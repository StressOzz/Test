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
SUFICS="v"
UPDATE="opkg update"
INSTALL="opkg install"
DELETE="opkg remove --autoremove --force-removal-of-dependent-packages"
ARCH="$(opkg print-architecture | awk '{print $2}' | tail -n1)"
VER_SUF="r1-all"
APK_RAS="ipk"
else 
PKG="apk"
CONFZ="/etc/apk/repositories.d/distfeeds.list"
PKG_IS_APK=1
SUFICS=""
UPDATE="apk update"
INSTALL="apk add --allow-untrusted"
DELETE="apk del"
ARCH="$(apk --print-arch 2>/dev/null)"
APK_RAS="apk"
VER_SUF="r1"
fi
IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
tmpDIR="/tmp/PodkopAWG"
pkg_is_installed () {
local pkg_name="$1"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk info -e "$pkg_name" >/dev/null 2>&1
else
opkg list-installed | grep -q "^$pkg_name"
fi
}
PODKOP_VER() {
PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"
    if command -v podkop >/dev/null 2>&1; then
        LOCALPOD=$(podkop show_version 2>/dev/null | cut -d'-' -f1)
        LOCALPOD=${LOCALPOD#v}
        [ -z "$LOCALPOD" ] && LOCALPOD="unknown"
    else
        LOCALPOD="not_installed"
    fi
    if [ "$LOCALPOD" = "not_installed" ]; then
        PODKOP_STATUS="${RED}не установлена${NC}"
    elif [ "$PODKOP_LATEST_VER" = "unknown" ]; then
        PODKOP_STATUS="${GREEN}$LOCALPOD${NC}"
    elif [ "$LOCALPOD" = "$PODKOP_LATEST_VER" ]; then
        PODKOP_STATUS="${GREEN}$LOCALPOD${NC}"
    else
        PODKOP_STATUS="${RED}$LOCALPOD${NC}"
    fi
}
# Установка Podkop
PODKOP_INSTALL() {
if ! pkg_is_installed podkop; then
rm -rf "$tmpDIR"
mkdir -p "$tmpDIR"
echo -e "\n${MAGENTA}Устанавливаем Podkop Evolution${NC}"
echo -e "${CYAN}Обновляем список пакетов${NC}"
$UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось обновить список пакетов${NC}\n"; PAUSE; return; }
PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"
PODKOP_INST="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_LUCI="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-app-podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_RUS="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-i18n-podkop-ru-$PODKOP_LATEST_VER.$APK_RAS"
cd "$tmpDIR" || exit 1
echo -e "${CYAN}Скачиваем ${NC}Podkop Evolution"
wget -q -U "Mozilla/5.0" -O podkop.$APK_RAS "$PODKOP_INST" || { echo -e "\n${RED}Не удалось скачать $PODKOP_INST${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O luci-app-podkop.$APK_RAS "$PODKOP_LUCI" || { echo -e "\n${RED}Не удалось скачать $PODKOP_LUCI${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O luci-i18n-podkop-ru.$APK_RAS "$PODKOP_RUS" || { echo -e "\n${RED}Не удалось скачать $PODKOP_RUS${NC}\n"; PAUSE; return; }
echo -en "${CYAN}Устанавливаем ${NC}Podkop Evolution\n${YELLOW}Подождите...${NC}"
$INSTALL ./podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_INST\n"; PAUSE; return; }
$INSTALL ./luci-app-podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_LUCI\n"; PAUSE; return; }
$INSTALL ./luci-i18n-podkop-ru.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_RUS\n"; PAUSE; return; }
rm -rf "$tmpDIR"
echo -e "\nPodkop Evolution ${GREEN}установлен!${NC}\n"
PAUSE
else
echo -e "\n${MAGENTA}Удаление Podkop${NC}"
$DELETE luci-i18n-podkop-ru >/dev/null 2>&1
$DELETE luci-app-podkop >/dev/null 2>&1
$DELETE podkop >/dev/null 2>&1
rm -rf /etc/config/podkop* /usr/bin/podkop >/dev/null 2>&1
echo -e "Podkop ${GREEN}удалён!${NC}\n"
PAUSE
fi
}
# Установка AWG
install_AWG() {
OWRT=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2)
ARCHAWG="$(grep DISTRIB_ARCH /etc/openwrt_release | cut -d"'" -f2)_$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | tr '/' '_')"
if ! pkg_is_installed amneziawg-tools; then
rm -rf "$tmpDIR"
mkdir -p "$tmpDIR"
echo -e "\n${MAGENTA}Устанавливаем AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Обновляем список пакетов${NC}"
$UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось обновить список пакетов${NC}\n"; PAUSE; return; }
AWG_kmod=https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v$OWRT/kmod-amneziawg_v${OWRT}_$ARCHAWG.$APK_RAS
AWG_tools=https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v$OWRT/amneziawg-tools_v${OWRT}_$ARCHAWG.$APK_RAS
AWG_luci=https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v$OWRT/luci-proto-amneziawg_v${OWRT}_$ARCHAWG.$APK_RAS
AWG_ru=https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v$OWRT/luci-i18n-amneziawg-ru_v${OWRT}_$ARCHAWG.$APK_RAS
cd "$tmpDIR" || exit 1
echo -e "${CYAN}Скачиваем ${NC}AWG"
wget -q -U "Mozilla/5.0" -O AWG_kmod.$APK_RAS "$AWG_kmod" || { echo -e "\n${RED}Не удалось скачать $AWG_kmod${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O AWG_tools.$APK_RAS "$AWG_tools" || { echo -e "\n${RED}Не удалось скачать $AWG_tools${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O AWG_luci.$APK_RAS "$AWG_luci" || { echo -e "\n${RED}Не удалось скачать $AWG_luci${NC}\n"; PAUSE; return; }
wget -q -U "Mozilla/5.0" -O AWG_ru.$APK_RAS "$AWG_ru" || { echo -e "\n${RED}Не удалось скачать $AWG_ru${NC}\n"; PAUSE; return; }
echo -e "${CYAN}Устанавливаем ${NC}AWG"
$INSTALL ./AWG_kmod.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$AWG_kmod\n"; PAUSE; return; }
$INSTALL ./AWG_tools.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$AWG_tools\n"; PAUSE; return; }
$INSTALL ./AWG_luci.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$AWG_luci\n"; PAUSE; return; }
$INSTALL ./AWG_ru.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$AWG_ru\n"; PAUSE; return; }
echo -e "${CYAN}Создаем ${NC}интерфейс AWG"
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
echo -e "${YELLOW}Необходимо в ${NC}LuCI${YELLOW} в интерфейс ${NC}AWG${YELLOW} загрузить файл ${NC}*.conf${YELLOW}:${NC}"
echo -e "${NC}Network ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration… ${GREEN}→${NC} Save ${GREEN}→${NC} Save & Apply\n"
PAUSE
rm -rf "$tmpDIR"
else
echo -e "\n${MAGENTA}Удаление AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Удаляем ${NC}AWG"
$DELETE luci-i18n-amneziawg-ru >/dev/null 2>&1
$DELETE luci-proto-amneziawg >/dev/null 2>&1
$DELETE amneziawg-tools >/dev/null 2>&1
$DELETE kmod-amneziawg >/dev/null 2>&1
uci delete network.AWG >/dev/null 2>&1
uci commit network >/dev/null 2>&1
for peer in $(uci show network | grep "interface='AWG'" | cut -d. -f2); do
uci delete network.$peer
done
uci commit network >/dev/null 2>&1
echo -e "${CYAN}Удаляем ${NC}интерфейс AWG"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart
echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}удалены!${NC}\n"
PAUSE
fi
}
# Интеграция AWG
integration_AWG() {
if ! pkg_is_installed podkop; then echo -e "\n${RED}Podkop Evolution не установлен!${NC}\n"; PAUSE; return; fi
if ! awg --version >/dev/null 2>&1; then
echo -e "\n${RED}AWG не установлен!${NC}"
PAUSE
return
fi
echo -e "\n${MAGENTA}Интегрируем AWG в Podkop${NC}"
echo -e "${CYAN}Меняем конфигурацию в ${NC}Podkop${NC}"

printf "%s\n" "config settings 'settings'" "option dns_type 'udp'" "option dns_server '8.8.8.8'" "option bootstrap_dns_server '77.88.8.8'" "option dns_rewrite_ttl '60'" "list source_network_interfaces 'br-lan'" "option enable_output_network_interface '0'" "option enable_badwan_interface_monitoring '0'" "option enable_yacd '0'" "option disable_quic '0'" "option update_interval '1d'" "option download_lists_via_proxy '0'" "option dont_touch_dhcp '0'" "option config_path '/etc/sing-box/config.json'" "option cache_path '/tmp/sing-box/cache.db'" "option log_level 'warn'" "option exclude_ntp '0'" "option shutdown_correctly '0'" "" "config section 'StressAWG'" "option connection_type 'vpn'" "option interface 'AWG'" "option domain_resolver_enabled '0'" "list community_lists 'geoblock'" "list community_lists 'block'" "list community_lists 'porn'" "list community_lists 'news'" "list community_lists 'anime'" "list community_lists 'youtube'" "list community_lists 'discord'" "list community_lists 'meta'" "list community_lists 'twitter'" "list community_lists 'hdrezka'" "list community_lists 'tiktok'" "list community_lists 'telegram'" "list community_lists 'cloudflare'" "list community_lists 'google_ai'" "list community_lists 'google_play'" "list community_lists 'hodca'" "list community_lists 'roblox'" "list community_lists 'hetzner'" "list community_lists 'ovh'" "list community_lists 'digitalocean'" "list community_lists 'cloudfront'" "option user_domain_list_type 'disabled'" "option user_subnet_list_type 'disabled'" "option mixed_proxy_enabled '0'" > /etc/config/podkop

echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
podkop enable >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}\n${YELLOW}Подождите...${NC}"
podkop restart >/dev/null 2>&1
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}!${NC}\n"
echo -e "${YELLOW}Необходимо в ${NC}LuCI${YELLOW} в интерфейс ${NC}AWG${YELLOW} загрузить файл ${NC}*.conf${YELLOW}:${NC}"
echo -e "${NC}Network ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration… ${GREEN}→${NC} Save ${GREEN}→${NC} Save & Apply\n"
PAUSE
}

# Интеграция VPN

PODKOP_VPN() {
if ! pkg_is_installed podkop; then echo -e "\n${RED}Podkop Evolution не установлен!${NC}\n"; PAUSE; return; fi
echo -e "\n${MAGENTA}Интегрируем VPN подписку в Podkop Evolution${NC}"
echo -ne "\n${YELLOW}Введите ссылку на подписку (${NC}https://...${YELLOW}): ${NC}"
read -r SUB_URL
SUB_URL="$(echo "$SUB_URL" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
echo "$SUB_URL" | grep -qE '^https?://' || { echo -e "\n${RED}Ошибка ссылки! Только ${NC}http://${RED} или ${NC}https://${RED} ссылки${NC}\n"; PAUSE; return; }
echo -e "\n${CYAN}Меняем конфигурацию в ${NC}Podkop Evolution${NC}"

printf "%s\n" "config settings 'settings'" "option dns_type 'udp'" "option dns_server '8.8.8.8'" "option bootstrap_dns_server '77.88.8.8'" "option dns_rewrite_ttl '60'" "list source_network_interfaces 'br-lan'" "option enable_output_network_interface '0'" "option enable_badwan_interface_monitoring '0'" "option enable_yacd '0'" "option disable_quic '0'" "option update_interval '1d'" "option download_lists_via_proxy '0'" "option dont_touch_dhcp '0'" "option config_path '/etc/sing-box/config.json'" "option cache_path '/tmp/sing-box/cache.db'" "option log_level 'panic'" "option exclude_ntp '0'" "option shutdown_correctly '0'" > /etc/config/podkop
printf "%s\n" "" "config section 'StressKVN'" "option connection_type 'proxy'" "option proxy_config_type 'subscription'" "option enable_udp_over_tcp '0'" "option subscription_url '$SUB_URL'" "option subscription_update_interval '1h'" "option subscription_group_by_countries '0'" "option urltest_check_interval '5m'" "option urltest_tolerance '150'" "option urltest_testing_url 'https://www.gstatic.com/generate_204'" "list community_lists 'geoblock'" "list community_lists 'block'" "list community_lists 'porn'" "list community_lists 'news'" "list community_lists 'anime'" "list community_lists 'youtube'" "list community_lists 'discord'" "list community_lists 'meta'" "list community_lists 'twitter'" "list community_lists 'hdrezka'" "list community_lists 'tiktok'" "list community_lists 'telegram'" "list community_lists 'cloudflare'" "list community_lists 'google_ai'" "list community_lists 'google_play'" "list community_lists 'hodca'" "list community_lists 'roblox'" "list community_lists 'hetzner'" "list community_lists 'ovh'" "list community_lists 'digitalocean'" "list community_lists 'cloudfront'" "option user_domain_list_type 'disabled'" "option user_subnet_list_type 'disabled'" "option mixed_proxy_enabled '0'" >> /etc/config/podkop

echo -e "${CYAN}Запускаем ${NC}Podkop Evolution${NC}"
podkop enable >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}\n${YELLOW}Подождите...${NC}"
podkop restart >/dev/null 2>&1
echo -e "VPN подписка ${GREEN}интегрирована в ${NC}Podkop Evolution${GREEN}!${NC}\n"
PAUSE
}
# МЕНЮ
PODKOP_menu() { while true; do
openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)
if [ "$openwrt_version" = "23" ]; then
echo -e "\n${RED}OpenWrt версии ниже 24 не поддерживаются!${NC}\n"
PAUSE; return
fi
AVAILABLE_SPACE=$(df /overlay 2>/dev/null | awk 'NR==2 {print $4}')
[ -z "$AVAILABLE_SPACE" ] && AVAILABLE_SPACE=$(df / 2>/dev/null | awk 'NR==2 {print $4}')
REQUIRED_SPACE=16000
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
echo -e "\n${RED}Недостаточно свободного места${NC}\n"
echo -e "${YELLOW}Доступно: ${NC}$((AVAILABLE_SPACE/1024))MB"
echo -e "${YELLOW}Требуется: ${NC}$((REQUIRED_SPACE/1024))MB\n"
PAUSE; return
fi

