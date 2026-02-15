#!/bin/sh

# --- конфиг ---
if command -v apk >/dev/null 2>&1; then
    CONF="/etc/apk/repositories.d/distfeeds.list"
else
    CONF="/etc/opkg/distfeeds.conf"
fi

# --- цвета ---
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"

# --- проверка зеркала ---
update_packages() {
    echo -e "${CYAN}\nПроверяем зеркало. Обновляем список пакетов...${NC}"

    PKG="$(command -v apk >/dev/null 2>&1 && echo apk || echo opkg)"

    $PKG update >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка! Зеркало не работает!${NC}\n"
        return 1
    }

    echo -e "${GREEN}\nЗеркало работает! Обновление выполнено!${NC}\n"
    
    echo "Нажмите Enter..."; read dummy
}

# --- замена зеркала ---
replace_server() {
    NEW_BASE="$1"

    # заменяем только часть между https:// и /releases/
    sed -i "s|https://.*/releases/|https://$NEW_BASE/releases/|g" "$CONF"

    echo -e "${GREEN}\nЗеркало обновлено!${NC}"

    update_packages
}

# --- определяем текущее зеркало по стране ---
current_country() {
    if [ -f "$CONF" ]; then
        URL=$(head -n1 "$CONF")
        case "$URL" in
            *tiguinet.net*) echo "Belgium" ;;
            *utwente.nl*) echo "Netherlands" ;;
            *freifunk.net*) echo "Germany" ;;
            *cernet.edu.cn*) echo "China" ;;
            *downloads.openwrt.org*) echo "OpenWrt" ;;
            *) echo "Неизвестно" ;;
        esac
    else
        echo "Файл не найден"
    fi
}

# --- меню ---
show_menu() {
    clear

    CURRENT=$(current_country)
    echo -e "${BLUE}Используется зеркало: ${GREEN}$CURRENT${NC}\n"
    
    echo -e "${BLUE}Выберите зеркало:${NC}"
    echo -e "${CYAN}1)${NC} Belgium"
    echo -e "${CYAN}2)${NC} Netherlands"
    echo -e "${CYAN}3)${NC} Germany"
    echo -e "${CYAN}4)${NC} China"
    echo -e "${CYAN}5)${NC} Вернуть downloads.openwrt.org"
    echo -e "${CYAN}Enter)${NC} Выход"
    echo -en "\n${YELLOW}Введите номер: ${NC}"
}

# --- главный цикл ---
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
