#!/bin/bash

set -euo pipefail

# =============================================================================
# КОНФИГУРАЦИЯ
# =============================================================================

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly LOCK_FILE="/var/run/zapret_config.lock"
readonly CONFIG_FILE="/opt/zapret/config"
readonly SERVICE_SCRIPT="/etc/init.d/zapret"
readonly LOG_FILE="/var/log/zapret_autoconfig.log"
readonly BACKUP_DIR="/opt/zapret/backups"

# Telegram уведомления
readonly TELEGRAM_BOT_TOKEN=""  # вставьте токен бота
readonly TELEGRAM_CHAT_ID=""    # вставьте ID чата

# Тестовые цели
readonly TEST_URLS=(
    "https://www.youtube.com"
    "https://youtube.com"
    "https://www.google.com"
)
readonly TEST_TIMEOUT=15
readonly MAX_ATTEMPTS=25
readonly RETRY_DELAY=3

# Параметры для рандомизации
readonly FILTER_TCP_OPTIONS=("80" "443" "80,443" "443,80")
readonly FILTER_UDP_OPTIONS=("443" "50000-65535" "50000-50100" "443,50000-50100")
readonly DPI_DESYNC_MODES=("fake" "fakedsplit" "multidisorder" "fakeddisorder" "split" "split2")
readonly DPI_DESYNC_FOOLING=("badsum" "md5sig" "badseq" "padencap" "none")
readonly DPI_DESYNC_REPEATS=("6" "8" "11" "16" "24" "32")
readonly DPI_DESYNC_TTLS=("2" "4" "8" "16")
readonly HOSTLISTS=(
    "/opt/zapret/ipset/zapret-hosts-google.txt"
    "/opt/zapret/ipset/zapret-hosts-user.txt"
    "/opt/zapret/ipset/zapret-hosts-user.txt /opt/zapret/ipset/zapret-hosts-google.txt"
)

# Веса для "умного" подбора (чем выше вес, тем чаще используется вариант)
declare -A CONFIG_WEIGHTS=(
    ["fake"]=3
    ["split"]=2
    ["fakedsplit"]=2
    ["multidisorder"]=1
    ["fakeddisorder"]=1
    ["split2"]=1
    ["badsum"]=2
    ["md5sig"]=1
    ["badseq"]=2
    ["padencap"]=1
    ["none"]=1
)

# =============================================================================
# ФУНКЦИИ ЛОГИРОВАНИЯ
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] [$level] $message" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_warn() {
    log "WARN" "$@"
}

log_error() {
    log "ERROR" "$@"
}

setup_logging() {
    local log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir"
    touch "$LOG_FILE"
    
    local backup_dir=$(dirname "$BACKUP_DIR")
    mkdir -p "$backup_dir"
}

# =============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =============================================================================

validate_environment() {
    local errors=0
    
    log_info "Проверка окружения..."
    
    # Проверка конфигурационного файла
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Конфигурационный файл не найден: $CONFIG_FILE"
        ((errors++))
    else
        log_info "Конфигурационный файл: OK"
    fi
    
    # Проверка скрипта сервиса
    if [[ ! -f "$SERVICE_SCRIPT" ]]; then
        log_error "Скрипт сервиса не найден: $SERVICE_SCRIPT"
        ((errors++))
    elif [[ ! -x "$SERVICE_SCRIPT" ]]; then
        log_error "Скрипт сервиса не исполняемый: $SERVICE_SCRIPT"
        ((errors++))
    else
        log_info "Скрипт сервиса: OK"
    fi
    
    # Проверка Telegram настроек
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        log_warn "Telegram токен или chat ID не настроены, уведомления отключены"
    else
        log_info "Telegram настройки: OK"
    fi
    
    # Проверка hostlist файлов
    local hostlist_errors=0
    for hostlist in "${HOSTLISTS[@]}"; do
        for file in $hostlist; do
            if [[ -n "$file" && ! -f "$file" ]]; then
                log_warn "Файл hostlist не найден: $file"
                ((hostlist_errors++))
            fi
        done
    done
    
    if [[ $hostlist_errors -eq 0 ]]; then
        log_info "Hostlist файлы: OK"
    fi
    
    # Проверка утилит
    local utils=("curl" "flock" "sed" "grep")
    for util in "${utils[@]}"; do
        if ! command -v "$util" &> /dev/null; then
            log_error "Утилита не найдена: $util"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        log_info "Все утилиты: OK"
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_error "Обнаружено $errors критических ошибок в окружении"
        return 1
    fi
    
    log_info "Проверка окружения завершена успешно"
    return 0
}

