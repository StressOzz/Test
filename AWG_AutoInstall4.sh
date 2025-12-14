#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
WHITE="\033[1;37m"
BLUE="\033[0;34m"
GRAY='\033[38;5;239m'
DGRAY='\033[38;5;236m'

show_menu() {

	clear
	echo -e "╔═══════════════════════════════╗"
	echo -e "║     ${BLUE}Podkop+AWG   Manager${NC}     ║"
	echo -e "╚═══════════════════════════════╝"


    echo -e "\n${CYAN}1) ${GREEN}Установить / обновить ${NC}Podkop"
    echo -e "${CYAN}2) ${GREEN}Установить AWG интерфэйс${NC}"
	echo -e "${CYAN}3) ${GREEN}Под КЛЮЧ${NC}"
    echo -ne "\n${YELLOW}Выберите пункт:${NC} "
    read choice

    case "$choice" in
        1) PODKOP_INSTALL ;;
        2) AWG_INSTALL ;;
		3) AWG_INSTALL; 

		echo -e "${GREEN}Вставьте рабочий конфиг в Interfaces и нажмите ENTER ${NC}"
		read -p "Нажмите Enter..." dummy
		
		PODKOP_INSTALL ;;
		
        *) exit 0 ;;
    esac
}



##################################################################################################################################################
AWG_INSTALL() {
    echo "Устанавливаем AmneziaWG..."

    TMP="/tmp/amneziawg"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v24.10.4"

    rm -rf "$TMP"
    mkdir -p "$TMP"
    cd "$TMP" || return

    opkg update >/dev/null 2>&1

    ARCH=$(opkg print-architecture | awk '{print $2}' | tail -n1)
    TARGET=$(ubus call system board | jsonfilter -e '@.release.target')

    SUFFIX="_v24.10.4_${ARCH}_${TARGET}.ipk"

    install() {
        pkg="$1"
        file="${pkg}${SUFFIX}"
        opkg list-installed | grep -q "$pkg" && return
        wget -q "$BASE_URL/$file" && opkg install "$file"
    }

    install kmod-amneziawg
    install amneziawg-tools
    install luci-proto-amneziawg
    install luci-i18n-amneziawg-ru

    cd /
    rm -rf "$TMP"

    /etc/init.d/network restart >/dev/null 2>&1

    echo "AmneziaWG установлен."
	read -p "Нажмите Enter..." dummy

##################################################################################################################

# Имя интерфейса и протокол

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"

# Проверяем, есть ли уже такой интерфейс

if grep -q "config interface '$IF_NAME'" /etc/config/network; then
echo "Интерфейс $IF_NAME уже существует"
else
echo "Добавляем интерфейс $IF_NAME..."
uci batch <<EOF
set network.$IF_NAME=interface
set network.$IF_NAME.proto=$PROTO
set network.$IF_NAME.device=$DEV_NAME
commit network
EOF
fi

# Перезапускаем сеть, firewall и веб-интерфейс LuCI

/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
echo "Интерфейс $IF_NAME создан и активирован. Проверьте LuCI."
read -p "Нажмите Enter..." dummy
}
##################################################################################################################
PODKOP_INSTALL() {
    PODKOP_VER="0.7.10"

    echo "Устанавливаем Podkop v$PODKOP_VER..."

    TMP="/tmp/podkop"
    BASE_URL="https://github.com/itdoginfo/podkop/releases/download/$PODKOP_VER"

    rm -rf "$TMP"
    mkdir -p "$TMP"
    cd "$TMP" || return

    wget -q "$BASE_URL/podkop-v$PODKOP_VER-r1-all.ipk"
    wget -q "$BASE_URL/luci-app-podkop-v$PODKOP_VER-r1-all.ipk"
    wget -q "$BASE_URL/luci-i18n-podkop-ru-$PODKOP_VER.ipk"

    opkg update >/dev/null 2>&1
    opkg install ./*.ipk >/dev/null 2>&1

    wget -qO /etc/config/podkop \
        https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/podkop

    podkop enable >/dev/null 2>&1
    podkop restart >/dev/null 2>&1
    podkop list_update >/dev/null 2>&1

    cd /
    rm -rf "$TMP"

    echo "Podkop v$PODKOP_VER установлен и работает."
read -p "Нажмите Enter..." dummy
	
}



# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
