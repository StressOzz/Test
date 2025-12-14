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
printf "${GREEN}===== Обновление списка пакетов =====${NC}\n"
opkg update
printf "${GREEN}===== Определяем архитектуру и версию OpenWrt =====${NC}\n"
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
printf "${GREEN}===== Определяем версию AWG =====${NC}\n"
MAJOR=$(echo "$VERSION" | cut -d '.' -f1)
MINOR=$(echo "$VERSION" | cut -d '.' -f2)
PATCH=$(echo "$VERSION" | cut -d '.' -f3)
AWG_VERSION="1.0"
if [ "$MAJOR" -gt 24 ] || \
   [ "$MAJOR" -eq 24 -a "$MINOR" -gt 10 ] || \
   [ "$MAJOR" -eq 24 -a "$MINOR" -eq 10 -a "$PATCH" -ge 3 ] || \
   [ "$MAJOR" -eq 23 -a "$MINOR" -eq 5 -a "$PATCH" -ge 6 ]; then
    AWG_VERSION="2.0"
    LUCI_PACKAGE_NAME="luci-proto-amneziawg"
else
    LUCI_PACKAGE_NAME="luci-app-amneziawg"
fi
printf "${GREEN}Detected AWG version: $AWG_VERSION${NC}\n"
AWG_DIR="/tmp/amneziawg"
mkdir -p "$AWG_DIR"
install_pkg() {
    local pkgname=$1
    local filename="${pkgname}${PKGPOSTFIX}"
    local url="${BASE_URL}v${VERSION}/${filename}"

    if opkg list-installed | grep -q "$pkgname"; then
        printf "${GREEN}$pkgname уже установлен${NC}\n"
        return
    fi

    printf "${GREEN}===== Скачиваем $pkgname =====${NC}\n"
    if wget -O "$AWG_DIR/$filename" "$url"; then
        printf "${GREEN}===== Устанавливаем $pkgname =====${NC}\n"
        if opkg install "$AWG_DIR/$filename"; then
            printf "${GREEN}$pkgname установлен успешно${NC}\n"
        else
            printf "${GREEN}Ошибка установки $pkgname. Установите вручную.${NC}\n"
            exit 1
        fi
    else
        printf "${GREEN}Ошибка скачивания $pkgname. Установите вручную.${NC}\n"
        exit 1
    fi
}
printf "${GREEN}===== Устанавливаем kmod-amneziawg =====${NC}\n"
install_pkg "kmod-amneziawg"
printf "${GREEN}===== Устанавливаем amneziawg-tools =====${NC}\n"
install_pkg "amneziawg-tools"
printf "${GREEN}===== Устанавливаем $LUCI_PACKAGE_NAME =====${NC}\n"
install_pkg "$LUCI_PACKAGE_NAME"
# Русская локализация только для AWG 2.0
if [ "$AWG_VERSION" = "2.0" ]; then
    printf "${GREEN}===== Устанавливаем русскую локализацию =====${NC}\n"
	install_pkg "luci-i18n-amneziawg-ru" || printf "${GREEN}Внимание: русская локализация не установлена (не критично)${NC}\n"
    else
        printf "${GREEN}Пропускаем установку русской локализации.${NC}\n"
    fi
printf "${GREEN}===== Очистка временных файлов =====${NC}\n"
rm -rf "$AWG_DIR"
printf "${GREEN}===== Перезапускаем сеть =====${NC}\n"
/etc/init.d/network restart
printf "${GREEN}===== Скрипт завершен =====${NC}\n"
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
