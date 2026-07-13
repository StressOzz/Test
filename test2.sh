#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

HOST="raw.githubusercontent.com"
URL="https://raw.githubusercontent.com/StressOzz/Test/main/test1.sh"

IPS="
185.199.108.133
185.199.109.133
185.199.110.133
185.199.111.133
"

echo -e "${CYAN}"
echo "╔══════════════════════════════╗"
echo "║ GitHub IP Connection Test    ║"
echo "╚══════════════════════════════╝"
echo -e "${NC}"


echo -e "${YELLOW}[ DNS ]${NC}"
nslookup $HOST 2>/dev/null | grep Address

echo


GOOD=0
BAD=0

for IP in $IPS
do
    echo -n "IP $IP : "

    RESULT=$(curl -4 -k -sS \
    --resolve $HOST:443:$IP \
    -o /dev/null \
    -w "%{http_code} %{time_connect}" \
    --connect-timeout 5 \
    "$URL" 2>&1)

    CODE=$(echo "$RESULT" | awk '{print $1}')

    if [ "$CODE" = "200" ]; then
        echo -e "${GREEN}OK${NC} HTTP:$CODE TIME:$(echo "$RESULT" | awk '{print $2}')s"
        GOOD=$((GOOD+1))
    else
        echo -e "${RED}FAIL${NC} $RESULT"
        BAD=$((BAD+1))
    fi
done


echo
echo -e "${CYAN}========== RESULT ==========${NC}"

echo "Рабочих IP: $GOOD"
echo "Недоступных IP: $BAD"

if [ "$GOOD" -gt 0 ] && [ "$BAD" -gt 0 ]; then
    echo -e "${YELLOW}Вывод: GitHub доступен частично. DNS балансировка мешает.${NC}"
    echo "Решение: закрепить рабочий IP через /etc/hosts или использовать обход."
elif [ "$GOOD" -eq 4 ]; then
    echo -e "${GREEN}Вывод: все IP GitHub работают.${NC}"
else
    echo -e "${RED}Вывод: GitHub недоступен.${NC}"
fi
