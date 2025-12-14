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
	echo -e "${CYAN}2) ${GREEN}Под КЛЮЧ${NC}"
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
install() {
echo -e "${MAGENTA}Установка / обновление Podkop${NC}\n"

    REPO="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    DOWNLOAD_DIR="/tmp/podkop"

    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    msg() {
        if [ -n "$2" ]; then
            printf "\033[32;1m%s \033[37;1m%s\033[0m\n" "$1" "$2"
        else
            printf "\033[32;1m%s\033[0m\n" "$1"
        fi
    }

    pkg_is_installed () {
        local pkg_name="$1"

            opkg list-installed | grep -q "$pkg_name"

    }

    pkg_remove() {
        local pkg_name="$1"
        msg "Удаляем" "$pkg_name..."
            opkg remove --force-depends "$pkg_name" >/dev/null 2>&1

    }

    pkg_list_update() {
        msg "Обновляем список пакетов..."
            opkg update >/dev/null 2>&1
    }

    pkg_install() {
        local pkg_file="$1"
        msg "Устанавливаем" "$(basename "$pkg_file")"
    }

    # Проверка системы
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "не определено")
    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=26000
	
[ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && { 
    msg "Недостаточно свободного места"
    echo ""
    read -p "Нажмите Enter..." dummy
    return
}


    if pkg_is_installed https-dns-proxy; then
        msg "Обнаружен конфликтный пакет" "https-dns-proxy. Удаляем..."
        pkg_remove luci-app-https-dns-proxy
        pkg_remove https-dns-proxy
        pkg_remove luci-i18n-https-dns-proxy*
    fi

    # Проверка sing-box
    if pkg_is_installed "^sing-box"; then
        sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
        required_version="1.12.4"
        if [ "$(echo -e "$sing_box_version\n$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
            msg "sing-box устарел. Удаляем..."
            service podkop stop >/dev/null 2>&1
            pkg_remove sing-box
        fi
    fi

    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123 >/dev/null 2>&1

pkg_list_update || { 
    msg "Не удалось обновить список пакетов"
    echo ""
    read -p "Нажмите Enter..." dummy
    return
}

    # Шаблон скачивания
        grep_url_pattern='https://[^"[:space:]]*\.ipk'


    download_success=0
    urls=$(wget -qO- "$REPO" 2>/dev/null | grep -o "$grep_url_pattern")
    for url in $urls; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"
        msg "Скачиваем" "$filename"
        if wget -q -O "$filepath" "$url" >/dev/null 2>&1 && [ -s "$filepath" ]; then
            download_success=1
        else
            msg "Ошибка скачивания" "$filename"
        fi
    done

[ $download_success -eq 0 ] && { 
    msg "Нет успешно скачанных пакетов"
    echo ""
    read -p "Нажмите Enter..." dummy
    return
}

    # Установка пакетов
    for pkg in podkop luci-app-podkop; do
        file=$(ls "$DOWNLOAD_DIR" | grep "^$pkg" | head -n 1)
        [ -n "$file" ] && pkg_install "$DOWNLOAD_DIR/$file"
    done

    # Русский интерфейс
    ru=$(ls "$DOWNLOAD_DIR" | grep "luci-i18n-podkop-ru" | head -n 1)
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop-ru; then
            msg "Обновляем русский язык..." "$ru"
            pkg_remove luci-i18n-podkop* >/dev/null 2>&1
            pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Установить русский интерфейс? y/N"
            read -r RUS
            case "$RUS" in
                y|Y) pkg_install "$DOWNLOAD_DIR/$ru" ;;
                *) ;;
            esac
        fi
    fi

    # Очистка
    rm -rf "$DOWNLOAD_DIR"

wget -qO /etc/config/podkop https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/podkop
echo -e "\nAWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}.${NC}"
	echo -e "${GREEN}Запуск ${NC}Podkop${GREEN}...${NC}"
    podkop enable >/dev/null 2>&1
    echo -e "${GREEN}Применяем конфигурацию...${NC}"
    podkop reload >/dev/null 2>&1
    echo -e "${GREEN}Перезапускаем сервис...${NC}"
    podkop restart >/dev/null 2>&1
    echo -e "${GREEN}Обновляем списки...${NC}"
    podkop list_update >/dev/null 2>&1
    echo -e "${GREEN}Перезапускаем сервис...${NC}"
    podkop restart >/dev/null 2>&1
    echo -e "\nPodkop ${GREEN}готов к работе.${NC}"
    read -p "Нажмите Enter..." dummy
}


# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
