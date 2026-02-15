#!/bin/sh


CONF="/etc/opkg/distfeeds.conf"

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"

update_packages() {
    echo -e "${CYAN}\nПроверяем зеркало. Обновляем список пакетов...${NC}"

    PKG="$(command -v apk >/dev/null 2>&1 && echo apk || echo opkg)"

    $PKG update >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка! Зеркало не работат!${NC}\n"
        return 1
    }

    echo -e "${GREEN}\nЗеркало работает! Обновление выполнено!${NC}\n"
    
    echo "Нажмите Enter..."; read dummy
}

replace_server() {
    NEW_BASE="$1"

    sed -i "s|https://[^/]*/releases|https://$NEW_BASE/releases|g" "$CONF"

    echo -e "${GREEN}\nЗеркало обновлено!${NC}"

    update_packages
}

show_menu() {
    clear
    
    echo -e "${BLUE}Выберите зеркало:${NC}"
    echo -e "${CYAN}1)${NC} Belgium"
    echo -e "${CYAN}2)${NC} Netherlands"
    echo -e "${CYAN}3)${NC} Germany"
    echo -e "${CYAN}4)${NC} China"
    echo -e "${CYAN}5)${NC} Вернуть downloads.openwrt.org"
    echo -e "${CYAN}Enter) Выход"
    echo -en "\n${YELLOW}Введите номер: "
}

while true; do
    show_menu
    read choice

    case "$choice" in
        1) replace_server "mirror.tiguinet.net/openwrt" ;;
        2) replace_server "ftp.snt.utwente.nl/pub/software/openwrt" ;;
        3) replace_server "mirror.berlin.freifunk.net/downloads.openwrt.org" ;;
        4) replace_server "mirrors.cernet.edu.cn/openwrt" ;;
        5) replace_server "downloads.openwrt.org" ;;
        *) exit 0 ;;
    esac
done
