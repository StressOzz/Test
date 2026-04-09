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

# ===== ПРОВЕРКИ =====
is_installed() {
    command -v redsocks >/dev/null 2>&1
}

# ===== УСТАНОВКА =====
install_all() {
    echo -e "${YELLOW}Установка...${NC}"

    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks ipset curl
    else
        apk update
        apk add redsocks ipset curl
    fi

# --- redsocks config ---
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

# --- IPSET ---
    ipset destroy $IPSET_NAME 2>/dev/null
    ipset create $IPSET_NAME hash:ip

    echo -e "${YELLOW}Загрузка IP Telegram...${NC}"
    curl -s $LIST_URL | while read ip; do
        [ -n "$ip" ] && ipset add $IPSET_NAME $ip 2>/dev/null
    done

# --- firewall include ---
cat > $INCLUDE_FILE <<EOF
# TG REDSOCKS

iptables -t nat -N REDSOCKS 2>/dev/null
iptables -t nat -F REDSOCKS

# исключения
iptables -t nat -A REDSOCKS -d 127.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 192.168.0.0/16 -j RETURN
iptables -t nat -A REDSOCKS -d 10.0.0.0/8 -j RETURN
iptables -t nat -A REDSOCKS -d 172.16.0.0/12 -j RETURN

# редирект
iptables -t nat -A REDSOCKS -p tcp -j REDIRECT --to-ports $REDSOCKS_PORT

# только Telegram через ipset
iptables -t nat -D PREROUTING -p tcp -m set --match-set $IPSET_NAME dst -j REDSOCKS 2>/dev/null
iptables -t nat -A PREROUTING -p tcp -m set --match-set $IPSET_NAME dst -j REDSOCKS
EOF

# --- включаем include ---
    uci -q delete firewall.tg_redsocks
    uci set firewall.tg_redsocks="include"
    uci set firewall.tg_redsocks.type="script"
    uci set firewall.tg_redsocks.path="$INCLUDE_FILE"
    uci set firewall.tg_redsocks.enabled="1"
    uci commit firewall

# --- сервис redsocks ---
cat > /etc/init.d/tg-redsocks <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command redsocks -c /etc/redsocks.conf
    procd_set_param respawn
    procd_close_instance
}
EOF

    chmod +x /etc/init.d/tg-redsocks
    /etc/init.d/tg-redsocks enable
    /etc/init.d/tg-redsocks restart

# --- перезапуск firewall ---
    /etc/init.d/firewall restart

    echo -e "${GREEN}Установлено и настроено (с автозапуском)${NC}"
}

# ===== УДАЛЕНИЕ =====
remove_all() {
    echo -e "${YELLOW}Удаление...${NC}"

    /etc/init.d/tg-redsocks stop 2>/dev/null
    /etc/init.d/tg-redsocks disable 2>/dev/null
    rm -f /etc/init.d/tg-redsocks

    uci -q delete firewall.tg_redsocks
    uci commit firewall

    rm -f $INCLUDE_FILE

    ipset destroy $IPSET_NAME 2>/dev/null
    rm -f /etc/redsocks.conf

    /etc/init.d/firewall restart

    echo -e "${GREEN}Удалено чисто${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG Transparent Proxy (PRO MODE) ===${NC}\n"

        if is_installed; then
            echo "1) Удалить (чисто)"
        else
            echo "1) Установить (с автозапуском)"
        fi

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
            0)
                exit 0
                ;;
        esac
    done
}

menu
