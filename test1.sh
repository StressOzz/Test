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
    REMOVE="opkg remove"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
    REMOVE="apk del"
fi

echo -e "${MAGENTA}=== Обновляем пакеты ===${NC}"
$UPDATE

echo -e "${MAGENTA}=== Устанавливаем минимально необходимые пакеты ===${NC}"
# Устанавливаем python3-pip, но потом удалим его
$INSTALL python3-light python3-pip git-http

WORKDIR="/root/tg-ws-proxy"

rm -rf "$WORKDIR"

cd /root
git clone https://github.com/Flowseal/tg-ws-proxy
cd "$WORKDIR"

pip install -e .

# Создаем init скрипт
cat << 'EOF' > /etc/init.d/tg-ws-proxy
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/python3 /root/tg-ws-proxy/tg_ws_proxy/__main__.py --host 0.0.0.0
    procd_set_param limits memory="262144"
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/tg-ws-proxy
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo -e "\n${GREEN}=== Установка завершена ===${NC}"
echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"

# Показываем экономию памяти
echo -e "\n${MAGENTA}=== Использование памяти ===${NC}"
free -h

# Показываем размер установленных Python пакетов
echo -e "\n${MAGENTA}=== Размер установленных пакетов ===${NC}"
du -sh /usr/lib/python3.*/site-packages/ 2>/dev/null || true
