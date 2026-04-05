#!/bin/sh
#==============================================================================
# 🎯 YouTube DNS/DPI Check for OpenWrt (POSIX sh)
# Проверка подмены DNS и блокировок доступа к googlevideo.com
#
# Совместимость: /bin/sh (BusyBox/Ash), OpenWrt
# Зависимости: nslookup (или dig), curl (или wget), grep, awk
# Использование: ./yt-check.sh
#==============================================================================

# ──────────────────────────────────────────────────────────────────────────
# 🎨 Цвета (автоопределение терминала)
# ──────────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    GREEN="\033[1;32m"
    RED="\033[1;31m"
    YELLOW="\033[1;33m"
    CYAN="\033[1;36m"
    MAGENTA="\033[1;35m"
    BLUE="\033[1;34m"
    BOLD="\033[1m"
    NC="\033[0m"
else
    GREEN="" RED="" YELLOW="" CYAN="" MAGENTA="" BLUE="" BOLD="" NC=""
fi

# ──────────────────────────────────────────────────────────────────────────
# ⚙️ Конфигурация
# ──────────────────────────────────────────────────────────────────────────
# Домены для проверки (через пробел)
DOMAINS="rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com rr1---sn-gvnuxaxjvh-jx3s.googlevideo.com"

# DNS серверы для сравнения (через пробел)
DNS_SERVERS="1.1.1.1 8.8.8.8 77.88.8.8 83.220.169.155 84.21.189.133"

# Локальный DoH/DoT (если используется dnscrypt-proxy/unbound), формат: IP#порт
DOH_SERVER="127.0.0.1#5053"

# Таймауты (сек)
TIMEOUT_DNS=3
TIMEOUT_CURL=5

# ──────────────────────────────────────────────────────────────────────────
# 🔧 Утилиты
# ──────────────────────────────────────────────────────────────────────────
log_info() { echo "${BLUE}[i]${NC} $*"; }
log_ok()   { echo "${GREEN}[✓]${NC} $*"; }
log_warn() { echo "${YELLOW}[!]${NC} $*"; }
log_err()  { echo "${RED}[✗]${NC} $*" >&2; }

# Получение первого IP адреса
# Аргументы: $1=домен, $2=сервер(опционально)
get_ip() {
    _domain="$1"
    _server="$2"
    _cmd=""
    
    # Пробуем dig (если установлен)
    if command -v dig >/dev/null 2>&1; then
        if [ -n "$_server" ]; then
            _cmd="dig +short +time=$TIMEOUT_DNS A $_domain @$_server"
        else
            _cmd="dig +short +time=$TIMEOUT_DNS A $_domain"
        fi
    # Пробуем nslookup (есть в базовом OpenWrt)
    elif command -v nslookup >/dev/null 2>&1; then
        if [ -n "$_server" ]; then
            _cmd="nslookup -type=A $_domain $_server"
        else
            _cmd="nslookup -type=A $_domain"
        fi
    else
        return 1
    fi
    
    # Парсинг вывода (универсальный для nslookup/dig)
    eval $_cmd 2>/dev/null | awk '/^Address: /{print $2} /^[0-9.]+$/{if($1 !~ /server|name/) print $1}' | grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}$' | head -n1
}

