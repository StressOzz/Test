#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"

BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"

PKG_IS_APK=0
PKG_MANAGER="opkg list-installed 2>/dev/null"

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"
VER="$(awk -F\' '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release)"

[ "$VER" = "24.10.6" ] || { echo -e "\n${RED}Неподдерживаемая версия OpenWrt: $VER${NC}\n"; exit 1; }
[ "$ARCH" = "aarch64_cortex-a53" ] || { echo -e "\n${RED}Неподдерживаемая архитектура: $ARCH${NC}\n"; exit 1; }

if ! grep -q "routerich/packages.routerich" /etc/opkg/customfeeds.conf 2>/dev/null; then
    echo -e "\n${CYAN}Добавляем пакеты Routerich${NC}"
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.5/routerich' > /etc/opkg/customfeeds.conf
    opkg update
fi

is_routerich() {
    grep -q "routerich/packages.routerich" /etc/opkg/customfeeds.conf 2>/dev/null
}

routerich_add() {
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.5/routerich' > /etc/opkg/customfeeds.conf
    opkg update
    echo "Routerich добавлен"
}

routerich_remove() {
    rm -f /etc/opkg/customfeeds.conf
    sed -i 's/# option check_signature/option check_signature/' /etc/opkg.conf
    opkg update
    echo "Routerich удалён"
}


is_installed() {
    opkg list-installed | grep -q "$1"
}

install_zapret() {
    opkg update
    opkg install zapret2 luci-app-zapret2
    echo -e "${GREEN}Настраиваем...${NC}"
wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
/etc/init.d/zapret2 restart >/dev/null 2>&1

}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    echo -e "\n${GREEN}Zapret удалён${NC}\n"
}

install_zero() {
    opkg update
    opkg install zeroblock luci-app-zeroblock
}

remove_zero() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zeroblock zeroblock
    rm -rf /etc/config/zeroblock*
    rm -rf /etc/zeroblock*
    rm -rf /opt/zeroblock*
    rm -rf /usr/bin/zeroblock*
    echo -e "\n${GREEN}Zeroblock удалён${NC}\n"
}


###################################################################################################################################################
install_AWG() {

echo -e "\n${MAGENTA}Устанавливаем AWG и интерфейс AWG${NC}"

VERSION=$(ubus call system board | jsonfilter -e '@.release.version' | tr -d '\n')
MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f1)

if [ -z "$VERSION" ]; then
echo -e "\n${RED}Не удалось определить версию OpenWrt!${NC}"
PAUSE
return
fi

TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)

install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"

echo -e "${CYAN}Скачиваем:${NC} $filename"

if wget -O "$tmpDIR/$filename" "$url" >/dev/null 2>&1; then
echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
if ! $INSTALL_CMD "$tmpDIR/$filename" >/dev/null 2>&1; then
echo -e "\n${RED}Ошибка установки $pkgname!${NC}"
PAUSE
return 1
fi
else
echo -e "\n${RED}Ошибка! Не удалось скачать $filename${NC}"
PAUSE
return 1
fi
}

if [ "$MAJOR_VERSION" -ge 25 ] 2>/dev/null; then
PKGARCH=$(cat /etc/apk/arch)
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.apk"
INSTALL_CMD="apk add --allow-untrusted"
else
echo -e "${CYAN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}"
PAUSE
return
}
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
INSTALL_CMD="opkg install"
fi

install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
install_pkg "luci-i18n-amneziawg-ru"

echo -e "${CYAN}Создаем интерфейс AWG${NC}"

if uci show network.$IF_NAME >/dev/null 2>&1; then
echo -e "${RED}Интерфейс уже существует!${NC}"
else
uci set network.$IF_NAME=interface
uci set network.$IF_NAME.proto=$PROTO
uci set network.$IF_NAME.device=$DEV_NAME
uci commit network
fi

echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart >/dev/null 2>&1

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}установлены!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE
}

uninstall_AWG() {
echo -e "\n${MAGENTA}Удаление AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Удаляем ${NC}AWG"
pkg_remove luci-i18n-amneziawg-ru
pkg_remove luci-proto-amneziawg
pkg_remove amneziawg-tools
pkg_remove kmod-amneziawg

uci delete network.AWG >/dev/null 2>&1
uci commit network >/dev/null 2>&1

for peer in $(uci show network | grep "interface='AWG'" | cut -d. -f2); do
    uci delete network.$peer
done
uci commit network >/dev/null 2>&1
echo -e "${CYAN}Удаляем ${NC}интерфейс AWG"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}удалены!${NC}"
PAUSE
}

###################################################################################################################################################

menu() {
    clear

    echo -e "${CYAN}===== Router Manager =====${NC}"
    echo
    
echo -e "${MAGENTA}--- AWG ---${NC}"

if command -v amneziawg >/dev/null 2>&1 || eval "$PKG_MANAGER" | grep -q "amneziawg-tools"; then
echo -e "${YELLOW}AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}AWG: ${RED}не установлен${NC}"
fi
if uci -q get network.AWG >/dev/null; then
    echo -e "${YELLOW}Интерфейс AWG: ${GREEN}установлен${NC}"
else
    echo -e "${YELLOW}Интерфейс AWG: ${RED}не установлен${NC}"
fi





    if is_installed zapret2; then
        Z="Удалить"
    else
        Z="Установить"
    fi

    if is_installed zeroblock; then
        ZB="Удалить"
    else
        ZB="Установить"
    fi

    if is_routerich; then
        R_TEXT="Удалить"
    else
        R_TEXT="Добавить"
    fi

    echo -e "${CYAN}1) ${GREEN}${Z}${NC} Zapret 2"
    echo -e "${CYAN}2) ${GREEN}${ZB}${NC} Zeroblock"
    echo -e "${CYAN}3) ${GREEN}Установить ${NC}AWG ${GREEN}и${NC} интерфейс AWG"
    echo -e "${CYAN}4) ${GREEN}Удалить ${NC}AWG ${GREEN}и${NC} интерфейс AWG" 
    echo -e "${CYAN}5) ${GREEN}$R_TEXT пакеты${NC} Routerich"
    
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
    read c

    case "$c" in
        1)
            if is_installed zapret2; then remove_zapret; else install_zapret; fi
        ;;
        2)
            if is_installed zeroblock; then remove_zero; else install_zero; fi
        ;;

        3) 
            install_AWG
        ;;
        
        4) 
            uninstall_AWG
        ;;

        5)
            if is_routerich; then routerich_remove; else routerich_add; fi
        ;;      
        *)
            exit 0
        ;;
    esac

    PAUSE
    
    read
}

while true; do
    menu
done
