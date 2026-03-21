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

echo -e "\n${GREEN}=== Установка завершена ===${NC}"
echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"

sleep 2
if pgrep -f "tg-ws-proxy" > /dev/null; then
    echo -e "${GREEN}✓ Процесс tg-ws-proxy запущен${NC}"
    PROCESS_OK=1
else
    echo -e "${RED}✗ Процесс tg-ws-proxy не запущен${NC}"
    PROCESS_OK=0
fi

# Проверяем, слушает ли порт 1080
if netstat -tuln | grep -q ":1080 "; then
    echo -e "${GREEN}✓ Порт 1080 прослушивается${NC}"
    PORT_OK=1
else
    echo -e "${RED}✗ Порт 1080 не прослушивается${NC}"
    PORT_OK=0
fi

# Проверяем доступность прокси
if command -v curl >/dev/null 2>&1; then
    echo -e "\n${MAGENTA}=== Проверка доступности прокси через curl ===${NC}"
    if curl -s -x "socks5://127.0.0.1:1080" --connect-timeout 5 https://api.telegram.org > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Прокси работает (успешное соединение с Telegram API)${NC}"
        CURL_OK=1
    else
        echo -e "${RED}✗ Прокси не отвечает (ошибка соединения)${NC}"
        CURL_OK=0
    fi
else
    echo -e "${YELLOW}! curl не установлен, проверка через curl пропущена${NC}"
    CURL_OK=2
fi

# Проверяем логи на наличие ошибок
echo -e "\n${MAGENTA}=== Проверка логов ===${NC}"
if logread | tail -20 | grep -i "tg-ws-proxy" | grep -qi "error"; then
    echo -e "${YELLOW}⚠ Найдены ошибки в логах:${NC}"
    logread | tail -20 | grep -i "tg-ws-proxy" | grep -i "error"
else
    echo -e "${GREEN}✓ Критических ошибок в логах не найдено${NC}"
fi

# Итоговый результат
echo -e "\n${MAGENTA}=== ИТОГОВАЯ ПРОВЕРКА ===${NC}"
if [ "$PROCESS_OK" -eq 1 ] && [ "$PORT_OK" -eq 1 ] && { [ "$CURL_OK" -eq 1 ] || [ "$CURL_OK" -eq 2 ]; }; then
    echo -e "${GREEN}✅ Прокси работает корректно!${NC}"
    echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"
    echo -e "${YELLOW}Проверить работу можно командой:${NC}"
    echo "curl -x socks5://$LAN_IP:1080 https://api.telegram.org"
else
    echo -e "${RED}❌ Прокси не работает!${NC}"
    echo -e "\n${YELLOW}Проверьте статус сервиса:${NC}"
    echo "/etc/init.d/tg-ws-proxy status"
    echo -e "\n${YELLOW}Проверьте логи:${NC}"
    echo "logread | grep tg-ws-proxy"
    echo -e "\n${YELLOW}Попробуйте перезапустить:${NC}"
    echo "/etc/init.d/tg-ws-proxy restart"
fi
