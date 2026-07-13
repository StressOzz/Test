#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m'

HOST="raw.githubusercontent.com"
URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh"

BACKUP="/tmp/hosts_backup_github_test"

save_hosts() {
    cp /etc/hosts $BACKUP
}

restore_hosts() {
    cp $BACKUP /etc/hosts
    /etc/init.d/dnsmasq restart 2>/dev/null
    sleep 2
}

show_hosts() {
    echo -e "${YELLOW}┌─ /etc/hosts: github записи ─────────────┐${NC}"

    if grep -q "githubusercontent.com" /etc/hosts; then
        grep "githubusercontent.com" /etc/hosts | sed 's/^/│ /'
    else
        echo -e "│ ${GRAY}нет записей${NC}"
    fi

    echo -e "${YELLOW}└─────────────────────────────────────────┘${NC}"
}

test_net() {

TITLE="$1"

echo
echo -e "${CYAN}╔══════════════════════════════╗${NC}"
printf "${CYAN}║ %-28s ║${NC}\n" "$TITLE"
echo -e "${CYAN}╚══════════════════════════════╝${NC}"


echo -e "\n${YELLOW}[ DNS nslookup ]${NC}"
nslookup $HOST 2>/dev/null | grep Address | sed 's/^/  /'


echo -e "\n${YELLOW}[ CURL IPv4 HTTPS ]${NC}"

V4=$(curl -4 -sS \
-o /dev/null \
-w "HTTP=%{http_code} TIME=%{time_connect}s IP=%{remote_ip}" \
--connect-timeout 5 "$URL" 2>&1)


if echo "$V4" | grep -q "HTTP=200"; then
    echo -e "  ${GREEN}✓ $V4${NC}"
    IPV4="OK"
else
    echo -e "  ${RED}✗ $V4${NC}"
    IPV4="FAIL"
fi


echo -e "\n${YELLOW}[ CURL IPv6 HTTPS ]${NC}"

V6=$(curl -6 -sS \
-o /dev/null \
-w "HTTP=%{http_code} TIME=%{time_connect}s IP=%{remote_ip}" \
--connect-timeout 5 "$URL" 2>&1)


if echo "$V6" | grep -q "HTTP=200"; then
    echo -e "  ${GREEN}✓ $V6${NC}"
    IPV6="OK"
else
    echo -e "  ${RED}✗ $V6${NC}"
    IPV6="FAIL"
fi


echo "$IPV4/$IPV6"
}


echo -e "${CYAN}"
echo "╔══════════════════════════════════════╗"
echo "║          GitHub Hosts A/B Test       ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"


save_hosts


echo -e "${WHITE}Текущее состояние:${NC}"
show_hosts


echo
echo -e "${WHITE}┌─────────────── 1/3 ───────────────┐${NC}"
echo -e "${WHITE}│       Проверка без hosts           │${NC}"
echo -e "${WHITE}└───────────────────────────────────┘${NC}"

sed -i '/#githubusercontent.com/,+2d' /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2

RESULT_OFF=$(test_net "HOSTS OFF")


echo
echo -e "${WHITE}┌─────────────── 2/3 ───────────────┐${NC}"
echo -e "${WHITE}│       Проверка с hosts             │${NC}"
echo -e "${WHITE}└───────────────────────────────────┘${NC}"

git="githubusercontent.com"

printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts

/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2

show_hosts

RESULT_ON=$(test_net "HOSTS ON")


echo
echo -e "${WHITE}┌─────────────── 3/3 ───────────────┐${NC}"
echo -e "${WHITE}│       Восстановление hosts         │${NC}"
echo -e "${WHITE}└───────────────────────────────────┘${NC}"

restore_hosts

show_hosts

RESULT_BACK=$(test_net "AFTER RESTORE")


echo
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "${CYAN}              СРАВНЕНИЕ              ${NC}"
echo -e "${CYAN}══════════════════════════════════════${NC}"

echo
echo -e "${WHITE}HOSTS OFF:${NC} $RESULT_OFF"
echo -e "${WHITE}HOSTS ON :${NC} $RESULT_ON"
echo -e "${WHITE}RESTORE  :${NC} $RESULT_BACK"


echo

if echo "$RESULT_OFF" | grep -q "FAIL" && echo "$RESULT_ON" | grep -q "OK"; then
    echo -e "${YELLOW}✓ ВЫВОД: hosts улучшает доступ к GitHub.${NC}"
fi

if echo "$RESULT_OFF" | grep -q "OK" && echo "$RESULT_ON" | grep -q "OK"; then
    echo -e "${GREEN}✓ ВЫВОД: hosts не нужен.${NC}"
fi

echo
echo -e "${GREEN}✓ Оригинальный /etc/hosts восстановлен.${NC}"

rm -f $BACKUP
