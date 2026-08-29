#!/bin/sh

# =========================================
# GitHub Hosts Fix for OpenWrt
# =========================================

if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    NC=''
fi

GITHUB_DOMAINS="
raw.githubusercontent.com
objects.githubusercontent.com
media.githubusercontent.com
avatars.githubusercontent.com
avatars0.githubusercontent.com
avatars1.githubusercontent.com
avatars2.githubusercontent.com
avatars3.githubusercontent.com
avatars4.githubusercontent.com
avatars5.githubusercontent.com
avatars6.githubusercontent.com
avatars7.githubusercontent.com
avatars8.githubusercontent.com
camo.githubusercontent.com
gist.githubusercontent.com
cloud.githubusercontent.com
user-images.githubusercontent.com
release-assets.githubusercontent.com
github.io
"

HOSTS_FILE="/etc/hosts"
TMP_FILE="/tmp/gh_hosts_$$"

# =========================================
# Проверка root
# =========================================

if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Ошибка: скрипт должен запускаться от root.${NC}"
    exit 1
fi

# =========================================
# Проверка curl
# =========================================

if ! command -v curl >/dev/null 2>&1; then
    echo -e "${RED}Ошибка: curl не установлен.${NC}"
    echo "Установите его командой: opkg update && opkg install curl"
    exit 1
fi

echo -e "${GREEN}Проверяю доступность raw.githubusercontent.com...${NC}"

# =========================================
# Получение IPv4 через Google DoH
# =========================================

DOH_V4=$(curl -fsSL --max-time 10 \
    "https://dns.google/resolve?name=raw.githubusercontent.com&type=A" \
    2>/dev/null)

IPS_V4=$(echo "$DOH_V4" |
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' |
    sort -u)

# =========================================
# Получение IPv6 через Google DoH
# =========================================

DOH_V6=$(curl -fsSL --max-time 10 \
    "https://dns.google/resolve?name=raw.githubusercontent.com&type=AAAA" \
    2>/dev/null)

IPS_V6=$(echo "$DOH_V6" |
    grep -oE '"data":"[0-9a-fA-F:.]+"' |
    cut -d'"' -f4 |
    grep ':' |
    sort -u)

# =========================================
# Резервные адреса GitHub
# =========================================

if [ -z "$IPS_V4" ]; then
    echo -e "${YELLOW}Google DoH не вернул IPv4. Использую резервные адреса.${NC}"

    IPS_V4="
185.199.108.133
185.199.109.133
185.199.110.133
185.199.111.133
"
fi

if [ -z "$IPS_V6" ]; then
    echo -e "${YELLOW}Google DoH не вернул IPv6. Использую резервные адреса.${NC}"

    IPS_V6="
2606:50c0:8000::154
2606:50c0:8001::154
2606:50c0:8002::154
2606:50c0:8003::154
"
fi

echo
echo "IPv4:"
echo "$IPS_V4"

echo
echo "IPv6:"
echo "$IPS_V6"

# =========================================
# Проверка рабочих IPv4
# =========================================

GOOD_V4=""

echo
echo -e "${YELLOW}Проверяю IPv4...${NC}"

for IP in $IPS_V4; do

    if curl -sS \
        --connect-timeout 3 \
        --max-time 6 \
        -o /dev/null \
        --resolve "raw.githubusercontent.com:443:$IP" \
        "https://raw.githubusercontent.com/" \
        >/dev/null 2>&1
    then
        GOOD_V4="$GOOD_V4 $IP"
        echo -e "${GREEN}OK${NC}  $IP"
    else
        echo -e "${RED}FAIL${NC} $IP"
    fi

done

# =========================================
# Проверка рабочих IPv6
# =========================================

GOOD_V6=""

if [ -n "$IPS_V6" ] && [ -n "$(ip -6 route 2>/dev/null)" ]; then

    echo
    echo -e "${YELLOW}Проверяю IPv6...${NC}"

    for IP in $IPS_V6; do

        if curl -6 -sS \
            --connect-timeout 3 \
            --max-time 6 \
            -o /dev/null \
            --resolve "raw.githubusercontent.com:443:[$IP]" \
            "https://raw.githubusercontent.com/" \
            >/dev/null 2>&1
        then
            GOOD_V6="$GOOD_V6 $IP"
            echo -e "${GREEN}OK${NC}  $IP"
        else
            echo -e "${RED}FAIL${NC} $IP"
        fi

    done

fi

# =========================================
# Выбор рабочего IP
# =========================================

if [ -n "$GOOD_V4" ]; then

    # Первый рабочий IPv4
    SELECTED_IP=$(echo "$GOOD_V4" | awk '{print $1}')
    FAMILY="IPv4"

elif [ -n "$GOOD_V6" ]; then

    # Первый рабочий IPv6
    SELECTED_IP=$(echo "$GOOD_V6" | awk '{print $1}')
    FAMILY="IPv6"

else

    echo
    echo -e "${RED}Ошибка: рабочие IP GitHub не найдены.${NC}"
    exit 1

fi

echo
echo -e "${GREEN}Выбран IP: $SELECTED_IP ($FAMILY)${NC}"

# =========================================
# Подготовка /etc/hosts
# =========================================

if [ ! -f "$HOSTS_FILE" ]; then
    touch "$HOSTS_FILE"
fi

# =========================================
# Удаление старых GitHub-записей
# =========================================

PATTERN=''

for DOMAIN in $GITHUB_DOMAINS; do

    ESCAPED_DOMAIN=$(echo "$DOMAIN" | sed 's/\./\\./g')

    if [ -n "$PATTERN" ]; then
        PATTERN="$PATTERN|"
    fi

    PATTERN="${PATTERN}${ESCAPED_DOMAIN}"

done

grep -vE \
    "^[[:space:]]*(([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F:]+)[[:space:]]+(${PATTERN})([[:space:]]|\$)" \
    "$HOSTS_FILE" \
    > "$TMP_FILE" 2>/dev/null || true

# =========================================
# Добавление новых записей
# =========================================

for DOMAIN in $GITHUB_DOMAINS; do
    echo "$SELECTED_IP $DOMAIN" >> "$TMP_FILE"
done

# =========================================
# Замена /etc/hosts
# =========================================

cat "$TMP_FILE" > "$HOSTS_FILE"

rm -f "$TMP_FILE"

# =========================================
# Перезапуск dnsmasq
# =========================================

if [ -x /etc/init.d/dnsmasq ]; then
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
fi

echo
echo -e "${GREEN}Готово!${NC}"
echo -e "${GREEN}GitHub-домены добавлены в /etc/hosts.${NC}"
echo -e "${GREEN}Используется: $SELECTED_IP ($FAMILY)${NC}"

exit 0
