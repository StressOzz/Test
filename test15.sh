#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"
PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }
###########################################################################################################################################
if command -v opkg >/dev/null 2>&1; then 
PKG="opkg"
CONFZ="/etc/opkg/distfeeds.conf"
PKG_IS_APK=0
UPDATE="opkg update"
INSTALL="opkg install"
CHECK_AVAIL="opkg list | cut -d ' ' -f1"
DELETE="opkg remove --autoremove --force-removal-of-dependent-packages"
CHECK_CMD="opkg list-installed"; 
ARCH="$(opkg print-architecture | awk '{print $2}' | tail -n1)"
VER_SUF="r1-all"; APK_RAS="ipk"; INSTALL="opkg install"
else
PKG="apk"; CONFZ="/etc/apk/repositories.d/distfeeds.list"
PKG_IS_APK=1
UPDATE="apk update"
INSTALL="apk add --allow-untrusted"
CHECK_AVAIL="apk search -e"
DELETE="apk del"
CHECK_CMD="apk info"
ARCH="$(apk --print-arch 2>/dev/null)"
fi


PODKOP_VER() {
PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"
if command -v podkop >/dev/null 2>&1; then
PODKOP_VER=$(podkop show_version 2>/dev/null | sed 's/-r[0-9]\+$//')
[ -z "$PODKOP_VER" ] && PODKOP_VER="не найдена"
else
PODKOP_VER="не установлен"
fi
[ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"
PODKOP_VER=$(echo "$PODKOP_VER" | sed 's/^v//')
PODKOP_LATEST_VER=$(echo "$PODKOP_LATEST_VER" | sed 's/^v//')
if [ "$PODKOP_VER" = "не найдена" ] || [ "$PODKOP_VER" = "не установлен" ]; then
PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
elif [ "$PODKOP_LATEST_VER" != "не найдена" ] && [ "$PODKOP_VER" != "$PODKOP_LATEST_VER" ]; then
PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
else
PODKOP_STATUS="${GREEN}$PODKOP_VER${NC}"
fi
}

# ==========================================
# Установка Podkop
# ==========================================
PODKOP_INSTALL() {
if ! $CHECK_CMD podkop; then

echo -e "\n${MAGENTA}Устанавливаем Podkop Evolution${NC}"

tmpDIR="/tmp/PodkopEvolution"
rm -rf "$tmpDIR"
mkdir -p "$tmpDIR"
echo -e "${CYAN}Обновляем список пакетов${NC}"
$UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось обновить список пакетов${NC}\n"; PAUSE; return; }


PODKOP_INST="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_LUCI="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-app-podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_RUS="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-i18n-podkop-ru-$PODKOP_LATEST_VER.$APK_RAS"

cd "$tmpDIR" || exit 1

echo -e "${CYAN}Скачиваем ${NC}Podkop Evolution"
wget -q -U "Mozilla/5.0" -O podkop.$APK_RAS "$PODKOP_INST" || { echo -e "\n${RED}Не удалось скачать $PODKOP_INST${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O luci-app-podkop.$APK_RAS "$PODKOP_LUCI" || { echo -e "\n${RED}Не удалось скачать $PODKOP_LUCI${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O luci-i18n-podkop-ru.$APK_RAS "$PODKOP_RUS" || { echo -e "\n${RED}Не удалось скачать $PODKOP_RUS${NC}\n"; PAUSE; return; }

echo -e "${CYAN}Устанавливаем ${NC}Podkop Evolution"
$INSTALL_CMD ./podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_INST\n"; PAUSE; return; }
$INSTALL_CMD ./luci-app-podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_LUCI\n"; PAUSE; return; }
$INSTALL_CMD ./luci-i18n-podkop-ru.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_RUS\n"; PAUSE; return; }

rm -rf "$tmpDIR"
echo -e "Podkop Evolution ${GREEN}установлен!${NC}\n"
PAUSE

else
    echo -e "\n${MAGENTA}Удаление Podkop${NC}"

$DELETE luci-i18n-podkop-ru
$DELETE luci-app-podkop podkop
$DELETE podkop

rm -rf /etc/config/podkop >/dev/null 2>&1
rm -f /etc/config/*podkop* >/dev/null 2>&1

echo -e "Podkop ${GREEN}удалён!${NC}"
PAUSE
fi

}

# ==========================================
# AWG
# ==========================================
install_AWG() {

if ! $CHECK_CMD amneziawg-tools; then

echo -e "\n${MAGENTA}Устанавливаем AWG и интерфейс AWG${NC}"

VERSION=$(ubus call system board | jsonfilter -e '@.release.version' | tr -d '\n')
MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f1)

if [ -z "$VERSION" ]; then
echo -e "\n${RED}Не удалось определить версию OpenWrt!${NC}"
PAUSE
return
fi

TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)

install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"

echo -e "${CYAN}Скачиваем:${NC} $filename"

if wget -O "$tmpDIR/$filename" "$url" >/dev/null 2>&1; then
echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
if ! $INSTALL_CMD "$tmpDIR/$filename" >/dev/null 2>&1; then
echo -e "\n${RED}Ошибка установки $pkgname!${NC}"
PAUSE
return 1
fi
else
echo -e "\n${RED}Ошибка! Не удалось скачать $filename${NC}"
PAUSE
return 1
fi
}

if [ "$MAJOR_VERSION" -ge 25 ] 2>/dev/null; then
PKGARCH=$(cat /etc/apk/arch)
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.apk"
INSTALL_CMD="apk add --allow-untrusted"
else
echo -e "${CYAN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}"
PAUSE
return
}
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
INSTALL_CMD="opkg install"
fi

install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
install_pkg "luci-i18n-amneziawg-ru"

echo -e "${CYAN}Создаем интерфейс AWG${NC}"

if uci show network.$IF_NAME >/dev/null 2>&1; then
echo -e "${RED}Интерфейс уже существует!${NC}"
else
uci set network.$IF_NAME=interface
uci set network.$IF_NAME.proto=$PROTO
uci set network.$IF_NAME.device=$DEV_NAME
uci commit network
fi

echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart >/dev/null 2>&1

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}установлены!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE

else
echo -e "\n${MAGENTA}Удаление AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Удаляем ${NC}AWG"
$DELETE luci-i18n-amneziawg-ru
$DELETE luci-proto-amneziawg
$DELETE amneziawg-tools
$DELETE kmod-amneziawg
uci delete network.AWG >/dev/null 2>&1
uci commit network >/dev/null 2>&1
for peer in $(uci show network | grep "interface='AWG'" | cut -d. -f2); do
uci delete network.$peer
done
uci commit network >/dev/null 2>&1
echo -e "${CYAN}Удаляем ${NC}интерфейс AWG"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart
echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}удалены!${NC}"
PAUSE
fi

}

# ==========================================
# Интеграция AWG
# ==========================================
integration_AWG() {

if ! $CHECK_CMD podkop; then echo -e "\n${RED}Podkop Evolution не установлен!${NC}\n"; PAUSE; return; fi

if ! awg --version >/dev/null 2>&1; then
echo -e "\n${RED}AWG не установлен!${NC}"
PAUSE
return
fi

echo -e "\n${MAGENTA}Интегрируем AWG в Podkop${NC}"

echo -e "${CYAN}Меняем конфигурацию в ${NC}Podkop${NC}"
cat <<'EOF' >/etc/config/podkop
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
list community_lists 'russia_inside'
list community_lists 'hodca'
EOF

echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
/etc/init.d/podkop enable >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
/etc/init.d/podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}"
/etc/init.d/podkop restart >/dev/null 2>&1
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE
}

# ==========================================
# Интеграция VPN
# ==========================================
PODKOP_VPN() {

if ! $CHECK_CMD podkop; then echo -e "\n${RED}Podkop Evolution не установлен!${NC}\n"; PAUSE; return; fi


echo -e "\n${MAGENTA}Интегрируем VPN подписку в Podkop Evolution${NC}"
echo -ne "${YELLOW}Введите ссылку на подписку (${CYAN}https://...${YELLOW}): ${NC}"
read -r SUB_URL
[ -z "$SUB_URL" ] && echo -e "\n${RED}Ошибка! Ссылка пустая!${NC}\n" && PAUSE && return

echo -e "${CYAN}Меняем конфигурацию в ${NC}Podkop Evolution${NC}"

cat > /etc/config/podkop <<EOF
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
	option log_level 'panic'
	option exclude_ntp '0'
	option shutdown_correctly '0'

config section 'main'
	option connection_type 'proxy'
	option proxy_config_type 'subscription'
	option enable_udp_over_tcp '0'
	option subscription_url '$SUB_URL'
	option subscription_update_interval '1h'
	option subscription_group_by_countries '0'
	option urltest_check_interval '5m'
	option urltest_tolerance '150'
	option urltest_testing_url 'https://www.gstatic.com/generate_204'
	list community_lists 'geoblock'
	list community_lists 'block'
	list community_lists 'porn'
	list community_lists 'news'
	list community_lists 'anime'
	list community_lists 'youtube'
	list community_lists 'discord'
	list community_lists 'meta'
	list community_lists 'twitter'
	list community_lists 'hdrezka'
	list community_lists 'tiktok'
	list community_lists 'telegram'
	list community_lists 'cloudflare'
	list community_lists 'google_ai'
	list community_lists 'google_play'
	list community_lists 'hodca'
	list community_lists 'roblox'
	list community_lists 'hetzner'
	list community_lists 'ovh'
	list community_lists 'digitalocean'
	list community_lists 'cloudfront'
	option user_domain_list_type 'disabled'
	option user_subnet_list_type 'disabled'
	option mixed_proxy_enabled '0'
EOF

echo -e "${CYAN}Запускаем ${NC}Podkop Evolution${NC}"
/etc/init.d/podkop enable >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
/etc/init.d/podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}"
/etc/init.d/podkop restart >/dev/null 2>&1
echo -e "VPN подписка ${GREEN}интегрирована в ${NC}Podkop Evolution${GREEN}!${NC}\n"
PAUSE
}

# ==========================================
# МЕНЮ
# ==========================================
PODKOP_menu() { while true; do
openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)
    if [ "$openwrt_version" = "23" ]; then
echo -e "\n${RED}OpenWrt ниже 24 - не поддерживается!${NC}\n"
PAUSE; return
    fi

AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
REQUIRED_SPACE=15360
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
echo -e "\n${RED}Недостаточно свободного места${NC}\n"
echo -e "${YELLOW}Доступно: ${NC}$((AVAILABLE_SPACE/1024))MB"
echo -e "${YELLOW}Требуется: ${NC}$((REQUIRED_SPACE/1024))MB\n"
PAUSE; return
    fi

if $CHECK_CMD https-dns-proxy; then
        echo -e "\n${RED}Обнаружен ${NC}DNS over HTTPS${RED}!"
        echo -e "${YELLOW}Удалите ${NC}DNS over HTTPS\n"
PAUSE; return      
    fi
    
PODKOP_VER

clear

echo -e "${MAGENTA}Меню Podkop Evolution${NC}\n"

echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_STATUS"

if command -v amneziawg >/dev/null 2>&1 || eval "$PKG_MANAGER" | grep -q "amneziawg-tools"; then
echo -e "${YELLOW}AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}AWG: ${RED}не установлен${NC}"
fi
if uci -q get network.AWG >/dev/null; then
    echo -e "${YELLOW}Интерфейс AWG: ${GREEN}установлен${NC}"
else
    echo -e "${YELLOW}Интерфейс AWG: ${RED}не установлен${NC}"
fi


echo

if $CHECK_CMD podkop; then
echo -e "${CYAN}1) ${GREEN}Удалить ${NC}Podkop Evolution"; else
echo -e "${CYAN}1) ${GREEN}Установить ${NC}Podkop Evolution"; fi
if $CHECK_CMD amneziawg-tools; then
echo -e "${CYAN}2) ${GREEN}Удалить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; else
echo -e "${CYAN}2) ${GREEN}Установить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; fi

if [ -f /etc/config/podkop ] && grep -q "^[[:space:]]*option subscription_url" /etc/config/podkop; then
  echo -e "${CYAN}3) ${GREEN}Сменить ${NC}VPN${GREEN} подписку${NC}"
else
    echo -e "${CYAN}3) ${GREEN}Интегрировать ${NC}VPN подписку${GREEN} в ${NC}Podkop Evolution"
fi

echo -e "${CYAN}4) ${GREEN}Интегрировать ${NC}AWG${GREEN} в ${NC}Podkop"

# echo -e "${CYAN}5) ${GREEN}Интегрировать ${NC}/root/WARP.conf${GREEN} в ${NC}AWG"


echo -e "${CYAN}Enter) ${GREEN}Выход${NC}"
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
read choicePOD

case "$choicePOD" in
1)  PODKOP_INSTALL ;;

2) install_AWG ;;

3) PODKOP_VPN ;;

4) integration_AWG ;;

*) return ;;

esac; done
}
PODKOP_menu
