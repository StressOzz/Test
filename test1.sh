#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"

tmpDIR="/tmp/PodkopManager"
rm -rf "$tmpDIR"
mkdir -p "$tmpDIR"

PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/itdoginfo/podkop/releases/latest | sed -E 's#.*/tag/v?##')"

BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"

if command -v apk; then
PKG_IS_APK=1
PKG_MANAGER="apk list -I 2>/dev/null"
else
PKG_IS_APK=0
PKG_MANAGER="opkg list-installed 2>/dev/null"
fi

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

pkg_remove() { local pkg_name="$1"; if [ "$PKG_IS_APK" -eq 1 ]; then apk del "$pkg_name" || true; else opkg remove --force-depends "$pkg_name" || true; fi; }

# ==========================================
# Определение версий
# ==========================================
get_versions() {


LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)

if command -v podkop; then
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
# Установка
# ==========================================
install_podkop() {
echo -e "\n${MAGENTA}Установка Podkop Evolution${NC}"

REPO="https://github.com/yandexru45/podkop-evolution/releases/latest"

PKG_IS_APK=0
command -v apk && PKG_IS_APK=1

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
echo -e "${CYAN}Удаляем ${NC}$pkg_name"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk del "$pkg_name"
else
opkg remove --force-depends "$pkg_name"
fi
}

pkg_list_update() {
echo -e "${CYAN}Обновляем список пакетов${NC}"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk update
else
opkg update
fi
}

pkg_install() {
local pkg_file="$1"
echo -e "${CYAN}Устанавливаем ${NC}$(basename "$pkg_file")"
if [ "$PKG_IS_APK" -eq 1 ]; then
apk add --allow-untrusted "$pkg_file"
else
opkg install "$pkg_file"
fi
}

MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "не определено")
AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
REQUIRED_SPACE=26000

[ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && {
echo -e "\n${RED}Недостаточно свободного места!${NC}"
PAUSE
return
}

nslookup google.com || {
echo -e "\n${RED}DNS не работает!${NC}"
PAUSE
return
}

if pkg_is_installed https-dns-proxy; then
echo -e "${RED}Обнаружен конфликтный пакет ${NC}https-dns-proxy${RED}. Удаляем...${NC}"
pkg_remove luci-app-https-dns-proxy
pkg_remove https-dns-proxy
pkg_remove luci-i18n-https-dns-proxy*
fi

if pkg_is_installed "^sing-box"; then
sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
required_version="1.12.4"
if [ "$(echo -e "$sing_box_version\n$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
echo -e "sing-box ${RED}устарел. Удаляем...${NC}"
service podkop stop
pkg_remove sing-box
fi
fi

/usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123

pkg_list_update || {
echo -e "\n${RED}Не удалось обновить список пакетов!${NC}"
PAUSE
return
}

# получаем реальный тег без API
LATEST_URL=$(curl -Ls -o /dev/null -w '%{url_effective}' "$REPO")
TAG=$(echo "$LATEST_URL" | sed 's#.*/tag/##')

if [ -z "$TAG" ]; then
echo -e "\n${RED}Не удалось определить версию релиза${NC}"
PAUSE
return
fi

DOWNLOAD_URL="https://github.com/yandexru45/podkop-evolution/releases/download/$TAG"

if [ "$PKG_IS_APK" -eq 1 ]; then
EXT="apk"
else
EXT="ipk"
fi

echo -e "${CYAN}Скачиваем пакеты версии ${NC}$TAG"

page=$(wget -qO- "$REPO" 2>/dev/null)

download_success=0
echo "$page" | grep -o "href=\"[^\" ]*\.$EXT\"" | sed 's/href="//;s/"//' | while read path; do
url="https://github.com$path"
filename=$(basename "$url")
filepath="$tmpDIR/$filename"

echo -e "${CYAN}Скачиваем ${NC}$filename"

if wget -q -O "$filepath" "$url" && [ -s "$filepath" ]; then
download_success=1
else
echo -e "${RED}Ошибка скачивания ${NC}$filename"
fi
done

for pkg in podkop luci-app-podkop; do
file=$(ls "$tmpDIR" | grep "^$pkg" | head -n 1)
[ -n "$file" ] && pkg_install "$tmpDIR/$file"
done

ru=$(ls "$tmpDIR" | grep "luci-i18n-podkop-ru" | head -n 1)
if [ -n "$ru" ]; then
if pkg_is_installed luci-i18n-podkop-ru; then
pkg_remove luci-i18n-podkop*
fi
pkg_install "$tmpDIR/$ru"
fi

echo -e "Podkop Evolution ${GREEN}установлен!${NC}"
PAUSE
}

# ==========================================
# Удаление Podkop
# ==========================================
uninstall_podkop() {
echo -e "\n${MAGENTA}Удаление Podkop${NC}"

pkg_remove luci-i18n-podkop-ru
pkg_remove luci-app-podkop podkop
pkg_remove podkop

rm -rf /etc/config/podkop /tmp/podkop_installer
rm -f /etc/config/*podkop*

echo -e "Podkop ${GREEN}удалён!${NC}"
PAUSE
}

# ==========================================
# uninstall_AWG
# ==========================================
uninstall_AWG() {
echo -e "\n${MAGENTA}Удаление AWG и интерфейс AWG${NC}"
echo -e "${CYAN}Удаляем ${NC}AWG"
pkg_remove luci-i18n-amneziawg-ru
pkg_remove luci-proto-amneziawg
pkg_remove amneziawg-tools
pkg_remove kmod-amneziawg

uci delete network.AWG
uci commit network

for peer in $(uci show network | grep "interface='AWG'" | cut -d. -f2); do
    uci delete network.$peer
done
uci commit network
echo -e "${CYAN}Удаляем ${NC}интерфейс AWG"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}удалены!${NC}"
PAUSE
}

# ==========================================
# AWG
# ==========================================
install_AWG() {

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

if wget -O "$tmpDIR/$filename" "$url"; then
echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
if ! $INSTALL_CMD "$tmpDIR/$filename"; then
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
opkg update || {
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

if uci show network.$IF_NAME; then
echo -e "${RED}Интерфейс уже существует!${NC}"
else
uci set network.$IF_NAME=interface
uci set network.$IF_NAME.proto=$PROTO
uci set network.$IF_NAME.device=$DEV_NAME
uci commit network
fi

echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart

echo -e "AWG ${GREEN}и${NC} интерфейс AWG ${GREEN}установлены!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE
}

# ==========================================
# Интеграция AWG
# ==========================================
integration_AWG() {

echo -e "\n${MAGENTA}Интегрируем AWG в Podkop${NC}"

if ! awg --version; then
echo -e "\n${RED}AWG не установлен!${NC}"
PAUSE
return
fi

echo -e "${CYAN}Меняем конфигурацию в ${NC}Podkop${NC}"
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
list community_lists 'russia_inside'
list community_lists 'hodca'
EOF

echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
podkop enable
echo -e "${CYAN}Применяем конфигурацию${NC}"
podkop reload
podkop restart
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update
echo -e "${CYAN}Перезапускаем сервис${NC}"
podkop restart
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE
}



# ==========================================
# Меню
# ==========================================
show_menu() {
get_versions

clear
echo -e "${MAGENTA}--- Podkop ---${NC}"
echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_STATUS"

echo -e "${MAGENTA}--- AWG ---${NC}"
if command -v amneziawg || eval "$PKG_MANAGER" | grep -q "amneziawg-tools"; then
echo -e "${YELLOW}AWG: ${GREEN}установлен${NC}"
else
echo -e "${YELLOW}AWG: ${RED}не установлен${NC}"
fi
if uci -q get network.AWG >/dev/null; then
    echo -e "${YELLOW}Интерфейс AWG: ${GREEN}установлен${NC}"
else
    echo -e "${YELLOW}Интерфейс AWG: ${RED}не установлен${NC}"
fi

echo -e "\n${CYAN}1) ${GREEN}Установить ${NC}Podkop"
echo -e "${CYAN}2) ${GREEN}Удалить ${NC}Podkop"
echo -e "${CYAN}7) ${GREEN}Установить ${NC}AWG ${GREEN}и${NC} интерфейс AWG"
echo -e "${CYAN}8) ${GREEN}Удалить ${NC}AWG ${GREEN}и${NC} интерфейс AWG"
echo -e "${CYAN}9) ${GREEN}Интегрировать ${NC}AWG ${GREEN}в ${NC}Podkop"
echo -e "${CYAN}0) ${GREEN}Перезагрузить устройство${NC}"
echo -e "${CYAN}Enter) ${GREEN}Выход${NC}"
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
read choice

case "$choice" in
1) install_podkop ;;
2) uninstall_podkop ;;
3) install_ByeDPI ;;
4) uninstall_byedpi ;;
5) integration_byedpi_podkop ;;
6) fix_strategy ;;
7) install_AWG ;;
8) uninstall_AWG ;;
9) integration_AWG ;;
0) echo -e "\n${GREEN}Перезагрузка!${NC}\n"; reboot; exit 0 ;;
*) exit 0 ;;
esac
}

# ==========================================
# Запуск
# ==========================================
while true; do
show_menu
done
