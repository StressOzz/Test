#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# Скрипт для установки, обновления и полного удаления Zapret на OpenWRT
# ==========================================

# Цвета для вывода
GREEN="\033[1;32m"       # Зеленый для успешных действий и статусов
RED="\033[1;31m"         # Красный для ошибок или остановленных процессов
CYAN="\033[1;36m"        # Голубой для информационных сообщений
YELLOW="\033[1;33m"      # Желтый для подчеркивания важных данных
MAGENTA="\033[1;35m"     # Фиолетовый для заголовков и названия скрипта
BLUE="\033[0;34m"        # Синий для завершения действий
NC="\033[0m"             # Сброс цвета
GRAY='\033[38;5;239m'    # Темно-серый для ссылок
DGRAY='\033[38;5;236m'   # Очень темный серый для версии

# Рабочая директория для скачивания и распаковки
WORKDIR="/tmp/zapret-update"  # Временная папка для загрузки архивов
LOG_FILE="/tmp/zapret-manager.log"

# ==========================================
# Вспомогательные функции
# ==========================================

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Функция вывода заголовка
show_header() {
    clear
    echo -e ""
    echo -e "╔════════════════════════════════════╗"
    echo -e "║     ${BLUE}Zapret on remittor Manager${NC}     ║"
    echo -e "╚════════════════════════════════════╝"
    echo -e "                                  ${DGRAY}v2.4${NC}"
    echo -e ""
}

# Функция проверки зависимостей
check_dependencies() {
    local deps="curl unzip"
    local missing=""
    
    for dep in $deps; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing="$missing $dep"
        fi
    done
    
    if [ -n "$missing" ]; then
        echo -e "${GREEN}🔴 ${CYAN}Устанавливаем зависимости:${NC}$missing"
        opkg update >/dev/null 2>&1
        for dep in $missing; do
            opkg install "$dep" >/dev/null 2>&1
        done
    fi
}

# Функция проверки свободного места
check_disk_space() {
    local required_mb=50
    local available_mb=$(df /tmp | awk 'NR==2 {print $4}')
    available_mb=$((available_mb/1024))
    
    if [ "$available_mb" -lt "$required_mb" ]; then
        echo -e "${RED}Недостаточно свободного места!${NC}"
        echo -e "${CYAN}Доступно: ${available_mb}MB, требуется: ${required_mb}MB${NC}"
        return 1
    fi
    return 0
}

# Функция валидации конфигурации
validate_config() {
    if [ -f /etc/config/zapret ]; then
        if uci show zapret >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Конфигурация valid${NC}"
            return 0
        else
            echo -e "${RED}✗ Ошибка в конфигурации!${NC}"
            return 1
        fi
    fi
    return 0
}

# Функция управления службой
manage_service() {
    local action=$1
    if [ -f /etc/init.d/zapret ]; then
        case $action in
            start)
                echo -e "${GREEN}🔴 ${CYAN}Запускаем сервис ${NC}Zapret"
                /etc/init.d/zapret start
                ;;
            stop)
                echo -e "${GREEN}🔴 ${CYAN}Останавливаем сервис ${NC}Zapret"
                /etc/init.d/zapret stop
                ;;
            restart)
                echo -e "${GREEN}🔴 ${CYAN}Перезапускаем сервис ${NC}Zapret"
                /etc/init.d/zapret restart
                ;;
        esac
        return 0
    else
        echo -e "${RED}Zapret не установлен!${NC}"
        return 1
    fi
}

# Функция завершения процессов Zapret
kill_zapret_processes() {
    PIDS=$(pgrep -f /opt/zapret)
    if [ -n "$PIDS" ]; then
        echo -e "${GREEN}🔴 ${CYAN}Завершаем процессы ${NC}Zapret"
        for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
    fi
}

# Функция определения архитектуры
get_architecture() {
    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release 2>/dev/null)
    
    if [ -z "$LOCAL_ARCH" ]; then
        LOCAL_ARCH=$(opkg print-architecture 2>/dev/null | awk '{print $2}' | head -1)
    fi
    
    # Резервный вариант
    if [ -z "$LOCAL_ARCH" ]; then
        LOCAL_ARCH=$(uname -m)
    fi
    
    echo "$LOCAL_ARCH"
}

