#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh"

BACKUP="/tmp/hosts_backup"

cp /etc/hosts $BACKUP


test_github() {
    TITLE="$1"

    echo
    echo -e "${CYAN}========== $TITLE ==========${NC}"

    echo -e "${YELLOW}[ DNS ]${NC}"
    nslookup raw.githubusercontent.com 2>/dev/null | grep Address


    echo
    echo -e "${YELLOW}[ WGET TEST ]${NC}"

    START=$(date +%s)

    wget -O /tmp/github_test.tmp \
    --timeout=10 \
    "$URL" >/tmp/wget_test.log 2>&1

    CODE=$?

    END=$(date +%s)
    TIME=$((END-START))


    SIZE=$(wc -c </tmp/github_test.tmp 2>/dev/null)


    if [ $CODE -eq 0 ] && [ "$SIZE" -gt 100 ]; then
        echo -e "${GREEN}OK${NC}"
        echo "Размер: $SIZE bytes"
        echo "Время: ${TIME}s"
        return 0
    else
        echo -e "${RED}FAIL${NC}"
        echo "wget код: $CODE"
        echo "Время: ${TIME}s"
        echo
        tail -5 /tmp/wget_test.log
        return 1
    fi
}


echo -e "${CYAN}"
echo "╔══════════════════════════════╗"
echo "║ GitHub HOSTS A/B TEST        ║"
echo "╚══════════════════════════════╝"
echo -e "${NC}"


echo -e "${YELLOW}Текущие github записи:${NC}"
grep githubusercontent.com /etc/hosts || echo "нет"


echo
echo -e "${YELLOW}=== TEST 1: HOSTS OFF ===${NC}"

sed -i '/#githubusercontent.com/,+2d' /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2

test_github "HOSTS OFF"
OFF=$?


echo
echo -e "${YELLOW}=== TEST 2: HOSTS ON ===${NC}"

git="githubusercontent.com"

printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts

/etc/init.d/dnsmasq restart 2>/dev/null
sleep 2

test_github "HOSTS ON"
ON=$?


echo
echo -e "${YELLOW}=== RESTORE HOSTS ===${NC}"

cp $BACKUP /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null


echo
echo -e "${CYAN}========== RESULT ==========${NC}"

if [ $OFF -ne 0 ] && [ $ON -eq 0 ]; then
    echo -e "${GREEN}Вывод: hosts решает проблему.${NC}"
    echo "Рекомендуется оставить запись."
elif [ $OFF -eq 0 ] && [ $ON -eq 0 ]; then
    echo -e "${GREEN}Вывод: hosts не нужен.${NC}"
else
    echo -e "${RED}Вывод: GitHub недоступен даже с hosts.${NC}"
fi


echo
echo -e "${GREEN}Исходный /etc/hosts восстановлен.${NC}"

rm -f /tmp/github_test.tmp /tmp/wget_test.log
