#!/bin/sh

# ===== НАСТРОЙКИ =====
SOCKS_IP="127.0.0.1"
SOCKS_PORT="1080"
REDSOCKS_PORT="12345"
IPSET_NAME="telegram"
LIST_URL="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"

INCLUDE_FILE="/etc/firewall.tg-redsocks"

# ===== ЦВЕТА =====
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
NC="\033[0m"

# ===== PKG =====
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
elif command -v apk >/dev/null 2>&1; then
    PKG="apk"
else
    echo -e "${RED}Пакетный менеджер не найден${NC}"
    exit 1
fi

# ===== УДАЛЕНИЕ ВСЕГО =====
remove_all() {
    echo -e "${YELLOW}Удаляем полностью всё, что ставили...${NC}"

    # --- останавливаем сервис ---
    /etc/init.d/tg-redsocks stop 2>/dev/null
    /etc/init.d/tg-redsocks disable 2>/dev/null
    rm -f /etc/init.d/tg-redsocks

    # --- удаляем конфиги ---
    rm -f /etc/redsocks.conf
    rm -f $INCLUDE_FILE

    # --- удаляем ipset ---
    ipset destroy $IPSET_NAME 2>/dev/null

    # --- удаляем include из UCI ---
    uci -q delete firewall.tg_redsocks
    uci commit firewall

    # --- перезапускаем firewall чтобы убрать правила ---
    /etc/init.d/firewall restart

    # --- удаляем пакеты полностью ---
    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks ipset curl -y
    else
        apk del redsocks ipset curl
    fi

    echo -e "${GREEN}Полностью удалено!${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG Transparent Proxy: FULL REMOVE ===${NC}\n"
        echo "1) Полностью удалить всё"
        echo "0) Выход"
        echo ""
        read -p "Выбор: " choice
        case "$choice" in
            1)
                remove_all
                read -p "Нажми Enter для выхода..."
                exit 0
                ;;
            0)
                exit 0
                ;;
            *)
                echo "Неверный выбор"
                sleep 1
                ;;
        esac
    done
}

menu
