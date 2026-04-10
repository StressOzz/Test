#!/bin/sh

# ===== CONFIG =====
REDSOCKS_PORT="12345"
SOCKS_IP="192.168.1.1"
SOCKS_PORT="1080"

SET_NAME="telegram_list"
CHAIN_NAME="tg_redsocks"

CONF="/etc/redsocks.conf"
NFT_FILE="/etc/nft-tg-redsocks.conf"

# ===== COLORS =====
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
NC="\033[0m"

# ===== PKG =====
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
else
    PKG="apk"
fi

# ===== INSTALL =====
install_all() {
    echo -e "${YELLOW}Установка...${NC}"

    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks
    else
        apk add redsocks
    fi

# --- redsocks config ---
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

# --- nft config (NO firewall.user) ---
cat > $NFT_FILE <<EOF
table inet fw4 {

    set $SET_NAME {
        type ipv4_addr
        flags interval
    }

    chain $CHAIN_NAME {
        type nat hook output priority dstnat; policy accept;

        ip daddr @$SET_NAME tcp dport {80, 443} redirect to :$REDSOCKS_PORT
    }
}
EOF

    # load nft rules
    nft -f $NFT_FILE 2>/dev/null

    # add telegram IPs
    nft flush set inet fw4 $SET_NAME 2>/dev/null
    nft add element inet fw4 $SET_NAME { \
91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
149.154.160.0/20, 185.76.151.0/24 \
}

# --- service ---
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart

    echo -e "${GREEN}Установлено${NC}"
}

# ===== REMOVE =====
remove_all() {
    echo -e "${YELLOW}Удаление...${NC}"

    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null

    rm -f $CONF
    rm -f $NFT_FILE

    nft delete table inet fw4 2>/dev/null

    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks
    else
        apk del redsocks
    fi

    echo -e "${GREEN}Удалено полностью${NC}"
}

# ===== STATUS =====
status() {
    echo -e "${CYAN}=== STATUS ===${NC}"

    pidof redsocks >/dev/null && echo "redsocks: RUNNING" || echo "redsocks: STOPPED"

    nft list set inet fw4 $SET_NAME >/dev/null 2>&1 \
        && echo "nft set: OK" \
        || echo "nft set: MISSING"

    nc -z $SOCKS_IP $SOCKS_PORT >/dev/null 2>&1 \
        && echo "SOCKS: OK" \
        || echo "SOCKS: DOWN"
}

# ===== MENU =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG REDSOCKS PRO ===${NC}"
        echo "1) Install"
        echo "2) Remove"
        echo "3) Status"
        echo "0) Exit"
        echo ""

        read -p "Choice: " c

        case "$c" in
            1) install_all; read -p "Enter..." ;;
            2) remove_all; read -p "Enter..." ;;
            3) status; read -p "Enter..." ;;
            0) exit 0 ;;
            *) echo "Error"; sleep 1 ;;
        esac
    done
}

menu
