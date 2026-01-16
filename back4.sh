#!/bin/sh
clear

BASE_URL="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"
TMP="/tmp"
GREEN="\033[1;32m"
NC="\033[0m"

# Ищем первый доступный пакет по префиксу
fetch_first_valid() {
  PREFIX="$1"
  wget -qO- "$BASE_URL/" \
    | grep -oE "${PREFIX}[^\"']+\.ipk" \
    | while read NAME; do
        # Проверяем, что файл реально существует
        http_code=$(wget -qS --spider "$BASE_URL/$NAME" 2>&1 | grep "HTTP/" | tail -n1 | awk '{print $2}')
        [ "$http_code" = "200" ] && { echo "$NAME"; return 0; }
    done
}

echo -e "${GREEN}! Обновляем списки пакетов...${NC}"
opkg update || exit 1

# Находим реальные пакеты
ZAPRET=$(fetch_first_valid "zapret2_")
[ -z "$ZAPRET" ] && { echo "Не найден реальный zapret2_*.ipk"; exit 1; }

LUCI=$(fetch_first_valid "luci-app-zapret2_")
[ -z "$LUCI" ] && { echo "Не найден реальный luci-app-zapret2_*.ipk"; exit 1; }

# Скачиваем и ставим
echo -e "${GREEN}! Скачиваем $ZAPRET${NC}"
wget "$BASE_URL/$ZAPRET" -O "$TMP/$ZAPRET" || exit 1
echo -e "${GREEN}! Устанавливаем $ZAPRET${NC}"
opkg install "$TMP/$ZAPRET"

echo -e "${GREEN}! Скачиваем $LUCI${NC}"
wget "$BASE_URL/$LUCI" -O "$TMP/$LUCI" || exit 1
echo -e "${GREEN}! Устанавливаем $LUCI${NC}"
opkg install "$TMP/$LUCI"

echo -e "${GREEN}! Готово.${NC}"
