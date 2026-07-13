#!/bin/sh
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

HOST="raw.githubusercontent.com"
URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh"

RESULT1=""
RESULT2=""

check() {
    TITLE="$1"

    echo -e "\n${CYAN}========== $TITLE ==========${NC}"

    echo -e "\n${YELLOW}[ DNS nslookup ]${NC}"
    DNS=$(nslookup $HOST 2>/dev/null | grep "Address:" | tail -n +2)

    if [ -n "$DNS" ]; then
        echo -e "${GREEN}$DNS${NC}"
    else
        echo -e "${RED}DNS ERROR${NC}"
    fi


    echo -e "\n${YELLOW}[ CURL IPv4 ]${NC}"
    IPV4=$(curl -4 -sS -o /dev/null \
    -w "HTTP:%{http_code}  TIME:%{time_connect}s  IP:%{remote_ip}" \
    --connect-timeout 5 "$URL" 2>&1)

    if echo "$IPV4" | grep -q "HTTP:200"; then
        echo -e "${GREEN}$IPV4${NC}"
        STATUS="OK"
    else
        echo -e "${RED}$IPV4${NC}"
        STATUS="FAIL"
    fi


    echo -e "\n${YELLOW}[ CURL IPv6 ]${NC}"
    IPV6=$(curl -6 -sS -o /dev/null \
    -w "HTTP:%{http_code}  TIME:%{time_connect}s  IP:%{remote_ip}" \
    --connect-timeout 5 "$URL" 2>&1)

    if echo "$IPV6" | grep -q "HTTP:200"; then
        echo -e "${GREEN}$IPV6${NC}"
    else
        echo -e "${RED}$IPV6${NC}"
    fi

    echo "$STATUS"
}


echo -e "${CYAN}
╔══════════════════════════════╗
║   GitHub Raw Access Test     ║
╚══════════════════════════════╝
${NC}"


echo -e "${YELLOW}1) Проверка без hosts${NC}"
RESULT1=$(check "ORIGINAL")


echo -e "\n${YELLOW}2) Добавление githubusercontent hosts${NC}"

git="githubusercontent.com"

grep -q "raw.$git" /etc/hosts || {
printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null
}

sleep 2

RESULT2=$(check "WITH HOSTS")


echo -e "\n${YELLOW}3) Удаление hosts${NC}"

sed -i '/#githubusercontent.com/,+2d' /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null

sleep 2


check "AFTER REMOVE"


echo -e "\n${CYAN}========== ИТОГ ==========${NC}"

if [ "$RESULT1" = "OK" ] && [ "$RESULT2" = "OK" ]; then
    echo -e "${GREEN}Доступ к GitHub работает. hosts не нужен.${NC}"

elif [ "$RESULT1" = "FAIL" ] && [ "$RESULT2" = "OK" ]; then
    echo -e "${YELLOW}hosts помогает. Проблема связана с DNS/маршрутом.${NC}"

elif [ "$RESULT1" = "FAIL" ] && [ "$RESULT2" = "FAIL" ]; then
    echo -e "${RED}GitHub недоступен. Проблема HTTPS/провайдер/Zapret.${NC}"

else
    echo -e "${YELLOW}Нестандартный результат, нужна дополнительная проверка.${NC}"
fi
