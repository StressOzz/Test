#!/bin/sh
GREEN="\033[32;1m"
NC="\033[0m"
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
    printf "${GREEN}Хотите установить русскую локализацию? (y/n) [n]: ${NC}"
    read INSTALL_RU_LANG
    INSTALL_RU_LANG=${INSTALL_RU_LANG:-n}
    if [ "$INSTALL_RU_LANG" = "y" ] || [ "$INSTALL_RU_LANG" = "Y" ]; then
        printf "${GREEN}===== Устанавливаем русскую локализацию =====${NC}\n"
        install_pkg "luci-i18n-amneziawg-ru" || printf "${GREEN}Внимание: русская локализация не установлена (не критично)${NC}\n"
    else
        printf "${GREEN}Пропускаем установку русской локализации.${NC}\n"
    fi
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

