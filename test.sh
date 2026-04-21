#!/bin/sh

clear

echo "███████╗██████╗ ██████╗ "
echo "╚══███╔╝╚════██╗██╔══██╗"
echo "  ███╔╝  █████╔╝██████╔╝"
echo " ███╔╝  ██╔═══╝ ██╔══██╗"
echo "███████╗███████╗██║  ██║"
echo "╚══════╝╚══════╝╚═╝  ╚═╝"

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.6/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.5/routerich"
TMP="/tmp/z2r"

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"

[ "$ARCH" = "aarch64_cortex-a53" ] || {
    echo -e "\n${RED}Неподдерживаемая архитектура!${NC}\n${GREEN}Только для ${NC}aarch64_cortex-a53\n"
    exit 1
}

find_latest() { wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1; }

install_pkg() {
    PKG="$(find_latest "$1")" || { echo -e "\n${RED}Файл не найден!${NC}\n"; exit 1; }
    wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" || { echo -e "\n${RED}Ошибка скачивания!${NC}\n"; exit 1; }
    opkg install "$TMP/$PKG" || { echo -e "\n${RED}Ошибка установки!${NC}\n"; exit 1; }
}

is_zapret_installed() {
    opkg list-installed | grep -q "^zapret2 "
}

is_zeroblock_installed() {
    opkg list-installed | grep -q "^zeroblock "
}

is_routerich_added() {
    grep -q "routerich" /etc/opkg/customfeeds.conf
}

install_zapret() {
    mkdir -p "$TMP"
    opkg update
    install_pkg "zapret2_"
    install_pkg "luci-app-zapret2_"

    wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt

    sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
    /etc/init.d/zapret2 restart

    rm -rf "$TMP"
    echo -e "\n${GREEN}Zapret установлен${NC}\n"
}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    echo -e "\n${GREEN}Zapret удалён${NC}\n"
}

install_zeroblock() {
    mkdir -p "$TMP"
    opkg update
    install_pkg "zeroblock"
    install_pkg "luci-app-zeroblock"
    rm -rf "$TMP"
    echo -e "\n${GREEN}Zeroblock установлен${NC}\n"
}

remove_zeroblock() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zeroblock zeroblock
    echo -e "\n${GREEN}Zeroblock удалён${NC}\n"
}

add_routerich() {
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.5/routerich' > /etc/opkg/customfeeds.conf
    opkg update
    echo -e "\n${GREEN}Routerich добавлен${NC}\n"
}

remove_routerich() {
    rm -f /etc/opkg/customfeeds.conf
    sed -i 's/# option check_signature/option check_signature/' /etc/opkg.conf
    opkg update
    echo -e "\n${GREEN}Routerich удалён${NC}\n"
}

menu() {
    clear

    if is_zapret_installed; then
        ZAPRET_TEXT="${YELLOW}Удалить Zapret${NC}"
    else
        ZAPRET_TEXT="${GREEN}Установить Zapret${NC}"
    fi

    if is_zeroblock_installed; then
        ZERO_TEXT="${YELLOW}Удалить Zeroblock${NC}"
    else
        ZERO_TEXT="${GREEN}Установить Zeroblock${NC}"
    fi

    if is_routerich_added; then
        ROUTE_TEXT="${YELLOW}Удалить Routerich feed${NC}"
    else
        ROUTE_TEXT="${GREEN}Добавить Routerich feed${NC}"
    fi

    echo -e "${CYAN}1) $ZAPRET_TEXT${NC}"
    echo -e "${CYAN}2) $ZERO_TEXT${NC}"
    echo -e "${CYAN}3) $ROUTE_TEXT${NC}"
    echo -e "${CYAN}0) Выход${NC}"
    echo
    printf "Выбор: "
    read choice

    case "$choice" in
        1)
            if is_zapret_installed; then remove_zapret; else install_zapret; fi
        ;;
        2)
            if is_zeroblock_installed; then remove_zeroblock; else install_zeroblock; fi
        ;;
        3)
            if is_routerich_added; then remove_routerich; else add_routerich; fi
        ;;
        0) exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}" ;;
    esac

    echo -ne "\nНажмите Enter..."
    read dummy
}

while true; do
    menu
done
