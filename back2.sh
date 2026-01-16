#!/bin/sh
clear
BASE_URL="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"
TMP="/tmp"

GREEN="\033[1;32m"
NC="\033[0m"

get_ipk() {
    wget -qO- "$BASE_URL/" | grep -o "$1[^\"']*\.ipk" | head -n1
}

echo -e "${GREEN}Обновляем списки пакетов...${NC}"
opkg update || exit 1

echo -e "${GREEN}Ищем zapret2...${NC}"
ZAPRET=$(get_ipk "zapret2_")
[ -z "$ZAPRET" ] && { echo "zapret2 не найден"; exit 1; }

echo -e "${GREEN}Ищем luci-app-zapret2...${NC}"
LUCI=$(get_ipk "luci-app-zapret2_")
[ -z "$LUCI" ] && { echo "luci-app-zapret2 не найден"; exit 1; }

echo -e "${GREEN}Скачиваем $ZAPRET${NC}"
wget -q "$BASE_URL/$ZAPRET" -O "$TMP/$ZAPRET" || exit 1

echo -e "${GREEN}Скачиваем $LUCI${NC}"
wget -q "$BASE_URL/$LUCI" -O "$TMP/$LUCI" || exit 1

echo -e "${GREEN}Устанавливаем zapret2${NC}"
opkg install "$TMP/$ZAPRET"

echo -e "${GREEN}Устанавливаем luci-app-zapret2${NC}"
opkg install "$TMP/$LUCI"

echo -e "${GREEN}Готово.${NC}"