send_telegram() {
    local message="$1"
    
    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        return 0
    fi
    
    # Экранирование специальных символов для JSON
    local escaped_message=$(echo "$message" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\//\\\//g' -e 's/\n/\\n/g')
    
    local payload="{\"chat_id\":\"$TELEGRAM_CHAT_ID\",\"text\":\"$escaped_message\",\"parse_mode\":\"Markdown\"}"
    
    if curl_output=$(curl -s -w "%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" 2>/dev/null); then
        
        local http_code="${curl_output: -3}"
        if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
            log_info "Сообщение отправлено в Telegram"
            return 0
        else
            log_warn "Ошибка HTTP при отправке в Telegram: $http_code"
            return 1
        fi
    else
        log_warn "Не удалось отправить сообщение в Telegram"
        return 1
    fi
}

check_connectivity() {
    local url="$1"
    local retries=2
    local timeout=10
    
    for ((i=1; i<=retries; i++)); do
        if curl -s --max-time "$timeout" -I "$url" > /dev/null 2>&1; then
            log_info "URL доступен: $url (попытка $i/$retries)"
            return 0
        fi
        [[ $i -lt $retries ]] && sleep 2
    done
    
    log_info "URL недоступен: $url после $retries попыток"
    return 1
}

check_all_urls() {
    local available=0
    local total=${#TEST_URLS[@]}
    
    for url in "${TEST_URLS[@]}"; do
        if check_connectivity "$url"; then
            ((available++))
        fi
    done
    
    # Считаем успехом, если доступен хотя бы один URL
    if [[ $available -gt 0 ]]; then
        log_info "Доступно $available из $total тестовых URL"
        return 0
    else
        log_info "Ни один из тестовых URL не доступен"
        return 1
    fi
}

weighted_pick() {
    local -n options=$1
    local -n weights=$2
    local prefix=$3
    
    local total_weight=0
    local weighted_options=()
    
    # Создаем взвешенный список
    for option in "${options[@]}"; do
        local weight=${weights["$prefix$option"]:-1}
        for ((i=0; i<weight; i++)); do
            weighted_options+=("$option")
        done
        total_weight=$((total_weight + weight))
    done
    
    if [[ $total_weight -eq 0 ]]; then
        pick_random "${options[@]}"
    else
        pick_random "${weighted_options[@]}"
    fi
}

pick_random() {
    local items=("$@")
    local count=${#items[@]}
    
    if [[ $count -eq 0 ]]; then
        return 1
    fi
    
    local index=$((RANDOM % count))
    echo "${items[$index]}"
}

backup_config() {
    local backup_file="$BACKUP_DIR/zapret_config.backup.$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    if cp "$CONFIG_FILE" "$backup_file"; then
        log_info "Резервная копия конфига создана: $backup_file"
        echo "$backup_file"
    else
        log_error "Не удалось создать резервную копию конфига"
        return 1
    fi
}

restore_config() {
    local backup_file="$1"
    
    if [[ -f "$backup_file" ]]; then
        log_info "Восстановление конфига из резервной копии: $backup_file"
        cp "$backup_file" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
    else
        log_error "Резервная копия не найдена: $backup_file"
        return 1
    fi
}

generate_config() {
    local tcp_filter=$(pick_random "${FILTER_TCP_OPTIONS[@]}")
    local udp_filter=$(pick_random "${FILTER_UDP_OPTIONS[@]}")
    local dpi_mode=$(weighted_pick DPI_DESYNC_MODES CONFIG_WEIGHTS "")
    local dpi_fooling=$(weighted_pick DPI_DESYNC_FOOLING CONFIG_WEIGHTS "")
    local dpi_repeats=$(pick_random "${DPI_DESYNC_REPEATS[@]}")
    local dpi_ttl=$(pick_random "${DPI_DESYNC_TTLS[@]}")
    local hostlist=$(pick_random "${HOSTLISTS[@]}")
    
    log_info "Генерация конфигурации: mode=$dpi_mode, fooling=$dpi_fooling, repeats=$dpi_repeats"
    
    # Базовые опции TCP
    local config="--filter-tcp=$tcp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"
    config="$config --dpi-desync-autottl=$dpi_ttl"
    config="$config --dpi-desync-fooling=$dpi_fooling"
    config="$config --dpi-desync-repeats=$dpi_repeats"
    config="$config --new"
    
    # Опции UDP
    config="$config --filter-udp=$udp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"
    config="$config --dpi-desync-repeats=$dpi_repeats"
    
    echo "$config"
}

replace_config_line() {
    local new_value="$1"
    local temp_file=$(mktemp)
    
    log_info "Обновление конфигурационного файла"
    
    if grep -q "^NFQWS_OPT=" "$CONFIG_FILE"; then
        # Заменяем существующую строку
        sed "s|^NFQWS_OPT=.*|NFQWS_OPT=\"$new_value\"|" "$CONFIG_FILE" > "$temp_file"
    else
        # Добавляем новую строку в конец файла
        cp "$CONFIG_FILE" "$temp_file"
        echo "NFQWS_OPT=\"$new_value\"" >> "$temp_file"
    fi
    
    # Проверяем синтаксис перед применением
    if bash -n "$temp_file" 2>/dev/null; then
        cp "$temp_file" "$CONFIG_FILE"
        chmod 644 "$CONFIG_FILE"
        log_info "Конфигурационный файл успешно обновлен"
    else
        log_error "Ошибка синтаксиса в новом конфигурационном файле"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    return 0
}

restart_zapret() {
    log_info "Перезапуск сервиса Zapret..."
    
    # Останавливаем сервис
    if ! "$SERVICE_SCRIPT" stop > /dev/null 2>&1; then
        log_warn "Не удалось корректно остановить сервис, продолжаем..."
    fi
    
    sleep 3
    
    # Запускаем сервис
    if ! "$SERVICE_SCRIPT" start > /dev/null 2>&1; then
        log_error "Ошибка при запуске сервиса Zapret"
        return 1
    fi
    
    # Даем время на полный запуск
    log_info "Ожидание запуска сервиса..."
    sleep 25
    
    # Проверяем статус сервиса
    if ! "$SERVICE_SCRIPT" status > /dev/null 2>&1; then
        log_error "Сервис Zapret не запущен после перезапуска"
        return 1
    fi
    
    log_info "Сервис Zapret успешно перезапущен"
    return 0
}

# =============================================================================
# ОСНОВНАЯ ЛОГИКА
# =============================================================================

main_loop() {
    local attempt=0
    local success_config=""
    local original_backup=$(backup_config)
    
    # Статистика
    local tested_configs=()
    local working_configs=()
    
    log_info "Начало подбора конфигурации..."
    
    while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
        attempt=$((attempt + 1))
        log_info "Попытка подбора конфигурации #$attempt/$MAX_ATTEMPTS"
        
        # Генерация новой конфигурации
        local new_config
        if ! new_config=$(generate_config); then
            log_error "Ошибка генерации конфигурации"
            continue
        fi
        
        # Проверяем, не тестировали ли уже эту конфигурацию
        local config_hash=$(echo "$new_config" | md5sum | cut -d' ' -f1)
        if [[ " ${tested_configs[@]} " =~ " ${config_hash} " ]]; then
            log_info "Конфигурация уже тестировалась, пропускаем"
            continue
        fi
        tested_configs+=("$config_hash")
        
        # Применение конфигурации
        if ! replace_config_line "$new_config"; then
            log_error "Ошибка применения конфигурации"
            continue
        fi
        
        # Перезапуск сервиса
        if ! restart_zapret; then
            log_error "Ошибка перезапуска сервиса"
            
            # Пробуем восстановить рабочую конфигурацию
            if [[ -n "$original_backup" ]]; then
                log_info "Попытка восстановления исходной конфигурации"
                restore_config "$original_backup"
                restart_zapret
            fi
            continue
        fi
        
        # Проверка доступности
        log_info "Проверка доступности с новой конфигурацией..."
        if check_all_urls; then
            success_config="$new_config"
            working_configs+=("$new_config")
            log_info "Успешная конфигурация найдена на попытке #$attempt"
            
            # Сохраняем рабочую конфигурацию
            local working_backup="$BACKUP_DIR/zapret_working_$(date +%Y%m%d_%H%M%S).config"
            echo "$new_config" > "$working_backup"
            log_info "Рабочая конфигурация сохранена: $working_backup"
            
            break
        fi
        
        log_info "Конфигурация не сработала, продолжаем поиск..."
        sleep "$RETRY_DELAY"
    done
    
    # Формирование результата
    if [[ -n "$success_config" ]]; then
        local message="✅ *Zapret обход настроен успешно!*
        
*Попытка:* #$attempt/$MAX_ATTEMPTS
*Конфигурация:* \`$success_config\`
*Тестовые URL:* ${#TEST_URLS[@]} проверено
*Время:* $(date '+%Y-%m-%d %H:%M:%S')"
        
        send_telegram "$message"
        log_info "Успешная конфигурация найдена и применена"
        return 0
    else
        local message="❌ *Zapret обход НЕ удалось настроить!*
        
*Попыток:* $MAX_ATTEMPTS
*Протестировано конфигураций:* ${#tested_configs[@]}
*Рабочих конфигураций:* ${#working_configs[@]}
*Время:* $(date '+%Y-%m-%d %H:%M:%S')
        
Требуется ручное вмешательство или анализ логов."
        
        send_telegram "$message"
        
        # Восстанавливаем исходную конфигурацию
        if [[ -n "$original_backup" ]]; then
            log_info "Восстановление исходной конфигурации"
            restore_config "$original_backup"
            restart_zapret
        fi
        
        log_error "Не удалось подобрать рабочую конфигурацию после $MAX_ATTEMPTS попыток"
        return 1
    fi
}

cleanup() {
    log_info "Завершение работы скрипта"
    rm -f "$LOCK_FILE"
    exit 0
}

show_usage() {
    cat << EOF
Использование: $SCRIPT_NAME [OPTIONS]

Автоматический подбор конфигурации для обхода блокировок через Zapret.

OPTIONS:
    -h, --help      Показать эту справку
    -v, --verbose   Подробный вывод
    --test-only     Только проверить доступность, не менять конфигурацию
    --force         Запуск даже если сервис доступен

Примеры:
    $SCRIPT_NAME                    # Обычный запуск
    $SCRIPT_NAME --test-only        # Только проверка
    $SCRIPT_NAME --force            # Принудительный запуск

Логи: $LOG_FILE
EOF
}

# =============================================================================
# ОСНОВНАЯ ПРОГРАММА
# =============================================================================

main() {
    local test_only=false
    local force=false
    
    # Разбор аргументов командной строки
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -v|--verbose)
                set -x
                ;;
            --test-only)
                test_only=true
                ;;
            --force)
                force=true
                ;;
            *)
                log_error "Неизвестный аргумент: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    
    # Настройка логирования
    setup_logging
    
    log_info "Запуск скрипта автоматической настройки Zapret"
    log_info "Параметры: test_only=$test_only, force=$force"
    
    # Проверка окружения
    if ! validate_environment; then
        log_error "Критические ошибки в окружении, завершение работы"
        send_telegram "❌ Ошибка окружения при запуске скрипта Zapret"
        exit 1
    fi
    
    # Проверка блокировки
    if ! flock -n 9; then
        log_error "Скрипт уже запущен, выход"
        send_telegram "⚠️ Скрипт настройки Zapret уже запущен"
        exit 1
    fi
    
    # Проверка доступности перед началом работы
    log_info "Проверка доступности тестовых URL..."
    if check_all_urls; then
        if [[ "$force" != true ]]; then
            log_info "Тестовые URL доступны, обход не требуется"
            send_telegram "✅ Тестовые URL доступны, обход не требуется"
            exit 0
        else
            log_info "Тестовые URL доступны, но запуск принудительный"
        fi
    else
        log_info "Тестовые URL недоступны, начинаем подбор конфигурации"
    fi
    
    if [[ "$test_only" == true ]]; then
        log_info "Режим тестирования, конфигурация не изменяется"
        exit 0
    fi
    
    # Запуск основного цикла подбора
    log_info "Запуск основного цикла подбора конфигурации..."
    send_telegram "⚠️ *Начинаем автоматический подбор конфигурации Zapret*
    
*Тестовые URL:* ${#TEST_URLS[@]}
*Максимум попыток:* $MAX_ATTEMPTS
*Время начала:* $(date '+%Y-%m-%d %H:%M:%S')"
    
    if main_loop; then
        log_info "Скрипт завершил работу успешно"
        exit 0
    else
        log_error "Скрипт завершил работу с ошибкой"
        exit 1
    fi
}

# Установка обработчиков
trap cleanup EXIT INT TERM

# Проверка на bash
if [[ -z "$BASH_VERSION" ]]; then
    echo "Ошибка: Этот скрипт требует Bash для выполнения" >&2
    exit 1
fi

# Запуск с блокировкой
exec 9>"$LOCK_FILE"
if flock -n 9; then
    main "$@"
else
    echo "Ошибка: Скрипт уже запущен" >&2
    exit 1
fi
