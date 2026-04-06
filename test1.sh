#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
NC="\033[0m"

DOMAINS="
rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com
rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com
rr1---sn-gvnuxaxjvh-jx3s.googlevideo.com
"

# Убираем пустые строки
DOMAINS=$(echo "$DOMAINS" | grep -v '^$')

DNS_LIST="
1.1.1.1
8.8.8.8
77.88.8.8
83.220.169.155
84.21.189.133
45.155.204.190
111.88.96.50
"

if ! command -v dig >/dev/null 2>&1; then
    echo -e "${YELLOW}Устанавливаем ${NC}dig"
    if command -v opkg >/dev/null 2>&1; then
        opkg update >/dev/null 2>&1
        opkg install bind-dig >/dev/null 2>&1
    elif command -v apk >/dev/null 2>&1; then
        apk update >/dev/null 2>&1
        apk add bind-dig >/dev/null 2>&1
    else
        echo -e "${RED}Не удалось установить ${NC}dig${RED}!${NC}"
        exit 1
    fi
fi

clear

get_ip4() {
    local domain=$1
    local server=$2
    local cmd="dig +short A $domain +time=2 +tries=1"
    [ -n "$server" ] && cmd="dig @$server +short A $domain +time=2 +tries=1"
    $cmd 2>/dev/null | grep -E '^[0-9.]+' | sort -u
}

pad() {
    printf "%-14s" "$1"
}

echo -e "${MAGENTA}Проверка googlevideo (YouTube)${NC}"
echo

FINAL_DNS_OK=1
FINAL_DPI_OK=1

for DOMAIN in $DOMAINS; do
    echo -e "${CYAN}Домен:${NC} $DOMAIN"

    SYS_IPS=$(get_ip4 "$DOMAIN")
    echo -e "  Системный DNS  : ${GREEN}$(echo $SYS_IPS | tr '\n' ' ')${NC}"

    MATCH=0
    TOTAL=0

    for DNS in $DNS_LIST; do
        DNS_IPS=$(get_ip4 "$DOMAIN" "$DNS")
        [ -z "$DNS_IPS" ] && continue

        echo -e "  ${YELLOW}$(pad $DNS)${NC} : $(echo $DNS_IPS | tr '\n' ' ')"

        TOTAL=$((TOTAL+1))
        INTERSECT=$(echo "$SYS_IPS" "$DNS_IPS" | tr ' ' '\n' | sort | uniq -d)
        [ -n "$INTERSECT" ] && MATCH=$((MATCH+1))
    done

    if [ -z "$SYS_IPS" ]; then
        DNS_RESULT="Блок DNS"
        DNS_COLOR=$RED
        FINAL_DNS_OK=0
    elif [ $MATCH -eq $TOTAL ]; then
        DNS_RESULT="OK"
        DNS_COLOR=$GREEN
    else
        DNS_RESULT="Разные CDN (норма)"
        DNS_COLOR=$YELLOW
    fi

    echo -e "${CYAN}DNS: ${DNS_COLOR}$DNS_RESULT${NC}"

    if [ -n "$SYS_IPS" ]; then
        curl -m 5 -I --resolve "$DOMAIN:443:$(echo $SYS_IPS | awk '{print $1}')" "https://$DOMAIN" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            DPI_RESULT="OK"
            DPI_COLOR=$GREEN
        else
            DPI_RESULT="Блокировка"
            DPI_COLOR=$RED
            FINAL_DPI_OK=0
        fi
    else
        DPI_RESULT="НЕ ВОЗМОЖНО ОПРЕДЕЛИТЬ"
        DPI_COLOR=$YELLOW
        FINAL_DPI_OK=0
    fi

    echo -e "${CYAN}Доступ: ${DPI_COLOR}$DPI_RESULT${NC}"
    echo -e "${MAGENTA}----------------------------------------${NC}"
done

echo -e "\n${MAGENTA}Итог тестирования:${NC}"
if [ $FINAL_DNS_OK -eq 1 ] && [ $FINAL_DPI_OK -eq 1 ]; then
    echo -e " ${GREEN}[✓]${NC} ${CYAN}DNS не подменён, трафик доступен${NC}"
elif [ $FINAL_DNS_OK -eq 0 ]; then
    echo -e " ${RED}[✗]${NC} ${CYAN}DNS подменяется / блокируется${NC}"
elif [ $FINAL_DPI_OK -eq 0 ]; then
    echo -e " ${RED}[✗]${NC} ${CYAN}Трафик блокируется провайдером${NC}"
else
    echo -e "${YELLOW}[!]${NC} ${CYAN}Результат неполный / сомнительный${NC}"
fi
echo
