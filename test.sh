#!/bin/bash
#==============================================================================
# 🎯 YouTube DNS/DPI Check Script
# Проверка подмены DNS и блокировок доступа к googlevideo.com
# 
# Использование: ./youtube-check.sh [--verbose] [--json] [--log FILE]
# Возврат: 0=OK, 1=DNS spoof, 2=DPI block, 3=error
#==============================================================================

set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────
# 🎨 Цвета и форматирование
# ──────────────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    GREEN="\033[1;32m"    RED="\033[1;31m"    YELLOW="\033[1;33m"
    CYAN="\033[1;36m"     MAGENTA="\033[1;35m"    BLUE="\033[1;34m"
    BOLD="\033[1m"        NC="\033[0m"
    ICON_OK="✓"  ICON_ERR="✗"  ICON_WARN="!"  ICON_INFO="•"
else
    GREEN="" RED="" YELLOW="" CYAN="" MAGENTA="" BLUE="" BOLD="" NC=""
    ICON_OK="[OK]" ICON_ERR="[ERR]" ICON_WARN="[!]" ICON_INFO="[i]"
fi

# ──────────────────────────────────────────────────────────────────────────
# ⚙️ Конфигурация
# ──────────────────────────────────────────────────────────────────────────
: "${TIMEOUT:=3}"
: "${TRIES:=2}"
: "${MIN_MATCH_PERCENT:=50}"

DOMAINS=(
    "rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"
    "rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com"
    "rr1---sn-gvnuxaxjvh-jx3s.googlevideo.com"
    "rr3---sn-gvnuxaxjvh-jx3e.googlevideo.com"
)

DNS_SERVERS=(
    "1.1.1.1"        # Cloudflare
    "8.8.8.8"        # Google
    "77.88.8.8"      # Yandex
    "83.220.169.155" # Comss.ru
    "84.21.189.133"  # Comss.ru
    "45.155.204.190" # Comss.ru
    "111.88.96.50"   # Comss.ru
)

DOH_SERVER="${DOH_SERVER:-127.0.0.1#5053}"  # dnscrypt-proxy / unbound

# ──────────────────────────────────────────────────────────────────────────
# 📊 Глобальные переменные и флаги
# ──────────────────────────────────────────────────────────────────────────
VERBOSE=0
JSON_MODE=0
LOG_FILE=""
FINAL_DNS_OK=1
FINAL_DPI_OK=1
declare -A IP_CACHE

# ──────────────────────────────────────────────────────────────────────────
# 🔧 Утилиты
# ──────────────────────────────────────────────────────────────────────────
log() {
    local level="$1"; shift
    local msg="[$(date '+%H:%M:%S')] [$level] $*"
    echo -e "$msg" >&2
    [ -n "$LOG_FILE" ] && echo "$msg" >> "$LOG_FILE"
}

die() {
    echo -e "${RED}${ICON_ERR} $*${NC}" >&2
    exit 3
}

check_deps() {
    local missing=()
    for cmd in curl timeout; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
    # dig/host/nslookup — хотя бы один
    if ! command -v dig >/dev/null 2>&1 && \
       ! command -v host >/dev/null 2>&1 && \
       ! command -v nslookup >/dev/null 2>&1; then
        missing+=("dig|host|nslookup")
    fi
    [ ${#missing[@]} -gt 0 ] && die "Отсутствуют зависимости: ${missing[*]}"
}

# ──────────────────────────────────────────────────────────────────────────
# 🌐 DNS функции
# ──────────────────────────────────────────────────────────────────────────
get_resolver_cmd() {
    if command -v dig >/dev/null 2>&1; then
        echo "dig"
    elif command -v host >/dev/null 2>&1; then
        echo "host"
    else
        echo "nslookup"
    fi
}

get_all_ips() {
    local domain="$1" server="${2:-}"
    local cache_key="${domain}:${server:-system}"
    
    # Кэширование
    [[ -n "${IP_CACHE[$cache_key]:-}" ]] && { echo "${IP_CACHE[$cache_key]}"; return 0; }
    
    local resolver=$(get_resolver_cmd)
    local result=""
    
    case "$resolver" in
        dig)
            local srv_flag="${server:+@$server}"
            result=$(dig +short +time="$TIMEOUT" +tries="$TRIES" A "$domain" $srv_flag 2>/dev/null | \
                     grep -E '^[0-9.]+$' | sort -u)
            ;;
        host)
            result=$(host -W "$TIMEOUT" -t A "$domain" ${server} 2>/dev/null | \
                     awk '/has address/{print $4}' | sort -u)
            ;;
        nslookup)
            result=$(nslookup -type=A "$domain" ${server} 2>/dev/null | \
                     awk '/^Address: /{print $2}' | grep -E '^[0-9.]+$' | sort -u)
            ;;
    esac
    
    IP_CACHE[$cache_key]="$result"
    echo "$result"
}