# Проверка доступности (DPI/Censorship)
check_access() {
    _domain="$1"
    _ip="$2"
    
    # 1. Проверка через curl с подменой резолва (--resolve)
    if command -v curl >/dev/null 2>&1; then
        # -s: silent, -o /dev/null: не выводить тело, -w: код ответа, -m: таймаут
        # --resolve: форсируем подключение к этому IP, но с этим именем хоста (SNI)
        _code=$(curl -s -o /dev/null -w "%{http_code}" -m "$TIMEOUT_CURL" \
                --resolve "$_domain:443:$_ip" \
                -H "User-Agent: Mozilla/5.0" \
                "https://$_domain/" 2>/dev/null)
        
        if [ "$_code" = "200" ] || [ "$_code" = "204" ] || [ "$_code" = "301" ] || [ "$_code" = "302" ]; then
            return 0
        fi
    # 2. Fallback на wget (если curl нет)
    elif command -v wget >/dev/null 2>&1; then
        # wget сложнее заставить использовать конкретный IP для проверки, 
        # поэтому пробуем просто соединение
        if wget --spider -T "$TIMEOUT_CURL" "https://$_domain/" -O /dev/null 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Простая проверка: является ли IP адресом Google (базовые подсети)
is_google_ip() {
    _ip="$1"
    # Google AS15169 диапазоны (упрощенно)
    case "$_ip" in
        8.*|172.21[0-9].*|172.25[0-3].*|142.25[0-1].*|173.194.*|216.58.*|74.125.*|35.19[0-1].*|108.177.*|142.250.*)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# ──────────────────────────────────────────────────────────────────────────
# 🚀 Основная логика
# ──────────────────────────────────────────────────────────────────────────
print_header() {
    echo ""
    echo "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo "${MAGENTA}${BOLD}║  🔍 YouTube Check (OpenWrt sh)       ║${NC}"
    echo "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Переменные статуса
GLOBAL_DNS_OK=1
GLOBAL_DPI_OK=1

main() {
    # Проверка зависимостей при старте
    if ! command -v nslookup >/dev/null 2>&1 && ! command -v dig >/dev/null 2>&1; then
        log_err "Требуется утилита nslookup или dig (пакет bind-dig или bind-utils)"
        exit 1
    fi
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        log_warn "Нет curl/wget. Пропускаем проверку доступа (DPI)."
        SKIP_DPI=1
    else
        SKIP_DPI=0
    fi

    print_header

    # Цикл по доменам (POSIX совместимый)
    for DOMAIN in $DOMAINS; do
        echo "${CYAN}${BOLD}📦 Проверка:${NC} $DOMAIN"
        echo "─────────────────────────────────────"

        # 1. Получаем системный IP
        SYS_IP=$(get_ip "$DOMAIN")
        
        if [ -z "$SYS_IP" ]; then
            echo "  Системный DNS: ${RED}НЕТ ОТВЕТА / БЛОК${NC}"
            GLOBAL_DNS_OK=0
            echo "  Доступ: ${YELLOW}ПРОПУЩЕНО${NC}"
            echo ""
            continue
        fi
        
        echo "  Системный IP : ${GREEN}$SYS_IP${NC}"
        
        # 2. Валидация: не подменен ли на "левый" сервер
        if ! is_google_ip "$SYS_IP"; then
            echo "  ⚠️ ${RED}IP не принадлежит Google! Возможна подмена.${NC}"
            GLOBAL_DNS_OK=0
        fi

        # 3. Сравнение с доверенными серверами
        MATCH_FOUND=0
        for DNS in $DNS_SERVERS; do
            TRUSTED_IP=$(get_ip "$DOMAIN" "$DNS")
            if [ -n "$TRUSTED_IP" ] && [ "$SYS_IP" = "$TRUSTED_IP" ]; then
                MATCH_FOUND=1
                break
            fi
        done
        
        # 4. Сравнение с локальным DoH (если настроен)
        if [ -n "$DOH_SERVER" ] && [ "$DOH_SERVER" != "127.0.0.1#5053" ] || [ -S "/var/run/dnscrypt-proxy/dnscrypt-proxy.sock" ]; then
            # Пытаемся резолвить через локальный прокси
            DOH_IP=$(get_ip "$DOMAIN" "${DOH_SERVER%%#*}") # берем только IP часть для nslookup
            if [ -n "$DOH_IP" ] && [ "$SYS_IP" != "$DOH_IP" ]; then
                 log_warn "Различие с локальным резолвером ($DOH_IP)"
            fi
        fi

        if [ $MATCH_FOUND -eq 1 ]; then
            echo "  Статус DNS   : ${GREEN}✅ OK (совпадает с публичными)${NC}"
        else
            echo "  Статус DNS   : ${YELLOW}⚠️ Различается с эталонами (возможно гео-CDN)${NC}"
        fi

        # 5. Проверка DPI (доступность)
        if [ "$SKIP_DPI" -eq 0 ]; then
            if check_access "$DOMAIN" "$SYS_IP"; then
                echo "  Доступ (DPI) : ${GREEN}✅ Работает${NC}"
            else
                echo "  Доступ (DPI) : ${RED}🚫 БЛОКИРОВКА / ОШИБКА${NC}"
                GLOBAL_DPI_OK=0
            fi
        else
            echo "  Доступ (DPI) : ${YELLOW}⊘ Нет инструментов${NC}"
        fi
        
        echo ""
    done

    # ──────────────────────────────────────────────────────────────────
    # Итоговый отчет
    # ──────────────────────────────────────────────────────────────────
    echo "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo "${MAGENTA}${BOLD}║  📊 ИТОГ                             ║${NC}"
    echo "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}"
    
    EXIT_CODE=0
    
    if [ $GLOBAL_DNS_OK -eq 1 ] && [ $GLOBAL_DPI_OK -eq 1 ]; then
        echo "  ${GREEN}[✓]${NC} DNS чист, трафик доступен."
        echo "  ${GREEN}🎉 YouTube работает корректно!${NC}"
    else
        if [ $GLOBAL_DNS_OK -eq 0 ]; then
            echo "  ${RED}[✗]${NC} Проблемы с DNS (подмена или блокировка)"
            EXIT_CODE=1
        fi
        if [ $GLOBAL_DPI_OK -eq 0 ]; then
            echo "  ${RED}[✗]${NC} Трафик блокируется (DPI / Reset)"
            EXIT_CODE=2
        fi
        echo ""
        echo "  ${YELLOW}💡 Совет:${NC}"
        echo "     1. Попробуйте сменить DNS в интерфейсе (1.1.1.1, 8.8.8.8)"
        echo "     2. Установите dnscrypt-proxy для шифрования запросов"
        echo "     3. Для обхода блокировок используйте GoodbyeDPI/Zapret"
    fi
    echo ""
    
    return $EXIT_CODE
}

# Запуск
main
exit $?
