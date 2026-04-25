#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"

PODKOP_LATEST_VER="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/yandexru45/podkop-evolution/releases/latest | sed 's#.*/tag/##')"

VER_SUF="r1-all"; APK_RAS="ipk"; PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && VER_SUF="r1" && APK_RAS="apk" && PKG_IS_APK=1

echo -e "${CYAN}Обновляем список пакетов${NC}"
if [ "$PKG_IS_APK" -eq 1 ]; then
    apk update
else
    opkg update
fi

PODKOP_INST="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_LUCI="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-app-podkop-$PODKOP_LATEST_VER-$VER_SUF.$APK_RAS"
PODKOP_RUS="https://github.com/yandexru45/podkop-evolution/releases/download/$PODKOP_LATEST_VER/luci-i18n-podkop-ru-$PODKOP_LATEST_VER.$APK_RAS"

echo -e "\n${CYAN}Скачиваем пакеты:${NC}"
echo "$PODKOP_INST"
echo "$PODKOP_LUCI"
echo "$PODKOP_RUS"

cd /tmp || exit 1

wget -O podkop.$APK_RAS "$PODKOP_INST"
wget -O luci-app-podkop.$APK_RAS "$PODKOP_LUCI"
wget -O luci-i18n-podkop-ru.$APK_RAS "$PODKOP_RUS"

echo -e "\n${CYAN}Устанавливаем:${NC}"

if [ "$PKG_IS_APK" -eq 1 ]; then
    apk add --allow-untrusted ./podkop.$APK_RAS
    apk add --allow-untrusted ./luci-app-podkop.$APK_RAS
    apk add --allow-untrusted ./luci-i18n-podkop-ru.$APK_RAS
else
    opkg install ./podkop.$APK_RAS
    opkg install ./luci-app-podkop.$APK_RAS
    opkg install ./luci-i18n-podkop-ru.$APK_RAS
fi

echo -e "\n${GREEN}===== Установка завершена =====${NC}"
