#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
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

echo -e "${MAGENTA}=== Устанавливаем необходимые пакеты ===${NC}"
$INSTALL python3-light python3-pip git-http

WORKDIR="/root/tg-ws-proxy"

rm -rf "$WORKDIR"

cd /root
git clone https://github.com/Flowseal/tg-ws-proxy
cd "$WORKDIR"

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

echo -e "\n${GREEN}=== Установка завершена ===${NC}\n"

echo -e "${MAGENTA}=== Очистка мусора ===${NC}"

# удаляем pip cache
rm -rf /root/.cache/pip

# удаляем git метаданные
rm -rf "$WORKDIR/.git"

# удаляем ненужные пакеты
$REMOVE python3-pip git-http 2>/dev/null


echo -e "${MAGENTA}=== Проверяем работу прокси ===${NC}"
sleep 2
if pgrep -f "tg-ws-proxy" > /dev/null; then
    echo -e "${GREEN}✓${NC} tg-ws-proxy запущен${NC}"
    PROCESS_OK=1
else
    echo -e "${RED}Процесс tg-ws-proxy не запущен${NC}"
    PROCESS_OK=0
fi

if netstat -tuln | grep -q ":1080 "; then
    echo -e "${GREEN}✓${NC} Порт 1080 прослушивается"
    PORT_OK=1
else
    echo -e "${RED}Порт 1080 не прослушивается${NC}"
    PORT_OK=0
fi

if [ "$PROCESS_OK" -eq 1 ] && [ "$PORT_OK" -eq 1 ]; then
    echo -e "\n${GREEN}Прокси работает корректно!${NC}"
    echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"
else
    echo -e "${RED}Прокси не работает!${NC}"
fi
