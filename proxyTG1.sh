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
    REMOVE="opkg remove --force-depends"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
    REMOVE="apk del"
fi

FREE_KB=$(df /root | tail -1 | awk '{print $4}')
FREE_MB=$((FREE_KB / 1024))

if [ "$FREE_MB" -ge 51 ]; then
    echo -e "---> ${GREEN}Свободно ${NC}$FREE_MB ${GREEN}МБ${NC}"
else
    echo -e "\n${RED}Не достаточно места для установки!${NC}\n"
    exit 0
fi

echo -e "${GREEN}=== ${MAGENTA}Обновляем пакеты ${GREEN}===${NC}"
$UPDATE

echo -e "${GREEN}=== ${MAGENTA}Устанавливаем необходимые пакеты ${GREEN}===${NC}"
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

echo -e "${GREEN}=== ${MAGENTA}Очистка мусора ${GREEN}===${NC}"

rm -rf /root/.cache/pip
rm -rf "$WORKDIR/.git"
$REMOVE python3-pip git git-http

echo -e "\n${MAGENTA}=== ${GREEN}Установка завершена${MAGENTA} ===${NC}\n"

echo -e "${GREEN}=== ${MAGENTA}Проверяем работу прокси ${GREEN}===${NC}"
sleep 2
    
if pgrep -f "tg-ws-proxy" > /dev/null; then
    echo -e "${GREEN}✓${NC} ${CYAN}tg-ws-proxy ${GREEN}запущен${NC}"
    PROCESS_OK=1
else
    echo -e "${RED}Процесс tg-ws-proxy не запущен${NC}"
    PROCESS_OK=0
fi

if netstat -tuln | grep -q ":1080 "; then
    echo -e "${GREEN}✓${NC} ${CYAN}порт 1080 ${GREEN}прослушивается${NC}"
    PORT_OK=1
else
    echo -e "${RED}Порт 1080 не прослушивается${NC}"
    PORT_OK=0
fi

if [ "$PROCESS_OK" -eq 1 ] && [ "$PORT_OK" -eq 1 ]; then
    echo -e "\n${YELLOW}Telegram прокси доступен: ${NC}$LAN_IP:1080\n"
else
    echo -e "\n${RED}Прокси не работает!${NC}\n"
fi
