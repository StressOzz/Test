#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"
VER="$(awk -F\' '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release)"

# проверка системы
[ "$VER" = "24.10.6" ] || { echo -e "\n${RED}Неподдерживаемая версия OpenWrt: $VER${NC}\n"; exit 1; }
[ "$ARCH" = "aarch64_cortex-a5" ] || { echo -e "\n${RED}Неподдерживаемая архитектура: $ARCH${NC}\n"; exit 1; }

# добавляем Routerich
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
}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove zapret2 luci-app-zapret2
}

install_zero() {
    opkg update
    opkg install zeroblock luci-app-zeroblock
}

remove_zero() {
    opkg --force-removal-of-dependent-packages --autoremove remove zeroblock luci-app-zeroblock
}

menu() {
    clear

    echo -e "${CYAN}===== Router Manager =====${NC}"
    echo

    if is_installed zapret2; then
        Z="Удалить Zapret"
    else
        Z="Установить Zapret"
    fi

    if is_installed zeroblock; then
        ZB="Удалить Zeroblock"
    else
        ZB="Установить Zeroblock"
    fi

    if is_routerich; then
        R_TEXT="Удалить Routerich"
    else
        R_TEXT="Добавить Routerich"
    fi


    echo -e "${CYAN}1) ${Z}${NC}"
    echo -e "${CYAN}2) ${ZB}${NC}"
    echo -e "${CYAN}3) $R_TEXT${NC}"
    echo -e "${CYAN}Enter) Выход${NC}"
    echo -en "Выбор: "
    read c

    case "$c" in
        1)
            if is_installed zapret2; then remove_zapret; else install_zapret; fi
        ;;
        2)
            if is_installed zeroblock; then remove_zero; else install_zero; fi
        ;;

        1)
            if is_routerich; then routerich_remove; else routerich_add; fi
        ;;      
        *)
            exit 0
        ;;
    esac

    echo -en "\nEnter..."
    read
}

while true; do
    menu
done
