#!/bin/sh

ZAPRET_MANAGER_VERSION="7.3"; STR_VERSION_AUTOINSTALL="v5" ZAPRET_VERSION="72.20251213"
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"
WORKDIR="/tmp/zapret-update"; CONF="/etc/config/zapret"; CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
EXCLUDE_URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"

### 1. Системная информация


### Проверка: доступ из браузера активен?
web_is_enabled() {
	command -v ttyd >/dev/null 2>&1 \
	&& uci -q get ttyd.@ttyd[0].command | grep -q "/usr/bin/zms"
}

### 2. Включить / удалить доступ из браузера
toggle_web() {

	if web_is_enabled; then
		echo -e "\n${MAGENTA}Удаляем доступ из браузера${NC}"
		opkg remove luci-app-ttyd ttyd >/dev/null 2>&1
		rm -f /etc/config/ttyd
		rm -f /usr/bin/zms

		echo -e "${GREEN}Доступ удалён${NC}\n"

		read -p "Нажмите Enter..." dummy
	else

	echo -e "\n${MAGENTA}Активируем доступ из браузера${NC}"
		echo 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)' > /usr/bin/zms
chmod +x /usr/bin/zms

echo -e "${CYAN}Обновляем список пакетов${NC}"
if ! opkg update >/dev/null 2>&1; then
    echo -e "\n${RED}Ошибка при обновлении!${NC}\n"
    exit 1
fi

echo -e "${CYAN}Устанавливаем ${NC}ttyd"
if ! opkg install ttyd >/dev/null 2>&1; then
    echo -e "\n${RED}Ошибка при установке ttyd!${NC}\n"
	read -p "Нажмите Enter..." dummy
    return
fi

echo -e "${CYAN}Устанавливаем ${NC}luci-app-ttyd"
if ! opkg install luci-app-ttyd >/dev/null 2>&1; then
    echo -e "\n${RED}Ошибка при установке luci-app-ttyd!${NC}\n"
	read -p "Нажмите Enter..." dummy
    return
fi

echo -e "${CYAN}Настраиваем ${NC}ttyd"
sed -i "s#/bin/login#sh /usr/bin/zms#" /etc/config/ttyd

/etc/init.d/ttyd restart >/dev/null 2>&1

if pidof ttyd >/dev/null; then
    echo -e "${GREEN}Служба запущена!${NC}\n\n${YELLOW}Доступ: ${NC}http://192.168.1.1:7681\n"
	read -p "Нажмите Enter..." dummy
else
    echo -e "\n${RED}Ошибка! Служба не запущена!${NC}\n"
	read -p "Нажмите Enter..." dummy
fi
fi
}

### Проверка: QUIC заблокирован?
quic_is_blocked() {
	uci show firewall | grep -q "name='Block_UDP_80'" \
	&& uci show firewall | grep -q "name='Block_UDP_443'"
}

### 3. Включить / отключить блокировку QUIC
toggle_quic() {

	if quic_is_blocked; then
		echo -e "\n${MAGENTA}Отключаем блокировку QUIC${NC}"

for RULE in Block_UDP_80 Block_UDP_443; do
    while true; do
        IDX=$(uci show firewall | grep "name='$RULE'" | cut -d. -f2 | cut -d= -f1 | head -n1)
        [ -z "$IDX" ] && break
        uci delete firewall.$IDX >/dev/null 2>&1
    done
done



		uci commit firewall >/dev/null 2>&1
		/etc/init.d/firewall restart >/dev/null 2>&1

		echo -e "${GREEN}Блокировка ${NC}QUIC ${GREEN}отключена${NC}\n"
		read -p "Нажмите Enter..." dummy
	else
		echo -e "\n${MAGENTA}Включаем блокировку QUIC${NC}"

		# UDP 80
		uci add firewall rule >/dev/null 2>&1
		uci set firewall.@rule[-1].name='Block_UDP_80' >/dev/null 2>&1
		uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1
		uci set firewall.@rule[-1].src='lan' >/dev/null 2>&1
		uci set firewall.@rule[-1].dest='wan' >/dev/null 2>&1
		uci set firewall.@rule[-1].dest_port='80' >/dev/null 2>&1
		uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1

		# UDP 443
		uci add firewall rule >/dev/null 2>&1
		uci set firewall.@rule[-1].name='Block_UDP_443' >/dev/null 2>&1
		uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1
		uci set firewall.@rule[-1].src='lan' >/dev/null 2>&1
		uci set firewall.@rule[-1].dest='wan' >/dev/null 2>&1
		uci set firewall.@rule[-1].dest_port='443' >/dev/null 2>&1
		uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1

		uci commit firewall >/dev/null 2>&1
		/etc/init.d/firewall restart >/dev/null 2>&1

		echo -e "${GREEN}Блокировка ${NC}QUIC ${GREEN}включена${NC}\n"
		read -p "Нажмите Enter..." dummy
	fi

}

### Главное меню
while true; do

	web_is_enabled \
		&& WEB_TEXT="Удалить доступ к скрипту из браузера" \
		|| WEB_TEXT="Активировать доступ к скрипту из браузера"

	quic_is_blocked \
		&& QUIC_TEXT="${GREEN}Отключить блокировку${NC} QUIC ${GREEN}(80,443)${NC}" || QUIC_TEXT="${GREEN}Включить блокировку${NC} QUIC ${GREEN}(80,443)${NC}"

clear; echo -e "${MAGENTA}Системное меню${NC}\n"

	if web_is_enabled; then echo -e "${YELLOW}Доступ из браузера:${NC} http://192.168.1.1:7681\n"; fi


echo -e "${CYAN}1) ${GREEN}Системная информация${NC}"
echo -e "${CYAN}2) ${GREEN}$WEB_TEXT${NC}"
echo -e "${CYAN}3) ${GREEN}$QUIC_TEXT${NC}"
echo -e "${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n"

echo -ne "${YELLOW}Выберите пункт:${NC} " && read -r choiceMN

	case "$choiceMN" in
		1) wget -qO- https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/sys_info.sh | sh; echo; read -p "Нажмите Enter..." dummy ;;
		2) toggle_web ;;
		3) toggle_quic ;;
		*) echo; exit 0 ;; esac; done
