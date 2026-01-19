#!/bin/sh

clear

echo "███████╗██████╗ ██████╗ "
echo "╚══███╔╝╚════██╗██╔══██╗"
echo "  ███╔╝  █████╔╝██████╔╝"
echo " ███╔╝  ██╔═══╝ ██╔══██╗"
echo "███████╗███████╗██║  ██║"
echo "╚══════╝╚══════╝╚═╝  ╚═╝"

BASE_HTML="$(printf '%s' 'aHR0cHM6Ly9naXRodWIuY29tL3JvdXRlcmljaC9wYWNrYWdlcy5yb3V0ZXJpY2gvdHJlZS8yNC4xMC40L3JvdXRlcmljaA==' | openssl base64 -d)"
RAW_BASE="$(printf '%s' 'aHR0cHM6Ly9naXRodWIuY29tL3JvdXRlcmljaC9wYWNrYWdlcy5yb3V0ZXJpY2gvcmF3L3JlZnMvaGVhZHMvMjQuMTAuNC9yb3V0ZXJpY2g=' | openssl base64 -d)"
TMP="/tmp/z2r"; GREEN="\033[1;32m"; RED="\033[1;31m"; NC="\033[0m"

[ "$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)" = "aarch64_cortex-a53" ] || { echo -e "\n${RED}Неподдерживаемая архитектура!${NC}\n${GREEN}Только для ${NC}aarch64_cortex-a53\n"; exit 1; }

if opkg list-installed | grep -q "^zapret2 "; then
    echo -e "${RED}Удаляем Zapret2${NC}"
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2 >/dev/null 2>&1
    rm -f /etc/config/zapret2; rm -rf /opt/zapret2; rm -rf "$TMP"
    echo -e "${GREEN}Удалено!${NC}\n"
    exit 0
fi

find_latest() { wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1; }

install_pkg() {
    PKG="$(find_latest "$1")" || { echo -e "\n${RED}Файл не найден!${NC}\n"; exit 1; }
    echo -e "${GREEN}Скачиваем${NC} ${1%_}"; wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при скачивании!${NC}\n"; exit 1; }
    echo -e "${GREEN}Устанавливаем${NC} ${1%_}"; opkg install "$TMP/$PKG" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при установке!${NC}\n"; exit 1; }
}

echo -e "${GREEN}Обновляем список пакетов${NC}"; opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; exit 1; }

mkdir -p "$TMP"; install_pkg "zapret2_"; install_pkg "luci-app-zapret2_"; rm -rf "$TMP"

echo -e "${GREEN}Настраиваем${NC}"
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
sed -i "/^--lua-desync=hostfakesplit:midhost=host-2:host=rzd\.ru:tcp_seq=0:tcp_ack=-66000:badsum:strategy=14:final'/ s/host=rzd\.ru/host=google.com/" /etc/config/zapret2
sed -i -e "s/rzd\.ru/max.ru/g" -e "s/m\.ok\.ru/max.ru/g" /etc/config/zapret2
/etc/init.d/zapret2 restart >/dev/null 2>&1

echo -e "${GREEN}Готово!${NC}\n"
