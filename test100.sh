#!/bin/sh

# ===== НАСТРОЙКИ =====
REDSOCKS_PORT="12345"
SOCKS_IP="127.0.0.1"
SOCKS_PORT="1080"

CONF="/etc/redsocks.conf"
FW_USER="/etc/firewall.user"

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

# ===== УСТАНОВКА =====
install_all() {
    echo -e "${YELLOW}Установка...${NC}"

    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks
    else
        apk update
        apk add redsocks
    fi

# --- конфиг redsocks ---
cat > $CONF <<EOF
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = $REDSOCKS_PORT;
    ip = $SOCKS_IP;
    port = $SOCKS_PORT;
    type = socks5;
}
EOF

# --- firewall.user ---
cat > $FW_USER << 'EOF'
# === TG REDSOCKS ===

nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null

nft flush set inet fw4 telegram_list
nft add element inet fw4 telegram_list { \
91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
149.154.160.0/20, 185.76.151.0/24 \
}

nft delete rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345 2>/dev/null
nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345
EOF

# --- сервис ---
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart

# --- firewall ---
    /etc/init.d/firewall restart

    echo -e "${GREEN}Готово!${NC}"
}

# ===== УДАЛЕНИЕ =====
remove_all() {
    echo -e "${YELLOW}Удаление...${NC}"

    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null

    rm -f $CONF

    # очищаем firewall.user полностью (как в посте)
    rm -f $FW_USER

    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks
    else
        apk del redsocks
    fi

    /etc/init.d/firewall restart

    echo -e "${GREEN}Удалено полностью${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG REDSOCKS (NFT) ===${NC}\n"
        echo "1) Установить и настроить"
        echo "2) Полностью удалить"
        echo "0) Выход"
        echo ""
        read -p "Выбор: " c

        case "$c" in
            1) install_all; read -p "Enter...";;
            2) remove_all; read -p "Enter...";;
            0) exit 0;;
            *) echo "Ошибка"; sleep 1;;
        esac
    done
}

menu
