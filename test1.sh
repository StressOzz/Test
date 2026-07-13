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

BACKUP="/tmp/hosts_github_backup"

OK="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"

line() {
    echo -e "${GRAY}──────────────────────────────────────${NC}"
}

title() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
    printf "${CYAN}║ %-36s ║${NC}\n" "$1"
    echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
}

save_hosts() {
    cp /etc/hosts "$BACKUP"
}

restore_hosts() {
    cp "$BACKUP" /etc/hosts
    /etc/init.d/dnsmasq restart 2>/dev/null
    sleep 2
}

show_hosts() {
    if grep -q "githubusercontent.com" /etc/hosts; then
        echo -e "${GREEN}✓ Найдена запись githubusercontent.com${NC}"
        grep "githubusercontent.com" /etc/hosts | sed 's/^/  /'
    else
        echo -e "${YELLOW}• Записей githubusercontent.com нет${NC}"
    fi
}

test_net() {

    MODE="$1"

    title "$MODE"

    echo -e "${YELLOW}DNS:${NC}"
    nslookup "$HOST" 2>/dev/null | grep "Address:" | tail -n +2 | sed 's/^/  /'


    echo
    echo -e "${YELLOW}IPv4 HTTPS:${NC}"

    V4=$(curl -4 -sS \
    -o /dev/null \
    -w "HTTP=%{http_code} TIME=%{time_connect}s IP=%{remote_ip}" \
    --connect-timeout 5 "$URL" 2>&1)


    if echo "$V4" | grep -q "HTTP=000"; then
        echo -e "  ${FAIL} ${RED}$V4${NC}"
        IPV4="FAIL"
    else
        echo -e "  ${OK} ${GREEN}$V4${NC}"
        IPV4="OK"
    fi


    echo
    echo -e "${YELLOW}IPv6 HTTPS:${NC}"

    V6=$(curl -6 -sS \
    -o /dev/null \
    -w "HTTP=%{http_code} TIME=%{time_connect}s IP=%{remote_ip}" \
    --connect-timeout 5 "$URL" 2>&1)


    if echo "$V6" | grep -q "HTTP=000"; then
        echo -e "  ${FAIL} ${RED}$V6${NC}"
        IPV6="FAIL"
    else
        echo -e "  ${OK} ${GREEN}$V6${NC}"
        IPV6="OK"
    fi

    TEST_RESULT="$IPV4/$IPV6"
}


echo -e "${WHITE}"
echo "╔══════════════════════════════════════╗"
echo "║        GitHub Hosts A/B Test         ║"
echo "╚══════════════════════════════════════╝"
echo -e "${NC}"


save_hosts


echo -e "${WHITE}Текущее состояние /etc/hosts${NC}"
line
show_hosts
line


# ---------------- OFF ----------------

echo -e "\n${WHITE}[1/3] Проверка без hosts${NC}"

sed -i '/#githubusercontent.com/,+2d' /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2

test_net "HOSTS OFF"

OFF_RESULT="$TEST_RESULT"


# ---------------- ON ----------------

echo
echo -e "${WHITE}[2/3] Проверка с hosts${NC}"

git="githubusercontent.com"

if ! grep -q "raw.$git" /etc/hosts; then
    printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts
fi

/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2


show_hosts

test_net "HOSTS ON"

ON_RESULT="$TEST_RESULT"


# ---------------- RESTORE ----------------

echo
echo -e "${WHITE}[3/3] Восстановление${NC}"

restore_hosts

if cmp -s /etc/hosts "$BACKUP"; then
    echo -e "${GREEN}✓ /etc/hosts восстановлен${NC}"
else
    echo -e "${RED}✗ Ошибка восстановления${NC}"
fi


# ---------------- RESULT ----------------

echo
echo -e "${CYAN}══════════════════════════════════════${NC}"
echo -e "${CYAN}               ИТОГ                  ${NC}"
echo -e "${CYAN}══════════════════════════════════════${NC}"

echo -e "HOSTS OFF : $OFF_RESULT"
echo -e "HOSTS ON  : $ON_RESULT"

echo

OFF4=$(echo "$OFF_RESULT" | cut -d/ -f1)
ON4=$(echo "$ON_RESULT" | cut -d/ -f1)

if [ "$OFF4" = "FAIL" ] && [ "$ON4" = "OK" ]; then
    echo -e "${GREEN}✓ Запись hosts решает проблему доступа${NC}"
elif [ "$OFF4" = "OK" ] && [ "$ON4" = "OK" ]; then
    echo -e "${YELLOW}• hosts не влияет на доступ${NC}"
else
    echo -e "${RED}✗ Требуется дополнительная проверка${NC}"
fi


rm -f "$BACKUP"

echo
echo -e "${GREEN}Готово.${NC}"