compare_ip_sets() {
    local set1="$1" set2="$2"
    [ -z "$set1" ] || [ -z "$set2" ] && return 1
    
    local common=$(comm -12 <(echo "$set1") <(echo "$set2") 2>/dev/null | wc -l)
    local total=$(echo -e "$set1\n$set2" | grep -v '^$' | sort -u | wc -l)
    
    [ "$total" -eq 0 ] && return 1
    local match_pct=$((common * 100 / total))
    [ "$match_pct" -ge "$MIN_MATCH_PERCENT" ]
}

is_google_ip() {
    local ip="$1"
    # Основные префиксы Google/YouTube (обновляйте при необходимости)
    echo "$ip" | grep -qE '^(8\.|172\.21[0-9]\.|172\.25[0-3]\.|142\.25[0-1]\.|173\.194\.|216\.58\.|74\.125\.|35\.19[0-1]\.|108\.177\.)' && return 0
    return 1
}

get_doh_ip() {
    local domain="$1"
    # Если DoH на localhost — используем get_all_ips с указанием сервера
    if [[ "$DOH_SERVER" =~ ^127\. ]]; then
        get_all_ips "$domain" "${DOH_SERVER%%#*}"
        return
    fi
    # Fallback: Cloudflare DoH API (требует jq)
    if command -v jq >/dev/null 2>&1; then
        curl -s --max-time "$TIMEOUT" \
             -H "accept: application/dns-json" \
             "https://1.1.1.1/dns-query?name=$domain&type=A" 2>/dev/null | \
             jq -r '.Answer[]? | select(.type==1) | .data' 2>/dev/null | sort -u
    else
        get_all_ips "$domain"  # fallback на системный
    fi
}

# ──────────────────────────────────────────────────────────────────────────
# 🔐 DPI / TLS проверки
# ──────────────────────────────────────────────────────────────────────────
check_tls_handshake() {
    local domain="$1" ip="$2"
    # Проверка TLS handshake с SNI и валидация сертификата
    echo | timeout 5 openssl s_client -connect "${ip}:443" -servername "$domain" \
         -verify_return_error 2>/dev/null | \
         grep -q "Verify return code: 0" && return 0
    return 1
}

check_http_access() {
    local domain="$1" ip="$2"
    # HTTP/2 запрос с реалистичными заголовками
    local http_code
    http_code=$(curl -m 5 -s -o /dev/null -w "%{http_code}" \
         --resolve "$domain:443:$ip" \
         -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
         -H "Accept: */*" \
         --http2 \
         "https://$domain/robots.txt" 2>/dev/null) || http_code="000"
    
    [[ "$http_code" =~ ^[23] ]] && return 0
    return 1
}

check_dpi() {
    local domain="$1" ip="$2"
    # Приоритет: проверка сертификата > HTTP доступ
    if check_tls_handshake "$domain" "$ip"; then
        return 0
    elif check_http_access "$domain" "$ip"; then
        return 0
    fi
    return 1
}

check_certificate() {
    local domain="$1" ip="$2"
    local cert_info
    cert_info=$(echo | timeout 5 openssl s_client -connect "${ip}:443" -servername "$domain" 2>/dev/null | \
                openssl x509 -noout -subject -issuer 2>/dev/null) || return 1
    echo "$cert_info" | grep -qiE "(Google|YouTube|GTS)" && return 0
    return 1
}

