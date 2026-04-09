#!/bin/sh

# ===== НАСТРОЙКИ =====
REDSOCKS_PORT=12345
SOCKS_IP="127.0.0.1"
SOCKS_PORT=1080
FIREWALL_USER="/etc/firewall.user"
REDSOCKS_CONF="/etc/redsocks.conf"
TELEGRAM_SET="telegram_list"

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
    echo -e "${YELLOW}Установка и настройка...${NC}"

    # --- пакеты ---
    if [ "$PKG" = "opkg" ]; then
        opkg update
        opkg install redsocks curl -y
    else
        apk update
        apk add redsocks curl
    fi

    # --- конфиг redsocks ---
    cat > $REDSOCKS_CONF <<EOF
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

    # --- автозапуск и старт сервиса ---
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart

    # --- firewall.user ---
    cat >> $FIREWALL_USER <<EOF

# === TG REDSOCKS ===
# Создаём set
nft add set inet fw4 $TELEGRAM_SET '{ type ipv4_addr; flags interval; }' 2>/dev/null

# Чистим и добавляем диапазоны
nft flush set inet fw4 $TELEGRAM_SET
nft add element inet fw4 $TELEGRAM_SET { \
91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
149.154.160.0/20, 185.76.151.0/24 \
}

# Правило редиректа TCP 80,443
nft delete rule inet fw4 dstnat ip daddr @$TELEGRAM_SET tcp dport { 80, 443 } counter redirect to :$REDSOCKS_PORT 2>/dev/null
nft insert rule inet fw4 dstnat ip daddr @$TELEGRAM_SET tcp dport { 80, 443 } counter redirect to :$REDSOCKS_PORT
EOF

    # --- перезапуск firewall ---
    /etc/init.d/firewall restart

    echo -e "${GREEN}Установлено и настроено!${NC}"
}

# ===== УДАЛЕНИЕ =====
remove_all() {
    echo -e "${YELLOW}Удаляем всё, что создавали...${NC}"

    # --- останавливаем redsocks ---
    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null

    # --- удаляем конфиг и правило ---
    rm -f $REDSOCKS_CONF

    # --- удаляем set и правила в firewall.user ---
    if [ -f $FIREWALL_USER ]; then
        sed -i '/# === TG REDSOCKS ===/,$d' $FIREWALL_USER
    fi

    # --- удаляем пакет redsocks ---
    if [ "$PKG" = "opkg" ]; then
        opkg remove redsocks
    else
        apk del redsocks
    fi

    # --- перезапуск firewall ---
    /etc/init.d/firewall restart

    echo -e "${GREEN}Полностью удалено!${NC}"
}

# ===== МЕНЮ =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}=== TG Transparent Proxy Menu ===${NC}\n"
        echo "1) Установить и настроить"
        echo "2) Полностью удалить"
        echo "0) Выход"
        echo ""
        read -p "Выбор: " choice
        case "$choice" in
            1) install_all; read -p "Enter...";;
            2) remove_all; read -p "Enter...";;
            0) exit 0;;
            *) echo "Неверный выбор"; sleep 1;;
        esac
    done
}

menu
