#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)

if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    UPDATE="opkg update"
    INSTALL="opkg install"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
fi

echo -e "${MAGENTA}=== Обновляем пакеты ===${NC}"
$UPDATE

echo -e "${MAGENTA}=== Устанавливаем минимально необходимые пакеты ===${NC}"
$INSTALL python3-light python3-pip git git-http

# WORKDIR="/root/tg-ws-proxy"

# rm -rf "$WORKDIR"

# cd /root

git clone https://github.com/Flowseal/tg-ws-proxy

# cd "$WORKDIR"

pip install -e .

cat << 'EOF' > /etc/init.d/tg-ws-proxy
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy --host 0.0.0.0
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/tg-ws-proxy
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo -e "\n${GREEN}=== Установка завершена ===${NC}"
echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"
