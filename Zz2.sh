#!/bin/sh
clear

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.4/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"
TMP="/tmp"
GREEN="\033[1;32m"
NC="\033[0m"

find_latest() {
  wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1
}

install_pkg() {
  PKG=$(find_latest "$1")
  [ -z "$PKG" ] && { echo "$1 не найден"; exit 1; }

  echo -e "${GREEN}Скачиваем $PKG${NC}"
  wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" >/dev/null 2>&1 || exit 1

  echo -e "${GREEN}Устанавливаем $PKG${NC}"
  opkg install "$TMP/$PKG" >/dev/null 2>&1
}

echo -e "${GREEN}Обновляем списки пакетов...${NC}"
opkg update >/dev/null 2>&1 || exit 1

install_pkg "zapret2_"
install_pkg "luci-app-zapret2_"

echo -e "${GREEN}Готово!${NC}"