# ==========================================
# Функция получения информации о версиях, архитектуре и статусе
# ==========================================
get_versions() {
    INSTALLED_VER=$(opkg list-installed | grep '^zapret ' | awk '{print $3}')
    [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"
    LOCAL_ARCH=$(get_architecture)

    check_dependencies

    LATEST_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases/latest \
        | grep browser_download_url | grep "$LOCAL_ARCH.zip" | cut -d '"' -f 4)
    PREV_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases \
        | grep browser_download_url | grep "$LOCAL_ARCH.zip" | sed -n '2p' | cut -d '"' -f 4)

    if [ -n "$LATEST_URL" ] && echo "$LATEST_URL" | grep -q '\.zip$'; then
        LATEST_FILE=$(basename "$LATEST_URL")
        LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
        USED_ARCH="$LOCAL_ARCH"
    else
        LATEST_VER="не найдена"
        USED_ARCH="нет пакета для вашей архитектуры"
    fi

    if [ -n "$PREV_URL" ] && echo "$PREV_URL" | grep -q '\.zip$'; then
        PREV_FILE=$(basename "$PREV_URL")
        PREV_VER=$(echo "$PREV_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
    else
        PREV_VER="не найдена"
    fi

    if [ -f /etc/init.d/zapret ]; then
        if /etc/init.d/zapret enabled && /etc/init.d/zapret status >/dev/null 2>&1; then
            ZAPRET_STATUS="${GREEN}запущен${NC}"
        else
            ZAPRET_STATUS="${RED}остановлен${NC}"
        fi
    else
        ZAPRET_STATUS=""
    fi
}

