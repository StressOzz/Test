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
DGRAY="\033[38;5;244m"

# ==========================================
# Устанавливаем AWG + интерфейс
# ==========================================
echo -e "\n${MAGENTA}Устанавка AWG + интерфейс${NC}"
echo -e "${GREEN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/FreeRKN/awg-openwrt/releases/download/"
AWG_DIR="/tmp/amneziawg"
mkdir -p "$AWG_DIR"
install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"
    if wget -O "$AWG_DIR/$filename" "$url" >/dev/null 2>&1 ; then
        echo -e "${CYAN}Устанавливаем ${NC}$pkgname"
        if ! opkg install "$AWG_DIR/$filename" >/dev/null 2>&1 ; then
            echo -e "\n${RED}Ошибка установки $pkgname!${NC}\n"
            read -p "Нажмите Enter..." dummy; return
        fi
    else
        echo -e "\n${RED}Ошибка! Не удалось скачать $filename${NC}\n"
        read -p "Нажмите Enter..." dummy; return
    fi
}
install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
install_pkg "luci-i18n-amneziawg-ru" >/dev/null 2>&1 || echo -e "${RED}Внимание: русская локализация не установлена (не критично)${NC}"
rm -rf "$AWG_DIR"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart >/dev/null 2>&1
sleep 5
echo -e "AmneziaWG ${GREEN}установлен!${NC}"

echo -e "${MAGENTA}Устанавливаем интерфейс AWG${NC}"
IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
if grep -q "config interface '$IF_NAME'" /etc/config/network; then
echo -e "${RED}Интерфейс ${NC}$IF_NAME${RED} уже существует${NC}"
else
echo -e "${CYAN}Добавляем интерфейс ${NC}$IF_NAME"
uci batch <<EOF
set network.$IF_NAME=interface
set network.$IF_NAME.proto=$PROTO
set network.$IF_NAME.device=$DEV_NAME
commit network
EOF
fi
echo -e "${CYAN}Перезапускаем сеть${NC}"

/etc/init.d/network restart
sleep 5
# /etc/init.d/firewall restart
# /etc/init.d/uhttpd restart

echo -e "${GREEN}Интерфейс ${NC}$IF_NAME${GREEN} создан и активирован!${NC}"
echo -e "${YELLOW}Вставьте рабочий конфиг в Interfaces (Интерфейс) AWG!${NC}\n"
read -p "Нажмите Enter..." dummy


# ==========================================
# Установка Podkop
# ==========================================


echo -e "\n${MAGENTA}Установка Podkop${NC}"

    REPO="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    DOWNLOAD_DIR="/tmp/podkop"

    PKG_IS_APK=0
    command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

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
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk list --installed | grep -q "$pkg_name"
        else
            opkg list-installed | grep -q "$pkg_name"
        fi
    }

    pkg_remove() {
        local pkg_name="$1"
        msg "Удаляем" "$pkg_name..."
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk del "$pkg_name" >/dev/null 2>&1
        else
            opkg remove --force-depends "$pkg_name" >/dev/null 2>&1
        fi
    }

    pkg_list_update() {
        msg "Обновляем список пакетов..."
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk update >/dev/null 2>&1
        else
            opkg update >/dev/null 2>&1
        fi
    }

    pkg_install() {
        local pkg_file="$1"
        msg "Устанавливаем" "$(basename "$pkg_file")"
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk add --allow-untrusted "$pkg_file" >/dev/null 2>&1
        else
            opkg install "$pkg_file" >/dev/null 2>&1
        fi
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

nslookup google.com >/dev/null 2>&1 || { 
    msg "DNS не работает"
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
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

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
			pkg_install "$DOWNLOAD_DIR/$ru"

        fi
    fi

    # Очистка
    rm -rf "$DOWNLOAD_DIR"

    echo -e "Podkop ${GREEN}успешно установлен!${NC}\n"
    read -p "Нажмите Enter..." dummy

# ==========================================
# Интеграция AWG
# ==========================================
echo -e "\n${MAGENTA}Интегрируем AWG в Podkop${NC}"

echo -e "${GREEN}Меняем конфигурацию в ${NC}Podkop${GREEN}...${NC}"
    # Создаём / меняем /etc/config/podkop
    cat <<EOF >/etc/config/podkop
config settings 'settings'
	option dns_type 'udp'
	option dns_server '8.8.8.8'
	option bootstrap_dns_server '77.88.8.8'
	option dns_rewrite_ttl '60'
	list source_network_interfaces 'br-lan'
	option enable_output_network_interface '0'
	option enable_badwan_interface_monitoring '0'
	option enable_yacd '0'
	option disable_quic '0'
	option update_interval '1d'
	option download_lists_via_proxy '0'
	option dont_touch_dhcp '0'
	option config_path '/etc/sing-box/config.json'
	option cache_path '/tmp/sing-box/cache.db'
	option exclude_ntp '0'
	option shutdown_correctly '0'

config section 'main'
	option connection_type 'vpn'
	option interface 'AWG'
	option domain_resolver_enabled '0'
	option user_domain_list_type 'disabled'
	option user_subnet_list_type 'disabled'
	option mixed_proxy_enabled '0'
	list community_lists 'telegram'
EOF

echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}.${NC}"
echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
podkop enable >/dev/null 2>&1
echo -e "${CYAN}Применяем конфигурацию${NC}"
podkop reload >/dev/null 2>&1
podkop restart >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}"
podkop restart >/dev/null 2>&1
echo -e "Podkop ${GREEN}готов к работе!${NC}\n"
read -p "Нажмите Enter..." dummy
