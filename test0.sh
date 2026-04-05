#!/bin/sh

# --- Цвета ---
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

DNS_LIST="
1.1.1.1
8.8.8.8
77.88.8.8
83.220.169.155
84.21.189.133
45.155.204.190
111.88.96.50
"

clear

get_ip4() {
    nslookup -type=A "$1" "$2" 2>/dev/null | awk '/^Address: /{print $2}' | grep -E '^[0-9.]+' | tail -n1
}

echo -e "${MAGENTA}Проверка googlevideo (YouTube)${NC}"
echo

FINAL_DNS_OK=1
FINAL_DPI_OK=1

for DOMAIN in $DOMAINS; do
    echo -e "${CYAN}Домен:${NC} $DOMAIN"

    SYS_IP=$(get_ip4 "$DOMAIN")

    echo -e "  Системный DNS : ${GREEN}${SYS_IP:-НЕТ}${NC}"

    MATCH=0
    TOTAL=0

    for DNS in $DNS_LIST; do
        IP=$(get_ip4 "$DOMAIN" "$DNS")
        [ -z "$IP" ] && continue

        echo -e "  ${YELLOW}$DNS${NC} : $IP"

        TOTAL=$((TOTAL+1))
        [ "$SYS_IP" = "$IP" ] && MATCH=$((MATCH+1))
    done

    # --- DNS анализ ---
    if [ -z "$SYS_IP" ]; then
        DNS_RESULT="БЛОК DNS"
        DNS_COLOR=$RED
        FINAL_DNS_OK=0
    elif [ $MATCH -eq $TOTAL ]; then
        DNS_RESULT="OK"
        DNS_COLOR=$GREEN
    else
        DNS_RESULT="РАЗНЫЕ CDN (норма)"
        DNS_COLOR=$YELLOW
    fi

    echo -e "  DNS: ${DNS_COLOR}$DNS_RESULT${NC}"

    # --- DPI проверка ---
    if [ -n "$SYS_IP" ]; then
        curl -m 5 -I --resolve "$DOMAIN:443:$SYS_IP" "https://$DOMAIN" >/dev/null 2>&1

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

    echo -e "  Доступ: ${DPI_COLOR}$DPI_RESULT${NC}"
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
