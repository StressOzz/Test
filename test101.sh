#!/bin/sh

# ===== НАСТРОЙКИ =====
REDSOCKS_PORT="12345"
SOCKS_IP="127.0.0.1"
SOCKS_PORT="1080"

CONF="/etc/redsocks.conf"
FW_USER="/etc/firewall.user"
TAG_BEGIN="# >>> TG REDSOCKS BEGIN >>>"
TAG_END="# <<< TG REDSOCKS END <<<"

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

# ===== ПРОВЕРКА =====
is_installed() {
    [ -f "$CONF" ]
}

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

# --- удаляем старый блок если был ---
sed -i "/$TAG_BEGIN/,/$TAG_END/d" $FW_USER 2>/dev/null

# --- добавляем блок аккуратно ---
cat >> $FW_USER <<EOF

$TAG_BEGIN
nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null

nft flush set inet fw4 telegram_list
nft add element inet fw4 telegram_list { \\
91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \\
91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \\
91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \\
149.154.160.0/20, 185.76.151.0/24 \\
}

nft delete rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :$REDSOCKS_PORT 2>/dev/null
nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :$REDSOCKS_PORT
$TAG_END
EOF

# --- сервис ---
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart

# --- firewall ---
    /etc/init.d/firewall restart

    echo -e "${GREEN}Установлено и работает${NC}"
}

# ===== УДАЛЕНИЕ =====
remove_all() {
    echo -e "${YELLOW}Удаление...${NC}"

    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null

    rm -f $CONF

    # удаляем только наш блок
    sed -i "/$TAG_BEGIN/,/$TAG_END/d" $FW_USER 2>/dev/null

    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks
    else
        apk del redsocks
    fi

    /etc/init.d/firewall restart

    echo -e "${GREEN}Удалено чисто${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG REDSOCKS (SMART) ===${NC}\n"

        if is_installed; then
            echo "1) Удалить"
        else
            echo "1) Установить"
        fi

        echo "0) Выход"
        echo ""

        read -p "Выбор: " c

        case "$c" in
            1)
                if is_installed; then
                    remove_all
                else
                    install_all
                fi
                read -p "Enter..."
                ;;
            0) exit 0 ;;
            *) echo "Ошибка"; sleep 1 ;;
        esac
    done
}

menu
