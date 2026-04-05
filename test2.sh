#!/bin/sh
#============================================================================== 
# 🎯 YouTube DNS/DPI Check Script (OpenWrt compatible)
#==============================================================================

GREEN="\033[1;32m" RED="\033[1;31m" YELLOW="\033[1;33m" CYAN="\033[1;36m" NC="\033[0m"
ICON_OK="✓" ICON_ERR="✗"

TIMEOUT=3
TRIES=2
MIN_MATCH_PERCENT=50

DOMAINS="rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com"
DNS_SERVERS="1.1.1.1 8.8.8.8 77.88.8.8"

#------------------------------------------------------------------------------ 
# Проверка зависимостей
#------------------------------------------------------------------------------
check_deps() {
    for cmd in dig curl timeout openssl; do
        command -v $cmd >/dev/null 2>&1 || { echo "❌ Отсутствует $cmd"; exit 1; }
    done
}

#------------------------------------------------------------------------------ 
# Получение IP с DNS
#------------------------------------------------------------------------------
get_all_ips() {
    DOMAIN="$1"
    SERVER="$2"
    SRV=""
    [ -n "$SERVER" ] && SRV="@$SERVER"
    dig +short +time=$TIMEOUT +tries=$TRIES A "$DOMAIN" $SRV 2>/dev/null | grep -E '^[0-9.]+' | sort -u
}

#------------------------------------------------------------------------------ 
# Сравнение двух наборов IP
#------------------------------------------------------------------------------
compare_ip_sets() {
    set1="$1"
    set2="$2"
    [ -z "$set1" ] || [ -z "$set2" ] && return 1
    common=$(comm -12 <(echo "$set1") <(echo "$set2") 2>/dev/null | wc -l)
    total=$(echo -e "$set1\n$set2" | grep -v '^$' | sort -u | wc -l)
    [ "$total" -eq 0 ] && return 1
    pct=$((common * 100 / total))
    [ "$pct" -ge "$MIN_MATCH_PERCENT" ] && return 0 || return 1
}

#------------------------------------------------------------------------------ 
# Простая проверка HTTPS (TLS handshake)
#------------------------------------------------------------------------------
check_tls_handshake() {
    DOMAIN="$1"
    IP="$2"
    echo | timeout $TIMEOUT openssl s_client -connect "$IP:443" -servername "$DOMAIN" 2>/dev/null | grep -q "Verify return code: 0"
}

#------------------------------------------------------------------------------ 
# Проверка домена
#------------------------------------------------------------------------------
check_domain() {
    DOMAIN="$1"
    echo -e "${CYAN}📦 Проверка домена:${NC} $DOMAIN"
    echo "───────────────────────────────"

    SYS_IPS=$(get_all_ips "$DOMAIN")
    [ -z "$SYS_IPS" ] && echo -e "${RED}Системный DNS: нет ответа${NC}" || echo "Системный DNS: $SYS_IPS"

    for DNS in $DNS_SERVERS; do
        DNS_IPS=$(get_all_ips "$DOMAIN" "$DNS")
        echo -n "$DNS: $DNS_IPS"
        compare_ip_sets "$SYS_IPS" "$DNS_IPS" && echo -e " ${GREEN}${ICON_OK} совпадает${NC}" || echo -e " ${RED}${ICON_ERR} отличается${NC}"
    done

    # Проверка TLS
    FIRST_IP=$(echo "$SYS_IPS" | head -n1)
    if [ -n "$FIRST_IP" ]; then
        if check_tls_handshake "$DOMAIN" "$FIRST_IP"; then
            echo -e "Доступ HTTPS: ${GREEN}${ICON_OK} успешный${NC}"
        else
            echo -e "Доступ HTTPS: ${RED}${ICON_ERR} блок/ошибка${NC}"
        fi
    else
        echo -e "Доступ HTTPS: ${YELLOW}! пропущено (нет IP)${NC}"
    fi

    echo "───────────────────────────────"
    echo
}

#------------------------------------------------------------------------------ 
# Main
#------------------------------------------------------------------------------
check_deps
for D in $DOMAINS; do
    check_domain $D
done
