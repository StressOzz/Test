#!/bin/sh
clear

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.4/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"
TMP="/tmp"
GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

[ "$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)" = "aarch64_cortex-a53" ] || { echo -e "${RED}Неподдерживаемая архитектура!${NC}"; exit 1; }

find_latest() {
  wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1
}

install_pkg() {
	PKG="$(find_latest "$1")"

	echo -e "${GREEN}Скачиваем${NC} ${1%_}"
	wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" >/dev/null 2>&1 || {
		echo -e "\n${RED}ОШИБКА!${NC}\n"
		exit 1
	}

	echo -e "${GREEN}Устанавливаем${NC} ${1%_}"
	opkg install "$TMP/$PKG" >/dev/null 2>&1 || exit 1
}


if opkg list-installed | grep -q "^zapret2 "; then
	echo -e "${RED}Удаляем Zapret2${NC}"

	opkg remove luci-app-zapret2 zapret2 >/dev/null 2>&1
  rm -f /etc/config/zapret2
  rm -rf /opt/zapret2

	echo -e "${GREEN}Удалено!${NC}"
	exit 0
fi


echo -e "${GREEN}Обновляем списки пакетов${NC}"
opkg update >/dev/null 2>&1 || exit 1

  install_pkg "zapret2_"
  install_pkg "luci-app-zapret2_"
echo -e "${GREEN}Настраиваем${NC}"
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
sed -i "/^--lua-desync=hostfakesplit:midhost=host-2:host=rzd\.ru:tcp_seq=0:tcp_ack=-66000:badsum:strategy=14:final'/ s/host=rzd\.ru/host=google.com/" /etc/config/zapret2
sed -i -e "s/rzd\.ru/max.ru/g" -e "s/m\.ok\.ru/max.ru/g" /etc/config/zapret2
/etc/init.d/zapret2 restart >/dev/null 2>&1
  
echo -e "${GREEN}Готово!${NC}"
