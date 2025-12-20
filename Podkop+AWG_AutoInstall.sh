#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
NC="\033[0m"
clear

##################################################################################################################

echo -e "${MAGENTA}Устанавливаем AWG + интерфейс${NC}"
echo -e "${GREEN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; exit 1; }
echo -e "${GREEN}Определяем архитектуру и версию OpenWrt${NC}"
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
AWG_DIR="/tmp/amneziawg"
mkdir -p "$AWG_DIR"
install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"
echo -e "${CYAN}Скачиваем ${NC}$pkgname"
if wget -O "$AWG_DIR/$filename" "$url" >/dev/null 2>&1 ; then
echo -e "${CYAN}Устанавливаем ${NC}$pkgname"
if opkg install "$AWG_DIR/$filename" >/dev/null 2>&1 ; then
echo -e "$pkgname ${GREEN}установлен успешно${NC}"
else
echo -e "\n${RED}Ошибка установки $pkgname!${NC}\n"
exit 1
fi
else
echo -e "\n${RED}Ошибка! Не удалось скачать $file${NC}\n"
exit 1
fi
}
install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
echo -e "${CYAN}Устанавливаем русскую локализацию${NC}"
install_pkg "luci-i18n-amneziawg-ru" >/dev/null 2>&1 || echo -e "${RED}Внимание: русская локализация не установлена (не критично)${NC}"
echo -e "${CYAN}Очистка временных файлов${NC}"
rm -rf "$AWG_DIR"
echo -e "${CYAN}Перезапускаем сеть${NC}"
/etc/init.d/network restart >/dev/null 2>&1
echo -e "AmneziaWG ${GREEN}установлен!${NC}"

##################################################################################################################

echo -e "${MAGENTA}Устанавливаем интерфейс AWG${NC}"
IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
if grep -q "config interface '$IF_NAME'" /etc/config/network; then
echo -e "${RED}Интерфейс ${NC}$IF_NAME${RED} уже существует${NC}"
else
echo -e "${CYAN}Добавляем интерфейс ${NC}$IF_NAME"
uci batch <<EOF
set network.$IF_NAME=interface
set network.$IF_NAME.proto=$PROTO
set network.$IF_NAME.device=$DEV_NAME
commit network
EOF
fi
echo -e "${CYAN}Перезапускаем сеть${NC}"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
echo -e "${GREEN}Интерфейс ${NC}$IF_NAME${GREEN} создан и активирован!${NC}"

##################################################################################################################

echo -e "\n${YELLOW}Вставьте рабочий конфиг в Interfaces (Интерфейс) AWG!\nНажмите Ctrl+C для остановки или Enter для установки Podkop!${NC}"
read -p "" dummy
echo -e "${YELLOW}Podkop будет установлен / обновлён!\nВсе настройки Podkop будут сброшены!\nPodkop будет настроен для работы с AWG!${NC}"
read -p "Нажмите Enter..." dummy
##################################################################################################################

echo -e "${MAGENTA}Устанавливаем Podkop${NC}"
TMP="/tmp/podkop"
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"
download() {
local url="$1"
local file="$2"
echo -e "${CYAN}Скачиваем ${NC}$file"
if ! wget -q -O "$file" "$url"; then
echo -e "\n${RED}Ошибка! Не удалось скачать $file${NC}\n"
exit 1
fi
}
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/podkop-v0.7.10-r1-all.ipk podkop.ipk
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-app-podkop-v0.7.10-r1-all.ipk luci-app-podkop.ipk
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-i18n-podkop-ru-0.7.10.ipk luci-i18n-podkop-ru.ipk
install_pkg() {
local file="$1"
local name="$2"
echo -e "${CYAN}Устанавливаем ${NC}${name}"
if ! opkg install "$file" >/dev/null 2>&1; then
echo -e "\n${RED}Ошибка! Не удалось установить ${name}${NC}\n"
exit 1
fi
}
install_pkg podkop.ipk podkop-v0.7.10-r1-all.ipk
install_pkg luci-app-podkop.ipk luci-app-podkop-v0.7.10-r1-all.ipk
install_pkg luci-i18n-podkop-ru.ipk luci-i18n-podkop-ru-0.7.10.ipk
cd /
rm -rf "$TMP"
wget -qO /etc/config/podkop https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/podkop
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}.${NC}"
echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
podkop enable >/dev/null 2>&1
echo -e "${CYAN}Применяем конфигурацию${NC}"
podkop reload >/dev/null 2>&1
podkop restart >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}"
podkop restart >/dev/null 2>&1
echo -e "Podkop ${GREEN}готов к работе!${NC}\n"