# ──────────────────────────────────────────────────────────────────────────
# 📋 Вывод результатов
# ──────────────────────────────────────────────────────────────────────────
print_header() {
    echo -e "\n${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║  🔍 YouTube DNS/DPI Check v2.0      ║${NC}"
    echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}\n"
}

print_domain_header() {
    echo -e "${CYAN}${BOLD}📦 Домен:${NC} $1"
    echo -e "${BLUE}─────────────────────────────────────${NC}"
}

print_result_line() {
    local label="$1" value="$2" color="${3:-$NC}"
    printf "  ${BOLD}%-14s${NC} ${color}%s${NC}\n" "$label:" "$value"
}

print_summary() {
    echo
    echo -e "${MAGENTA}${BOLD}╔════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}${BOLD}║  📊 ИТОГОВЫЙ ОТЧЁТ                   ║${NC}"
    echo -e "${MAGENTA}${BOLD}╚════════════════════════════════════════╝${NC}\n"
    
    if [ $FINAL_DNS_OK -eq 1 ] && [ $FINAL_DPI_OK -eq 1 ]; then
        echo -e "  ${GREEN}${ICON_OK} DNS не подменён${NC}"
        echo -e "  ${GREEN}${ICON_OK} Трафик доступен (DPI OK)${NC}"
        echo -e "\n${GREEN}${BOLD}🎉 Всё работает корректно!${NC}"
        return 0
    fi
    
    [ $FINAL_DNS_OK -eq 0 ] && echo -e "  ${RED}${ICON_ERR} Обнаружена подмена/блокировка DNS${NC}"
    [ $FINAL_DPI_OK -eq 0 ] && echo -e "  ${RED}${ICON_ERR} Трафик блокируется (DPI/провайдер)${NC}"
    
    echo -e "\n${YELLOW}${BOLD}💡 Рекомендации:${NC}"
    echo -e "  • Используйте DoH/DoT: ${CYAN}1.1.1.1${NC}, ${CYAN}8.8.8.8${NC}"
    echo -e "  • Попробуйте альтернативные DNS из списка"
    echo -e "  • Для обхода DPI: ${CYAN}GoodbyeDPI${NC}, ${CYAN}Zapret${NC}, ${CYAN}VPN${NC}"
    
    return 1
}

print_json_result() {
    local domain="$1" sys_ip="$2" doh_ip="$3" dns_status="$4" dpi_status="$5"
    cat <<EOF
{
  "domain": "$domain",
  "system_dns_ip": "${sys_ip:-null}",
  "doh_ip": "${doh_ip:-null}",
  "dns_status": "$dns_status",
  "dpi_status": "$dpi_status",
  "timestamp": "$(date -Iseconds)"
}
EOF
}

