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

PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }
PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"

VER_SUF="r1-all"; APK_RAS="ipk"; PKG_IS_APK=0; INSTALL_CMD="opkg install"
command -v apk >/dev/null 2>&1 && VER_SUF="r1" && APK_RAS="apk" && PKG_IS_APK=1 && INSTALL_CMD="apk add --allow-untrusted"

pkg_is_installed () {
    local pkg_name="$1"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk list --installed | grep -q "$pkg_name"
    else
        opkg list-installed | grep -q "$pkg_name"
    fi
}

openwrt_version=$(cat /etc/openwrt_release | grep DISTRIB_RELEASE | cut -d"'" -f2 | cut -d'.' -f1)

    if [ "$openwrt_version" = "23" ]; then
echo -e "\n${RED}OpenWrt ниже 24 - не поддерживается!${NC}\n"
PAUSE; exit 0
    fi

AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
REQUIRED_SPACE=15360
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
echo -e "\n${RED}Недостаточно свободного места${NC}\n"
echo -e "${YELLOW}Доступно: ${NC}$((AVAILABLE_SPACE/1024))MB"
echo -e "${YELLOW}Требуется: ${NC}$((REQUIRED_SPACE/1024))MB\n"
PAUSE; exit 0
    fi

if pkg_is_installed https-dns-proxy; then
        echo -e "\n${RED}Обнаружен ${NC}DNS over HTTPS${RED}!"
        echo -e "${YELLOW}Удалите ${NC}DNS over HTTPS\n"
PAUSE; exit 0        
    fi

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

echo -e "\n${GREEN}===== Установка завершена =====${NC}"