# ==========================================
# Установка Zapret
# ==========================================
install_update() {
    log_message "Начало установки/обновления Zapret"
    
    clear
    echo -e ""
    if [ "$INSTALLED_VER" != "не найдена" ]; then
        echo -e "${MAGENTA}Обновляем ZAPRET${NC}"
        ACTION="update"
    else
        echo -e "${MAGENTA}Устанавливаем ZAPRET${NC}"
        ACTION="install"
    fi
    echo -e ""
    get_versions

    # Проверка свободного места
    if ! check_disk_space; then
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    TARGET="$1"
    if [ "$TARGET" = "prev" ]; then
        TARGET_URL="$PREV_URL"
        TARGET_FILE="$PREV_FILE"
        TARGET_VER="$PREV_VER"
    else
        TARGET_URL="$LATEST_URL"
        TARGET_FILE="$LATEST_FILE"
        TARGET_VER="$LATEST_VER"
    fi

    [ "$USED_ARCH" = "нет пакета для вашей архитектуры" ] && {
        echo -e "${RED}Нет доступного пакета для вашей архитектуры: ${NC}$LOCAL_ARCH"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    }

    if [ "$INSTALLED_VER" = "$TARGET_VER" ]; then
        echo -e "${BLUE}🔴 ${GREEN}Эта версия уже установлена !${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 0
    fi

    # Остановка службы и процессов
    if [ -f /etc/init.d/zapret ]; then
        manage_service stop
        kill_zapret_processes
    fi

    mkdir -p "$WORKDIR" && cd "$WORKDIR" || return 1
    
    echo -e "${GREEN}🔴 ${CYAN}Скачиваем архив ${NC}$TARGET_FILE"
    if ! wget -q "$TARGET_URL" -O "$TARGET_FILE"; then
        echo -e "${RED}Ошибка скачивания ${NC}$TARGET_FILE"
        echo -e "${CYAN}Пробуем альтернативный URL...${NC}"
        # Можно добавить fallback URL здесь
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    echo -e "${GREEN}🔴 ${CYAN}Распаковываем архив${NC}"
    unzip -o "$TARGET_FILE" >/dev/null

    # Дополнительная проверка процессов
    kill_zapret_processes

    for PKG in zapret_*.ipk luci-app-zapret_*.ipk; do
        [ -f "$PKG" ] && {
            echo -e "${GREEN}🔴 ${CYAN}Устанавливаем пакет ${NC}$PKG"
            opkg install --force-reinstall "$PKG" >/dev/null 2>&1
        }
    done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы и пакеты${NC}"
    cd /
    rm -rf "$WORKDIR"
    rm -f /tmp/*.ipk /tmp/*.zip /tmp/*zapret* 2>/dev/null

    [ -f /etc/init.d/zapret ] && {
        echo -e "${GREEN}🔴 ${CYAN}Перезапуск службы ${NC}zapret"
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        manage_service restart
    }

    # Валидация конфигурации
    validate_config

    echo -e ""
    if [ "$ACTION" = "update" ]; then
        echo -e "${BLUE}🔴 ${GREEN}Zapret успешно обновлён !${NC}"
        log_message "Zapret успешно обновлен до версии $TARGET_VER"
    else
        echo -e "${BLUE}🔴 ${GREEN}Zapret успешно установлен !${NC}"
        log_message "Zapret успешно установлен версии $TARGET_VER"
    fi
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Чиним дефолтную стратегию
# ==========================================
fix_default() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Редактируем стратегию по умолчанию${NC}"
    echo -e ""

    # Проверка, установлен ли Zapret
    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен !${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    # Убираем все вхождения fake,
    sed -i 's/fake,//g' /etc/config/zapret

    # Удаляем конкретный блок строк
    sed -i '/--filter-tcp=80 <HOSTLIST>/,/--new/d' /etc/config/zapret

    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    manage_service restart

    # Валидация изменений
    validate_config

    echo -e "${BLUE}🔴 ${GREEN}Стратегия по умолчанию отредактирована !${NC}"
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Включение Discord и звонков в TG и WA
# ==========================================
enable_discord_calls() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Включаем Discord и звонки в TG и WA${NC}"
    echo -e ""

    # Проверка, установлен ли Zapret
    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен !${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    # Проверяем текущий установленный кастомный скрипт
    CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
    CURRENT_SCRIPT="не установлен"
    if [ -f "$CUSTOM_DIR/50-script.sh" ]; then
        FIRST_LINE=$(sed -n '1p' "$CUSTOM_DIR/50-script.sh")  # первая строка
        if echo "$FIRST_LINE" | grep -q "QUIC"; then
            CURRENT_SCRIPT="50-quic4all"
        elif echo "$FIRST_LINE" | grep -q "stun"; then
            CURRENT_SCRIPT="50-stun4all"
        else
            CURRENT_SCRIPT="неизвестный"
        fi
    fi

    echo -e "${YELLOW}Текущий установленный скрипт:${NC} $CURRENT_SCRIPT"
    echo -e ""

    # Предлагаем выбор скрипта для установки
    echo -e "${CYAN}1) ${GREEN}Установить скрипт ${NC}50-stun4all"
    echo -e "${CYAN}2) ${GREEN}Установить скрипт ${NC}50-quic4all"
    echo -e "${CYAN}3) ${GREEN}Выход в главное меню (Enter)${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice

    case "$choice" in
        1)
            SELECTED="50-stun4all"
            URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-stun4all"
            ;;
        2)
            SELECTED="50-quic4all"
            URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-quic4all"
            ;;
        3|"")
            # Выход в главное меню
            echo -e ""
            echo -e "${GREEN}Выходим в главное меню${NC}"
            return 0
            ;;
        *)
            # Любой другой ввод — просто выход
            echo -e ""
            echo -e "${GREEN}Выходим в главное меню${NC}"
            return 0
            ;;
    esac

    # Если выбранный уже установлен, не скачиваем
    if [ "$CURRENT_SCRIPT" = "$SELECTED" ]; then
        echo -e ""
        echo -e "${RED}Выбранный скрипт уже установлен !${NC}"
    else
        mkdir -p "$CUSTOM_DIR"
        if curl -fsSLo "$CUSTOM_DIR/50-script.sh" "$URL"; then
            echo -e ""
            echo -e "${GREEN}🔴 ${CYAN}Скрипт ${NC}$SELECTED${CYAN} успешно установлен !${NC}"
            chmod +x "$CUSTOM_DIR/50-script.sh"
            log_message "Установлен скрипт $SELECTED"
        else
            echo -e ""
            echo -e "${RED}Ошибка при скачивании скрипта !${NC}"
            echo -e ""
            read -p "Нажмите Enter для продолжения..." dummy
            return 1
        fi
    fi

    # Добавляем блок UDP, если его нет
    if ! grep -q -- "--filter-udp=50000-50099" /etc/config/zapret; then
        if ! grep -q '50000-50099' /etc/config/zapret; then
            sed -i "s/option NFQWS_PORTS_UDP '443'/option NFQWS_PORTS_UDP '443,50000-50099'/" /etc/config/zapret
        fi
        sed -i "/^'$/d" /etc/config/zapret
        printf -- '--new\n--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n' >> /etc/config/zapret
        echo "'" >> /etc/config/zapret
    fi
    
    # Синхронизация и перезапуск Zapret
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    manage_service restart
    
    # Валидация конфигурации
    validate_config

    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Звонки и Discord включены !${NC}"
    echo -e ""
    read -p "Нажмите Enter для продолжения..." dummy
}

# ==========================================
# Полное удаление Zapret
# ==========================================
uninstall_zapret() {
    log_message "Начало удаления Zapret"
    
    clear
    echo -e ""
    echo -e "${MAGENTA}Удаляем ZAPRET${NC}"
    echo -e ""

    # Остановка службы и процессов
    if [ -f /etc/init.d/zapret ]; then
        manage_service stop
    fi
    kill_zapret_processes

    echo -e "${GREEN}🔴 ${CYAN}Удаляем пакеты${NC} zapret ${CYAN}и ${NC}luci-app-zapret"
    opkg remove --force-removal-of-dependent-packages zapret luci-app-zapret >/dev/null 2>&1

    echo -e "${GREEN}🔴 ${CYAN}Удаляем конфигурации и рабочие папки${NC}"
    for path in /opt/zapret /etc/config/zapret /etc/firewall.zapret; do [ -e "$path" ] && rm -rf "$path"; done

    if crontab -l >/dev/null 2>&1; then
        crontab -l | grep -v -i "zapret" | crontab -
        echo -e "${GREEN}🔴 ${CYAN}Очищаем${NC} crontab ${CYAN}задания${NC}"
    fi

    echo -e "${GREEN}🔴 ${CYAN}Удаляем${NC} ipset"
    for set in $(ipset list -n 2>/dev/null | grep -i zapret); do ipset destroy "$set" >/dev/null 2>&1; done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы${NC}"
    rm -f /tmp/*zapret* /var/run/*zapret* 2>/dev/null

    echo -e "${GREEN}🔴 ${CYAN}Удаляем цепочки и таблицы${NC} nftables"
    for table in $(nft list tables 2>/dev/null | awk '{print $2}'); do
        chains=$(nft list table "$table" 2>/dev/null | grep zapret)
        [ -n "$chains" ] && nft delete table "$table" >/dev/null 2>&1
    done

    log_message "Zapret полностью удален"

    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Zapret полностью удалён !${NC}"
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Подменю управления службой
# ==========================================
service_management() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Управление службой Zapret${NC}"
    echo -e ""

    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен!${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    echo -e "${CYAN}1) ${GREEN}Запустить Zapret${NC}"
    echo -e "${CYAN}2) ${GREEN}Остановить Zapret${NC}"
    echo -e "${CYAN}3) ${GREEN}Перезапустить Zapret${NC}"
    echo -e "${CYAN}4) ${GREEN}Проверить статус${NC}"
    echo -e "${CYAN}5) ${GREEN}Выход в главное меню${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice

    case "$choice" in
        1)
            if manage_service start; then
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Zapret запущен!${NC}"
            fi
            ;;
        2)
            if manage_service stop; then
                kill_zapret_processes
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Zapret остановлен!${NC}"
            fi
            ;;
        3)
            if manage_service restart; then
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Zapret перезапущен!${NC}"
            fi
            ;;
        4)
            echo -e ""
            if /etc/init.d/zapret status; then
                echo -e ""
                echo -e "${GREEN}✓ Zapret работает${NC}"
            else
                echo -e ""
                echo -e "${RED}✗ Zapret не запущен${NC}"
            fi
            ;;
        5|"")
            return 0
            ;;
        *)
            echo -e "${RED}Неверный выбор!${NC}"
            ;;
    esac

    echo -e ""
    read -p "Нажмите Enter для продолжения..." dummy
}

# ==========================================
# Главное меню
# ==========================================
show_menu() {
    get_versions  # Получаем версии, архитектуру и статус службы

    show_header
    
    # Определяем актуальная/устарела
    if [ "$INSTALLED_VER" = "$LATEST_VER" ] && [ "$LATEST_VER" != "не найдена" ]; then
        INST_COLOR=$GREEN
        INSTALLED_DISPLAY="$INSTALLED_VER (актуальная)"
    elif [ "$LATEST_VER" = "не найдена" ]; then
        INST_COLOR=$CYAN
        INSTALLED_DISPLAY="$INSTALLED_VER"
    elif [ "$INSTALLED_VER" != "не найдена" ]; then
        INST_COLOR=$RED
        INSTALLED_DISPLAY="$INSTALLED_VER (устарела)"
    else
        INST_COLOR=$RED
        INSTALLED_DISPLAY="$INSTALLED_VER"
    fi

    # Вывод информации о версиях и архитектуре
    echo -e "${YELLOW}Установленная версия: ${INST_COLOR}$INSTALLED_DISPLAY${NC}"
    echo -e ""
    echo -e "${YELLOW}Последняя версия на GitHub: ${CYAN}$LATEST_VER${NC}"
    echo -e ""
    echo -e "${YELLOW}Архитектура устройства:${NC} $LOCAL_ARCH"
    
    # Выводим статус службы zapret, если он известен
    [ -n "$ZAPRET_STATUS" ] && echo -e "\n${YELLOW}Статус Zapret: ${NC}$ZAPRET_STATUS"

    # Проверяем, установлен ли кастомный скрипт
    CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
    CURRENT_SCRIPT=""
    if [ -f "$CUSTOM_DIR/50-script.sh" ]; then
        FIRST_LINE=$(sed -n '1p' "$CUSTOM_DIR/50-script.sh")
        if echo "$FIRST_LINE" | grep -q "QUIC"; then
            CURRENT_SCRIPT="50-quic4all"
        elif echo "$FIRST_LINE" | grep -q "stun"; then
            CURRENT_SCRIPT="50-stun4all"
        fi
    fi

    # Если скрипт найден, выводим строку
    [ -n "$CURRENT_SCRIPT" ] && echo -e "\n${YELLOW}Установлен скрипт: ${NC}$CURRENT_SCRIPT"

    echo -e ""

    # Вывод пунктов меню
    echo -e "${CYAN}1) ${GREEN}Установить/обновить Zapret${NC}"
    echo -e "${CYAN}2) ${GREEN}Оптимизировать стратегию по умолчанию${NC}"
    echo -e "${CYAN}3) ${GREEN}Вернуть настройки по умолчанию${NC}"
    echo -e "${CYAN}4) ${GREEN}Управление службой${NC}"
    echo -e "${CYAN}5) ${GREEN}Включить Discord и звонки в TG и WA ${RED}(test)${NC}"
    echo -e "${CYAN}6) ${GREEN}Удалить Zapret${NC}"
    echo -e "${CYAN}7) ${GREEN}Выход (Enter)${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice
    case "$choice" in
        1) install_update "latest" ;;  # Установка/обновление до последней версии
        2) fix_default ;;
        3)
            clear
            echo -e ""
            echo -e "${MAGENTA}Возвращаем настройки по умолчанию${NC}"
            echo -e ""
            # Проверка скрипта восстановления и его запуск
            if [ -f /opt/zapret/restore-def-cfg.sh ]; then
                rm -f /opt/zapret/init.d/openwrt/custom.d/50-script.sh
                manage_service stop
                kill_zapret_processes
                chmod +x /opt/zapret/restore-def-cfg.sh
                /opt/zapret/restore-def-cfg.sh
                chmod +x /opt/zapret/sync_config.sh
                /opt/zapret/sync_config.sh
                manage_service restart
                validate_config
                echo -e "${BLUE}🔴 ${GREEN}Настройки возвращены, сервис перезапущен !${NC}"
                log_message "Настройки возвращены к значениям по умолчанию"
            else
                echo -e "${RED}Zapret не установлен !${NC}"
            fi
            echo -e ""
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            ;;          
        4) service_management ;;
        5) enable_discord_calls ;;
        6) uninstall_zapret ;;
        7) 
            echo -e "${GREEN}Выход...${NC}"
            log_message "Завершение работы менеджера Zapret"
            exit 0 
            ;;
        *) 
            echo -e "${RED}Неверный выбор!${NC}"
            sleep 1
            ;;
    esac
}

# ==========================================
# Старт скрипта (цикл)
# ==========================================
log_message "Запуск менеджера Zapret"
while true; do
    show_menu  # Показываем главное меню бесконечно
done