# ──────────────────────────────────────────────────────────────────────────
# 🔄 Основная логика проверки домена
# ──────────────────────────────────────────────────────────────────────────
check_domain() {
    local DOMAIN="$1"
    local sys_ips doh_ips dns_result dpi_result dns_color dpi_color
    
    print_domain_header "$DOMAIN"
    
    # Получаем IP от системного DNS и DoH
    sys_ips=$(get_all_ips "$DOMAIN")
    doh_ips=$(get_doh_ip "$DOMAIN")
    
    local sys_ip_first="${sys_ips%%$'\n'*}"
    local doh_ip_first="${doh_ips%%$'\n'*}"
    
    [ $VERBOSE -eq 1 ] && {
        print_result_line "Системный DNS" "${sys_ips:-НЕТ}" "$([ -n "$sys_ips" ] && echo $GREEN || echo $RED)"
        [ -n "$doh_ips" ] && print_result_line "DoH" "$doh_ips" "$GREEN"
    }
    
    # Сравниваем с публичными DNS
    local match_count=0 total_count=0
    for DNS in "${DNS_SERVERS[@]}"; do
        local dns_ips=$(get_all_ips "$DOMAIN" "$DNS")
        [ -z "$dns_ips" ] && continue
        
        total_count=$((total_count + 1))
        compare_ip_sets "$sys_ips" "$dns_ips" && match_count=$((match_count + 1))
        
        [ $VERBOSE -eq 1 ] && {
            local ip_display="${dns_ips%%$'\n'*}"
            local color=$GREEN
            is_google_ip "$ip_display" || color=$YELLOW
            print_result_line "$DNS" "$ip_display" "$color"
        }
    done
    
    # === Анализ DNS ===
    if [ -z "$sys_ips" ]; then
        dns_result="БЛОК/НЕТ ОТВЕТА"
        dns_color=$RED
        FINAL_DNS_OK=0
    elif [ -n "$doh_ips" ] && ! compare_ip_sets "$sys_ips" "$doh_ips"; then
        dns_result="⚠️ ПОДМЕНА DNS"
        dns_color=$RED
        FINAL_DNS_OK=0
    elif [ "$total_count" -gt 0 ] && [ "$match_count" -eq "$total_count" ]; then
        dns_result="✅ OK (совпадает с публичными)"
        dns_color=$GREEN
    elif [ "$total_count" -gt 0 ] && [ "$match_count" -gt 0 ]; then
        dns_result="🟡 Частичное совпадение (CDN)"
        dns_color=$YELLOW
    else
        dns_result="🔍 Разные CDN (возможно, норма)"
        dns_color=$YELLOW
    fi
    
    # Проверка принадлежности к Google
    if [ -n "$sys_ip_first" ] && ! is_google_ip "$sys_ip_first"; then
        dns_result="🚫 IP не принадлежит Google!"
        dns_color=$RED
        FINAL_DNS_OK=0
    fi
    
    print_result_line "DNS статус" "$dns_result" "$dns_color"
    
    # === DPI проверка ===
    if [ -n "$sys_ip_first" ]; then
        if check_dpi "$DOMAIN" "$sys_ip_first"; then
            # Доп. проверка сертификата
            if check_certificate "$DOMAIN" "$sys_ip_first"; then
                dpi_result="✅ Доступен + сертификат валиден"
                dpi_color=$GREEN
            else
                dpi_result="⚠️ Доступен, но сертификат подозрителен"
                dpi_color=$YELLOW
            fi
        else
            dpi_result="🚫 DPI / БЛОК ПРОВАЙДЕРА"
            dpi_color=$RED
            FINAL_DPI_OK=0
        fi
    else
        dpi_result="⊘ Пропущено (нет IP)"
        dpi_color=$YELLOW
        FINAL_DPI_OK=0
    fi
    
    print_result_line "Доступ" "$dpi_result" "$dpi_color"
    
    # JSON вывод если нужно
    [ $JSON_MODE -eq 1 ] && print_json_result "$DOMAIN" "$sys_ip_first" "$doh_ip_first" "$dns_result" "$dpi_result"
    
    echo -e "${MAGENTA}─────────────────────────────────────${NC}\n"
}

# ──────────────────────────────────────────────────────────────────────────
# 🚀 Main
# ──────────────────────────────────────────────────────────────────────────
main() {
    # Парсинг аргументов
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --verbose|-v) VERBOSE=1; shift ;;
            --json|-j) JSON_MODE=1; shift ;;
            --log) LOG_FILE="$2"; shift 2 ;;
            --help|-h)
                echo "Использование: $0 [--verbose] [--json] [--log FILE]"
                echo "  --verbose  Подробный вывод"
                echo "  --json     Вывод в JSON (для автоматизации)"
                echo "  --log FILE Запись лога в файл"
                exit 0
                ;;
            *) die "Неизвестный аргумент: $1" ;;
        esac
    done
    
    check_deps
    print_header
    
    [ -n "$LOG_FILE" ] && {
        echo "=== YouTube Check started $(date) ===" >> "$LOG_FILE"
        log "INFO" "Логирование в: $LOG_FILE"
    }
    
    log "INFO" "Проверка ${#DOMAINS[@]} доменов через ${#DNS_SERVERS[@]} DNS серверов"
    
    # Основной цикл
    for DOMAIN in "${DOMAINS[@]}"; do
        check_domain "$DOMAIN"
    done
    
    # Финальный отчёт (только если не JSON режим)
    [ $JSON_MODE -eq 0 ] && {
        print_summary
        local exit_code=0
        [ $FINAL_DNS_OK -eq 0 ] && exit_code=1
        [ $FINAL_DPI_OK -eq 0 ] && exit_code=2
        exit $exit_code
    }
}

# Запуск
main "$@"
