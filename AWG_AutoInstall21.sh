#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
WHITE="\033[1;37m"
BLUE="\033[0;34m"
GRAY='\033[38;5;239m'
DGRAY='\033[38;5;236m'

clear

echo -e "${MAGENTA}Устанавливаем AWG + интерфейс${NC}"
echo -e "${GREEN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1
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

    if opkg list-installed >/dev/null 2>&1 | grep -q "$pkgname"; then
        echo -e "${GREEN}$pkgname уже установлен${NC}"
        return
    fi

    echo -e "${GREEN}Скачиваем ${NC}$pkgname"
    if wget -O "$AWG_DIR/$filename" "$url" >/dev/null 2>&1 ; then
        echo -e "${GREEN}Устанавливаем ${NC}$pkgname"
        if opkg install "$AWG_DIR/$filename" >/dev/null 2>&1 ; then
            echo -e "$pkgname ${GREEN}установлен успешно${NC}"
        else
            echo -e "\n${RED}Ошибка установки $pkgname!${NC}"
            exit 1
        fi
    else
        echo -e "\n${RED}Ошибка установки $pkgname!${NC}"
        exit 1
    fi
}
install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"

    echo -e "${GREEN}Устанавливаем русскую локализацию${NC}"
	install_pkg "luci-i18n-amneziawg-ru" >/dev/null 2>&1 || echo -e "${RED}Внимание: русская локализация не установлена (не критично)${NC}"

echo -e "${GREEN}Очистка временных файлов${NC}"
rm -rf "$AWG_DIR"
echo -e "${GREEN}Перезапускаем сеть${NC}"
/etc/init.d/network restart >/dev/null 2>&1
echo -e "AmneziaWG ${GREEN}установлен!${NC}"

##################################################################################################################

# Имя интерфейса и протокол

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
echo -e "${MAGENTA}Устанавливаем новый интерфейс AWG${NC}"
if grep -q "config interface '$IF_NAME'" /etc/config/network; then
echo -e "${RED}Интерфейс $IF_NAME уже существует${NC}"
else
echo -e "${GREEN}Добавляем интерфейс ${NC}$IF_NAME"
uci batch <<EOF
set network.$IF_NAME=interface
set network.$IF_NAME.proto=$PROTO
set network.$IF_NAME.device=$DEV_NAME
commit network
EOF
fi
echo -e "${GREEN}Перезапускаем сеть${NC}"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
echo -e "${GREEN}Интерфейс ${NC}$IF_NAME${GREEN} создан и активирован!${NC}"


		echo -e "\n${BLUE}Вставьте рабочий конфиг в Interfaces (Интерфейс) и нажмите Enter ${NC}\n"
		read -p "Нажмите Enter..." dummy
		


echo -e "${MAGENTA}Устанавливаем Podkop${NC}"
    TMP="/tmp/podkop"
    rm -rf "$TMP"
    mkdir -p "$TMP"
    cd "$TMP"
	
echo -e "${GREEN}Скачиваем пакеты${NC}"
wget -q -O podkop.ipk https://github.com/itdoginfo/podkop/releases/download/0.7.10/podkop-v0.7.10-r1-all.ipk
wget -q -O luci-app-podkop.ipk https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-app-podkop-v0.7.10-r1-all.ipk
wget -q -O luci-i18n-podkop-ru.ipk https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-i18n-podkop-ru-0.7.10.ipk


echo -e "${GREEN}Устанавливаем ${NC}podkop-v0.7.10-r1-all.ipk"
opkg install podkop.ipk >/dev/null 2>&1

echo -e "${GREEN}Устанавливаем ${NC}luci-app-podkop-v0.7.10-r1-all.ipk"
opkg install luci-app-podkop.ipk >/dev/null 2>&1

echo -e "${GREEN}Устанавливаем ${NC}luci-i18n-podkop-ru-0.7.10.ipk"
opkg install luci-i18n-podkop-ru.ipk >/dev/null 2>&1

    cd /
    rm -rf "$TMP"


wget -qO /etc/config/podkop https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/podkop
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}.${NC}"
	echo -e "${GREEN}Запускаем ${NC}Podkop${NC}"
    podkop enable >/dev/null 2>&1
    echo -e "${GREEN}Применяем конфигурацию${NC}"
    podkop reload >/dev/null 2>&1
    podkop restart >/dev/null 2>&1
    echo -e "${GREEN}Обновляем списки${NC}"
    podkop list_update >/dev/null 2>&1
    echo -e "${GREEN}Перезапускаем сервис${NC}"
    podkop restart >/dev/null 2>&1
    echo -e "\nPodkop ${GREEN}готов к работе!${NC}"
    read -p "Нажмите Enter..." dummy
