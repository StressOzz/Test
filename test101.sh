#!/bin/sh

# ===== CONFIG =====
SOCKS_IP="192.168.1.1"
SOCKS_PORT="1080"

REDSOCKS_PORT="12345"

SET_NAME="tg_list"
TABLE="inet fw4"

CONF="/etc/redsocks.conf"
NFT_FILE="/etc/nft-tg.nft"

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m"

# ===== INSTALL REDSOCKS =====
install_redsocks() {
    echo -e "${CYAN}Installing redsocks...${NC}"

    opkg update >/dev/null 2>&1
    opkg install redsocks >/dev/null 2>&1

    cat > "$CONF" <<EOF
base {
    log_info = on;
    log = "syslog";
    daemon = on;
    redirector = nftables;
}

redsocks {
    local_ip = 127.0.0.1;
    local_port = $REDSOCKS_PORT;

    ip = $SOCKS_IP;
    port = $SOCKS_PORT;
    type = socks5;
}
EOF

    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart

    sleep 1

    if pgrep redsocks >/dev/null 2>&1; then
        echo -e "${GREEN}redsocks OK${NC}"
    else
        echo -e "${RED}redsocks FAILED${NC}"
        return 1
    fi
}

# ===== TELEGRAM IP LIST =====
load_ips() {
    echo -e "${CYAN}Loading Telegram IPs...${NC}"

    curl -s https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt \
        | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
        > /tmp/tg.txt

    if [ ! -s /tmp/tg.txt ]; then
        echo "fallback list"

        cat > /tmp/tg.txt <<EOF
91.105.192.0/23
91.108.4.0/22
91.108.8.0/21
91.108.16.0/22
91.108.20.0/22
91.108.56.0/22
149.154.160.0/20
EOF
    fi
}

# ===== NFT RULES =====
setup_nft() {
    echo -e "${CYAN}Setting nftables...${NC}"

    load_ips

    nft add table inet fw4 2>/dev/null

    nft "add set inet fw4 $SET_NAME { type ipv4_addr; flags interval; }" 2>/dev/null

    nft add chain inet fw4 tg_prerouting '{ type nat hook prerouting priority dstnat; policy accept; }' 2>/dev/null

    nft add chain inet fw4 tg_output '{ type nat hook output priority dstnat; policy accept; }' 2>/dev/null

    # redirect Telegram → redsocks
    nft add rule inet fw4 tg_prerouting ip daddr @$SET_NAME tcp dport {80,443} redirect to :$REDSOCKS_PORT

    nft add rule inet fw4 tg_output ip daddr @$SET_NAME tcp dport {80,443} redirect to :$REDSOCKS_PORT

    # fill set
    while read ip; do
        [ -z "$ip" ] && continue
        nft add element inet fw4 $SET_NAME { $ip } 2>/dev/null
    done < /tmp/tg.txt

    echo -e "${GREEN}nft OK${NC}"
}

# ===== STATUS =====
status() {
    echo "---- STATUS ----"

    pgrep redsocks >/dev/null && echo "redsocks: RUN" || echo "redsocks: STOP"

    nft list set inet fw4 $SET_NAME >/dev/null 2>&1 \
        && echo "nft set: OK" || echo "nft set: NO"

    nft list chain inet fw4 tg_prerouting >/dev/null 2>&1 \
        && echo "prerouting: OK"
}

# ===== REMOVE =====
remove() {
    /etc/init.d/redsocks stop

    nft delete chain inet fw4 tg_prerouting 2>/dev/null
    nft delete chain inet fw4 tg_output 2>/dev/null
    nft delete set inet fw4 $SET_NAME 2>/dev/null

    rm -f "$CONF" "$NFT_FILE" /tmp/tg.txt

    echo "removed"
}

# ===== MENU =====
while true; do
    echo ""
    echo "1 install"
    echo "2 status"
    echo "3 remove"
    echo "0 exit"

    read -p ">> " c

    case "$c" in
        1) install_redsocks && setup_nft ;;
        2) status ;;
        3) remove ;;
        0) exit 0 ;;
    esac
done
