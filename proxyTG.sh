#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
RED="\033[1;31m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"
NC="\033[0m"

if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    UPDATE="opkg update"
    INSTALL="opkg install --force-reinstall"
    DELETE="opkg remove --force-removal-of-dependent-packages"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add --force-reinstall"
    DELETE="apk del --force-removal-of-dependent-packages"
fi

LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

is_installed() {
    if [ -d "/root/tg-ws-proxy" ] || python3 -m pip show tg-ws-proxy >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

is_running() {
    if pgrep -f tg-ws-proxy >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

install_tg_ws() {
echo -e "\n${MAGENTA}=== Обновляем пакеты ===${NC}"
$UPDATE

echo -e "${MAGENTA}=== Устанавливаем необходимые пакеты ===${NC}"
$INSTALL python3-light python3-pip git git-http

echo -e "${MAGENTA}=== Устанавливаем tg-ws-proxy ===${NC}"
rm -rf "/root/tg-ws-proxy"
git clone https://github.com/Flowseal/tg-ws-proxy
cd tg-ws-proxy
pip install --no-deps -e .
# pip install -e .

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
/etc/init.d/tg-ws-proxy enable >/dev/null 2>&1
/etc/init.d/tg-ws-proxy start >/dev/null 2>&1

echo -e "\n${GREEN}=== Установка завершена ===${NC}"
PAUSE
}

delete_tg_ws() {
echo -e "\n${MAGENTA}=== Удаялем tg-ws-proxy ===${NC}"

echo -e "${CYAN}Останавливаем сервис${NC}"
/etc/init.d/tg-ws-proxy stop >/dev/null 2>&1
/etc/init.d/tg-ws-proxy disable >/dev/null 2>&1

echo -e "${CYAN}Удаляем init.d скрипт${NC}"
rm -f /etc/init.d/tg-ws-proxy >/dev/null 2>&1

echo -e "${CYAN}Удаляем tg-ws-proxy${NC}"
rm -rf /root/tg-ws-proxy >/dev/null 2>&1

echo -e "${CYAN}Удаляем Python пакет${NC}"
python3 -m pip uninstall -y tg-ws-proxy >/dev/null 2>&1
pip uninstall -y tg-ws-proxy >/dev/null 2>&1

echo -e "${CYAN}Удаляем зависимости${NC}"
$DELETE python3-light python3-pip git git-http >/dev/null 2>&1

echo -e "\n${GREEN}=== Удаление завершино ===${NC}"
PAUSE
}

menu() {
clear
echo -e "╔═════════════════════════════════╗"
echo -e "║ ${BLUE}tg-ws-proxy by Flowseal Manager${NC} ║"
echo -e "╚═════════════════════════════════╝"
echo -e "                       ${DGRAY}by StressOzz${NC}\n"

if is_running; then
    echo -e "${YELLOW}tg-ws-proxy:   ${GREEN}запущен${NC}"
elif is_installed; then
    echo -e "${YELLOW}Cтатус tg-ws-proxy: ${RED}не запущен${NC}"
else
    echo -e "${YELLOW}Cтатус tg-ws-proxy: ${RED}не установлен${NC}"
fi

if is_running; then
    PORT=$(netstat -lnpt >/dev/null 2>&1 | grep tg-ws-proxy | awk '{print $4}' | cut -d: -f2)
    echo -e "${YELLOW}адресс SOCKS5: ${NC}$LAN_IP:${PORT:-1080}"
fi

echo -e "\n${CYAN}1) ${GREEN}Установить${NC} tg-ws-proxy"
echo -e "${CYAN}2) ${GREEN}Удалить${NC} tg-ws-proxy"
echo -e "${CYAN}Enter) ${GREEN}Выход${NC}\n"
echo -en "${YELLOW}Выберите пункт: ${NC}"
read choice
case "$choice" in 
1) install_tg_ws ;;
2) delete_tg_ws ;;
*) echo; exit 0 ;;
esac
}
while true; do menu; done
