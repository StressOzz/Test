#!/bin/sh

# ===== НАСТРОЙКИ =====
SOCKS_IP="127.0.0.1"
SOCKS_PORT="1080"
REDSOCKS_PORT="12345"
IPSET_NAME="telegram"
LIST_URL="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"

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

# ===== ПРОВЕРКИ =====
is_installed() {
    command -v redsocks >/dev/null 2>&1
}

is_running() {
    pidof redsocks >/dev/null 2>&1
}

# ===== УСТАНОВКА =====
install_all() {
    echo -e "${YELLOW}Установка...${NC}"

    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks ipset iptables-mod-nat-extra curl
    else
        apk update
        apk add redsocks ipset iptables curl
    fi

cat > /etc/redsocks.conf <<EOF
base {
 log_debug = off;
 log_info = off;
 daemon = on;
 redirector = iptables;
}

redsocks {
 local_ip = 127.0.0.1;
 local_port = $REDSOCKS_PORT;

 ip = $SOCKS_IP;
 port = $SOCKS_PORT;
 type = socks5;
}
EOF

    ipset destroy $IPSET_NAME 2>/dev/null
    ipset create $IPSET_NAME hash:ip

    echo -e "${YELLOW}Загрузка IP Telegram...${NC}"
    curl -s $LIST_URL | while read ip; do
        [ -n "$ip" ] && ipset add $IPSET_NAME $ip 2>/dev/null
    done

    iptables -t nat -N REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS

    iptables -t nat -A REDSOCKS -p tcp -m set --match-set $IPSET_NAME dst -j REDIRECT --to-ports $REDSOCKS_PORT
    iptables -t nat -A PREROUTING -p tcp -j REDSOCKS

    killall redsocks 2>/dev/null
    redsocks -c /etc/redsocks.conf

    echo -e "${GREEN}Установлено и включено${NC}"
}

# ===== УДАЛЕНИЕ =====
remove_all() {
    echo -e "${YELLOW}Удаление...${NC}"

    iptables -t nat -D PREROUTING -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null

    ipset destroy $IPSET_NAME 2>/dev/null
    killall redsocks 2>/dev/null

    rm -f /etc/redsocks.conf

    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks ipset iptables-mod-nat-extra
    else
        apk del redsocks ipset iptables
    fi

    echo -e "${GREEN}Полностью удалено${NC}"
}

# ===== СТАТУС =====
show_status() {
    echo -e "${CYAN}--- СТАТУС ---${NC}"

    if is_installed; then
        echo -e "redsocks: ${GREEN}установлен${NC}"
    else
        echo -e "redsocks: ${RED}не установлен${NC}"
    fi

    if is_running; then
        echo -e "сервис:  ${GREEN}запущен${NC}"
    else
        echo -e "сервис:  ${RED}не работает${NC}"
    fi

    ipset list $IPSET_NAME >/dev/null 2>&1 && \
        echo -e "ipset:    ${GREEN}есть${NC}" || \
        echo -e "ipset:    ${RED}нет${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG Transparent Proxy (redsocks) ===${NC}\n"

        show_status
        echo ""

        if is_installed; then
            echo "1) Удалить (полностью)"
        else
            echo "1) Установить и включить"
        fi

        echo "2) Перезапустить"
        echo "3) Статус"
        echo "0) Выход"

        echo ""
        read -p "Выбор: " choice

        case "$choice" in
            1)
                if is_installed; then
                    remove_all
                else
                    install_all
                fi
                read -p "Enter..."
                ;;
            2)
                remove_all
                sleep 1
                install_all
                read -p "Enter..."
                ;;
            3)
                show_status
                read -p "Enter..."
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
