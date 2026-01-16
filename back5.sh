#!/bin/sh
clear
BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.4/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"
TMP="/tmp"
GREEN="\033[1;32m"
NC="\033[0m"

# ищем файл по HTML GitHub страницы
find_latest() {
  wget -qO- "$BASE_HTML" \
    | grep -oE "$1[^\"']+\.ipk" \
    | sort -u \
    | head -n1
}

echo -e "${GREEN}! Обновляем списки пакетов...${NC}"
opkg update || exit 1

ZAPRET=$(find_latest "zapret2_")
[ -z "$ZAPRET" ] && { echo "zapret2 не найден"; exit 1; }

LUCI=$(find_latest "luci-app-zapret2_")
[ -z "$LUCI" ] && { echo "luci-app-zapret2 не найден"; exit 1; }

echo -e "${GREEN}! Скачиваем $ZAPRET${NC}"
wget "$RAW_BASE/$ZAPRET" -O "$TMP/$ZAPRET" || exit 1
echo -e "${GREEN}! Устанавливаем $ZAPRET${NC}"
opkg install "$TMP/$ZAPRET"

echo -e "${GREEN}! Скачиваем $LUCI${NC}"
wget "$RAW_BASE/$LUCI" -O "$TMP/$LUCI" || exit 1
echo -e "${GREEN}! Устанавливаем $LUCI${NC}"
opkg install "$TMP/$LUCI"

echo -e "${GREEN}! Готово.${NC}"
