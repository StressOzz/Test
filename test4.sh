#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

HOST="raw.githubusercontent.com"
URL="https://raw.githubusercontent.com/StressOzz/Test/main/test1.sh"

BACKUP="/tmp/hosts.github.test"

cp /etc/hosts $BACKUP

test_curl() {
    TITLE="$1"

    echo -e "\n${CYAN}========== $TITLE ==========${NC}"

    echo -e "\n${YELLOW}[ nslookup ]${NC}"
    nslookup $HOST 2>/dev/null | grep Address

    echo -e "\n${YELLOW}[ curl IPv4 ]${NC}"

    RES=$(curl -4 -sS -o /dev/null \
    -w "HTTP:%{http_code} TIME:%{time_connect}s IP:%{remote_ip}" \
    --connect-timeout 5 "$URL" 2>&1)

    if echo "$RES" | grep -q "HTTP:200"; then
        echo -e "${GREEN}$RES${NC}"
        return 0
    else
        echo -e "${RED}$RES${NC}"
        return 1
    fi
}


echo -e "${CYAN}"
echo "╔══════════════════════════════╗"
echo "║ GitHub hosts compare test    ║"
echo "╚══════════════════════════════╝"
echo -e "${NC}"


echo -e "${YELLOW}Текущие записи hosts:${NC}"

if grep -q "githubusercontent.com" /etc/hosts; then
    grep "githubusercontent.com" /etc/hosts
else
    echo "Нет записей"
fi


test_curl "1. БЕЗ ИЗМЕНЕНИЙ"

ORIGINAL=$?


echo -e "\n${YELLOW}Добавление hosts записи...${NC}"

git="githubusercontent.com"

if ! grep -q "raw.$git" /etc/hosts; then
printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts
fi

/etc/init.d/dnsmasq restart 2>/dev/null

sleep 2


test_curl "2. С HOSTS"

WITH_HOSTS=$?


echo -e "\n${YELLOW}Возврат оригинального hosts...${NC}"

cp $BACKUP /etc/hosts

/etc/init.d/dnsmasq restart 2>/dev/null

sleep 2


test_curl "3. ПОСЛЕ ВОЗВРАТА"

AFTER=$?


echo -e "\n${CYAN}========== ИТОГ ==========${NC}"


if [ $ORIGINAL -ne 0 ] && [ $WITH_HOSTS -eq 0 ]; then
    echo -e "${YELLOW}hosts помогает. GitHub доступен через фиксированные IP.${NC}"
fi

if [ $ORIGINAL -eq 0 ]; then
    echo -e "${GREEN}Без hosts всё работает.${NC}"
fi

if [ $AFTER -eq $ORIGINAL ]; then
    echo -e "${GREEN}hosts успешно восстановлен.${NC}"
else
    echo -e "${RED}Проверить восстановление hosts!${NC}"
fi

rm -f $BACKUP