if pkg_is_installed https-dns-proxy; then
echo -e "\n${RED}Обнаружен ${NC}DNS over HTTPS${RED}!"
echo -e "${YELLOW}Удалите ${NC}DNS over HTTPS\n"
PAUSE; return      
fi
PODKOP_VER
clear
echo -e "${MAGENTA}Меню Podkop Evolution${NC}\n"
echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_STATUS"
if pkg_is_installed amneziawg-tools || command -v amneziawg >/dev/null 2>&1; then
echo -e "${YELLOW}AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}AWG: ${RED}не установлен${NC}"
fi
if uci -q get network.AWG >/dev/null; then
echo -e "${YELLOW}Интерфейс AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}Интерфейс AWG: ${RED}не установлен${NC}"
fi
if pkg_is_installed podkop; then
echo -e "\n${CYAN}1) ${GREEN}Удалить ${NC}Podkop Evolution"; else
echo -e "\n${CYAN}1) ${GREEN}Установить ${NC}Podkop Evolution"; fi
if pkg_is_installed amneziawg-tools; then
echo -e "${CYAN}2) ${GREEN}Удалить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; else
echo -e "${CYAN}2) ${GREEN}Установить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; fi
if [ -f /etc/config/podkop ] && grep -q "^[[:space:]]*option subscription_url" /etc/config/podkop; then
echo -e "${CYAN}3) ${GREEN}Сменить ${NC}VPN${GREEN} подписку${NC}"
else
echo -e "${CYAN}3) ${GREEN}Интегрировать ${NC}VPN подписку${GREEN} в ${NC}Podkop Evolution"
fi
echo -e "${CYAN}4) ${GREEN}Интегрировать ${NC}AWG${GREEN} в ${NC}Podkop"
echo -e "${CYAN}Enter) ${GREEN}Выход в главное меню${NC}"
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
read choicePOD
case "$choicePOD" in
1) PODKOP_INSTALL ;;
2) install_AWG ;;
3) PODKOP_VPN ;;
4) integration_AWG ;;
*) return ;;
esac; done
}
PODKOP_menu
