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

VER_SUF="r1-all"; APK_RAS="ipk"; PKG_IS_APK=0; INSTALL_CMD="opkg install"
command -v apk >/dev/null 2>&1 && VER_SUF="r1" && APK_RAS="apk" && PKG_IS_APK=1 && INSTALL_CMD="apk add --allow-untrusted"

PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"

pkg_remove() { local pkg_name="$1"; if [ "$PKG_IS_APK" -eq 1 ]; then apk del "$pkg_name" >/dev/null 2>&1 || true; else opkg remove --force-depends "$pkg_name" >/dev/null 2>&1 || true; fi; }
pkg_is_installed () { local pkg_name="$1"; if [ "$PKG_IS_APK" -eq 1 ]; then apk list --installed | grep -q "$pkg_name"; else opkg list-installed | grep -q "$pkg_name"; fi; }

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
tmpDIR="/tmp/PodkopManager"
rm -rf "$tmpDIR"
mkdir -p "$tmpDIR"
echo -e "${CYAN}Обновляем список пакетов${NC}"
if [ "$PKG_IS_APK" -eq 1 ]; then
    apk update >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось обновить список пакетов${NC}\n"; PAUSE; exit 0; }
else
    opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось обновить список пакетов${NC}\n"; PAUSE; exit 0; }
fi

PODKOP_INST="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_LUCI="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-app-podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_RUS="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-i18n-podkop-ru-$PODKOP_LATEST_VER.$APK_RAS"

cd "$tmpDIR" || exit 1

echo -e "${CYAN}Скачиваем: ${YELLOW}$PODKOP_INST${NC}"
wget -q -U "Mozilla/5.0" -O podkop.$APK_RAS "$PODKOP_INST" || { echo -e "\n${RED}Не удалось скачать $PODKOP_INST${NC}\n"; PAUSE; exit 0; }
echo -e "${CYAN}Скачиваем: ${YELLOW}$PODKOP_LUCI${NC}"
wget -q -U "Mozilla/5.0" -O luci-app-podkop.$APK_RAS "$PODKOP_LUCI" || { echo -e "\n${RED}Не удалось скачать $PODKOP_LUCI${NC}\n"; PAUSE; exit 0; }
echo -e "${CYAN}Скачиваем: ${YELLOW}$PODKOP_RUS${NC}"
wget -q -U "Mozilla/5.0" -O luci-i18n-podkop-ru.$APK_RAS "$PODKOP_RUS" || { echo -e "\n${RED}Не удалось скачать $PODKOP_RUS${NC}\n"; PAUSE; exit 0; }

echo -e "\n${CYAN}Устанавливаем: ${NC}Podkop"
$INSTALL_CMD ./podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_INST\n"; PAUSE; exit 0; }
echo -e "\n${CYAN}Устанавливаем: ${NC}Podkop LuCI"
$INSTALL_CMD ./luci-app-podkop.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_LUCI\n"; PAUSE; exit 0; }
echo -e "\n${CYAN}Устанавливаем: ${NC}Руссификатор"
$INSTALL_CMD ./luci-i18n-podkop-ru.$APK_RAS >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить ${NC}$PODKOP_RUS\n"; PAUSE; exit 0; }

rm -rf "$tmpDIR"
echo -e "\n${GREEN}===== Установка завершена =====${NC}"
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
}

# ==========================================
# Интеграция AWG
# ==========================================
integration_AWG() {

echo -e "\n${MAGENTA}Интегрируем AWG в Podkop${NC}"

if ! awg --version >/dev/null 2>&1; then
echo -e "\n${RED}AWG не установлен!${NC}"
PAUSE
return
fi

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
podkop enable >/dev/null 2>&1
echo -e "${CYAN}Применяем конфигурацию${NC}"
podkop reload >/dev/null 2>&1
podkop restart >/dev/null 2>&1
echo -e "${CYAN}Обновляем списки${NC}"
podkop list_update >/dev/null 2>&1
echo -e "${CYAN}Перезапускаем сервис${NC}"
podkop restart >/dev/null 2>&1
echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}!${NC}\n"
echo -e "${YELLOW}Необходимо в LuCI в интерфейс AWG загрузить конфиг:${NC}\nNetwork ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit ${GREEN}→${NC} Load configuration…${NC}"
PAUSE
}

# ==========================================
# Удаление Podkop
# ==========================================
PODKOP_UNINSTALL() {
echo -e "\n${MAGENTA}Удаление Podkop${NC}"

pkg_remove luci-i18n-podkop-ru
pkg_remove luci-app-podkop podkop
pkg_remove podkop

rm -rf /etc/config/podkop >/dev/null 2>&1
rm -f /etc/config/*podkop* >/dev/null 2>&1

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

if pkg_is_installed https-dns-proxy; then
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

if pkg_is_installed podkop; then
echo -e "${CYAN}1) ${GREEN}Удалить ${NC}Podkop Evolution"; else
echo -e "${CYAN}1) ${GREEN}Установить ${NC}Podkop Evolution"; fi
if pkg_is_installed amneziawg-tools; then
echo -e "${CYAN}2) ${GREEN}Удалить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; else
echo -e "${CYAN}2) ${GREEN}Установить ${NC}AWG${GREEN} и ${NC}интерфейс AWG"; fi
echo -e "${CYAN}3) ${GREEN}Интегрировать подписку ${NC}VPN${GREEN} в ${NC}Podkop Evolution"

echo -e "${CYAN}4) ${GREEN}Интегрировать ${NC}AWG${GREEN} в ${NC}Podkop"

echo -e "${CYAN}5) ${GREEN}Интегрировать ${NC}/root/WARP.conf${GREEN} в ${NC}AWG"


echo -e "${CYAN}Enter) ${GREEN}Выход${NC}"
echo -ne "\n${YELLOW}Выберите пункт:${NC} "
read choicePOD

case "$choicePOD" in
1) 
if pkg_is_installed podkop; then
    PODKOP_UNINSTALL
else
    PODKOP_INSTALL
fi
;;


2)
if pkg_is_installed amneziawg-tools; then
    uninstall_AWG
else
    install_AWG
fi
;;


6) integration_AWG ;;

*) return ;;

esac; done
}
