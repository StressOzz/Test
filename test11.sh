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

# ===== УСТАНОВКА ПАКЕТОВ =====
install_pkgs() {
    echo -e "${YELLOW}Установка пакетов...${NC}"
    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks ipset iptables-mod-nat-extra curl
    else
        apk update
        apk add redsocks ipset iptables curl
    fi
}

# ===== УДАЛЕНИЕ ПАКЕТОВ =====
remove_pkgs() {
    echo -e "${YELLOW}Удаление пакетов...${NC}"
    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks ipset iptables-mod-nat-extra
    else
        apk del redsocks ipset iptables
    fi
}

# ===== REDSOCKS CONFIG =====
config_redsocks() {
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
}

# ===== IPSET =====
create_ipset() {
    ipset destroy $IPSET_NAME 2>/dev/null
    ipset create $IPSET_NAME hash:ip

    echo -e "${YELLOW}Загрузка IP Telegram...${NC}"
    curl -s $LIST_URL | while read ip; do
        [ -n "$ip" ] && ipset add $IPSET_NAME $ip 2>/dev/null
    done
}

# ===== IPTABLES =====
setup_iptables() {
    iptables -t nat -D PREROUTING -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null

    iptables -t nat -N REDSOCKS
    iptables -t nat -A REDSOCKS -p tcp -m set --match-set $IPSET_NAME dst -j REDIRECT --to-ports $REDSOCKS_PORT
    iptables -t nat -A PREROUTING -p tcp -j REDSOCKS
}

# ===== УДАЛЕНИЕ IPTABLES =====
cleanup_iptables() {
    iptables -t nat -D PREROUTING -p tcp -j REDSOCKS 2>/dev/null
    iptables -t nat -F REDSOCKS 2>/dev/null
    iptables -t nat -X REDSOCKS 2>/dev/null
}

# ===== REDSOCKS =====
start_redsocks() {
    killall redsocks 2>/dev/null
    redsocks -c /etc/redsocks.conf
}

stop_redsocks() {
    killall redsocks 2>/dev/null
}

# ===== STOP =====
stop_all() {
    echo -e "${YELLOW}Отключение...${NC}"
    cleanup_iptables
    ipset destroy $IPSET_NAME 2>/dev/null
    stop_redsocks
    echo -e "${GREEN}Отключено${NC}"
}

# ===== UNINSTALL =====
uninstall_all() {
    echo -e "${YELLOW}Полное удаление...${NC}"
    stop_all
    remove_pkgs
    rm -f /etc/redsocks.conf
    echo -e "${GREEN}Полностью удалено${NC}"
}

# ===== STATUS =====
status() {
    pidof redsocks >/dev/null && echo -e "${GREEN}redsocks запущен${NC}" || echo -e "${RED}redsocks не работает${NC}"
    ipset list $IPSET_NAME >/dev/null 2>&1 && echo -e "${GREEN}ipset есть${NC}" || echo -e "${RED}ipset нет${NC}"
}

# ===== START =====
start_all() {
    install_pkgs
    config_redsocks
    create_ipset
    setup_iptables
    start_redsocks
    echo -e "${GREEN}Прозрачный Telegram прокси включен${NC}"
}

# ===== MENU =====
case "$1" in
    start)
        start_all
        ;;
    stop)
        stop_all
        ;;
    restart)
        stop_all
        sleep 1
        start_all
        ;;
    uninstall)
        uninstall_all
        ;;
    status)
        status
        ;;
    *)
        echo "Использование:"
        echo "$0 start       - включить"
        echo "$0 stop        - выключить"
        echo "$0 restart     - перезапуск"
        echo "$0 status      - статус"
        echo "$0 uninstall   - удалить всё"
        ;;
esac
