#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"
NC="\033[0m"
clear

##################################################################################################################

echo -e "${MAGENTA}Устанавливаем AWG + интерфейс${NC}"
 PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')

    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
    PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

    # Определяем версию AWG протокола (2.0 для OpenWRT >= 23.05.6 и >= 24.10.3)
    AWG_VERSION="1.0"
    MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f 1)
    MINOR_VERSION=$(echo "$VERSION" | cut -d '.' -f 2)
    PATCH_VERSION=$(echo "$VERSION" | cut -d '.' -f 3)
    
    if [ "$MAJOR_VERSION" -gt 24 ] || \
       [ "$MAJOR_VERSION" -eq 24 -a "$MINOR_VERSION" -gt 10 ] || \
       [ "$MAJOR_VERSION" -eq 24 -a "$MINOR_VERSION" -eq 10 -a "$PATCH_VERSION" -ge 3 ] || \
       [ "$MAJOR_VERSION" -eq 23 -a "$MINOR_VERSION" -eq 5 -a "$PATCH_VERSION" -ge 6 ]; then
        AWG_VERSION="2.0"
        LUCI_PACKAGE_NAME="luci-proto-amneziawg"
    else
        LUCI_PACKAGE_NAME="luci-app-amneziawg"
    fi

    printf "\033[32;1mDetected AWG version: $AWG_VERSION\033[0m\n"

    AWG_DIR="/tmp/amneziawg"
    mkdir -p "$AWG_DIR"
    
    if opkg list-installed | grep -q kmod-amneziawg; then
        echo "kmod-amneziawg already installed"
    else
        KMOD_AMNEZIAWG_FILENAME="kmod-amneziawg${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${KMOD_AMNEZIAWG_FILENAME}"
        wget -O "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg file downloaded successfully"
        else
            echo "Error downloading kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
        
        opkg install "$AWG_DIR/$KMOD_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "kmod-amneziawg installed successfully"
        else
            echo "Error installing kmod-amneziawg. Please, install kmod-amneziawg manually and run the script again"
            exit 1
        fi
    fi

    if opkg list-installed | grep -q amneziawg-tools; then
        echo "amneziawg-tools already installed"
    else
        AMNEZIAWG_TOOLS_FILENAME="amneziawg-tools${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${AMNEZIAWG_TOOLS_FILENAME}"
        wget -O "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools file downloaded successfully"
        else
            echo "Error downloading amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$AMNEZIAWG_TOOLS_FILENAME"

        if [ $? -eq 0 ]; then
            echo "amneziawg-tools installed successfully"
        else
            echo "Error installing amneziawg-tools. Please, install amneziawg-tools manually and run the script again"
            exit 1
        fi
    fi
    
    # Проверяем оба возможных названия пакета
    if opkg list-installed | grep -q "luci-proto-amneziawg\|luci-app-amneziawg"; then
        echo "$LUCI_PACKAGE_NAME already installed"
    else
        LUCI_AMNEZIAWG_FILENAME="${LUCI_PACKAGE_NAME}${PKGPOSTFIX}"
        DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_AMNEZIAWG_FILENAME}"
        wget -O "$AWG_DIR/$LUCI_AMNEZIAWG_FILENAME" "$DOWNLOAD_URL"

        if [ $? -eq 0 ]; then
            echo "$LUCI_PACKAGE_NAME file downloaded successfully"
        else
            echo "Error downloading $LUCI_PACKAGE_NAME. Please, install $LUCI_PACKAGE_NAME manually and run the script again"
            exit 1
        fi

        opkg install "$AWG_DIR/$LUCI_AMNEZIAWG_FILENAME"

        if [ $? -eq 0 ]; then
            echo "$LUCI_PACKAGE_NAME installed successfully"
        else
            echo "Error installing $LUCI_PACKAGE_NAME. Please, install $LUCI_PACKAGE_NAME manually and run the script again"
            exit 1
        fi
    fi

    # Устанавливаем русскую локализацию только для AWG 2.0
    if [ "$AWG_VERSION" = "2.0" ]; then
        printf "\033[32;1mУстанавливаем пакет с русской локализацией? Install Russian language pack? (y/n) [n]: \033[0m\n"
        read INSTALL_RU_LANG
        INSTALL_RU_LANG=${INSTALL_RU_LANG:-n}

        if [ "$INSTALL_RU_LANG" = "y" ] || [ "$INSTALL_RU_LANG" = "Y" ]; then
            if opkg list-installed | grep -q luci-i18n-amneziawg-ru; then
                echo "luci-i18n-amneziawg-ru already installed"
            else
                LUCI_I18N_AMNEZIAWG_RU_FILENAME="luci-i18n-amneziawg-ru${PKGPOSTFIX}"
                DOWNLOAD_URL="${BASE_URL}v${VERSION}/${LUCI_I18N_AMNEZIAWG_RU_FILENAME}"
                wget -O "$AWG_DIR/$LUCI_I18N_AMNEZIAWG_RU_FILENAME" "$DOWNLOAD_URL"

                if [ $? -eq 0 ]; then
                    echo "luci-i18n-amneziawg-ru file downloaded successfully"
                    opkg install "$AWG_DIR/$LUCI_I18N_AMNEZIAWG_RU_FILENAME"
                    if [ $? -eq 0 ]; then
                        echo "luci-i18n-amneziawg-ru installed successfully"
                    else
                        echo "Warning: Error installing luci-i18n-amneziawg-ru (non-critical)"
                    fi
                else
                    echo "Warning: Russian localization not available for this version/platform (non-critical)"
                fi
            fi
        else
            printf "\033[32;1mSkipping Russian language pack installation.\033[0m\n"
        fi
    fi

    rm -rf "$AWG_DIR"

##################################################################################################################

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
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
echo -e "${GREEN}Интерфейс ${NC}$IF_NAME${GREEN} создан и активирован!${NC}"

##################################################################################################################

echo -e "\n${YELLOW}Вставьте рабочий конфиг в Interfaces (Интерфейс) AWG!\nНажмите ${NC}Ctrl+C${YELLOW} для остановки или ${NC}Enter${YELLOW} для установки Podkop!${NC}"
read -p "" dummy
echo -e "${YELLOW}Podkop будет установлен / обновлён!\nВсе настройки Podkop будут сброшены!\nPodkop будет настроен для работы с AWG!${NC}"
read -p "Нажмите Enter..." dummy
##################################################################################################################

echo -e "${MAGENTA}Устанавливаем Podkop${NC}"
TMP="/tmp/podkop"
rm -rf "$TMP"
mkdir -p "$TMP"
cd "$TMP"
download() {
local url="$1"
local file="$2"
echo -e "${CYAN}Скачиваем ${NC}$file"
if ! wget -q -O "$file" "$url"; then
echo -e "\n${RED}Ошибка! Не удалось скачать $file${NC}\n"
exit 1
fi
}
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/podkop-v0.7.10-r1-all.ipk podkop.ipk
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-app-podkop-v0.7.10-r1-all.ipk luci-app-podkop.ipk
download https://github.com/itdoginfo/podkop/releases/download/0.7.10/luci-i18n-podkop-ru-0.7.10.ipk luci-i18n-podkop-ru.ipk
install_pkg() {
local file="$1"
local name="$2"
echo -e "${CYAN}Устанавливаем ${NC}${name}"
if ! opkg install "$file" >/dev/null 2>&1; then
echo -e "\n${RED}Ошибка! Не удалось установить ${name}${NC}\n"
exit 1
fi
}
install_pkg podkop.ipk podkop-v0.7.10-r1-all.ipk
install_pkg luci-app-podkop.ipk luci-app-podkop-v0.7.10-r1-all.ipk
install_pkg luci-i18n-podkop-ru.ipk luci-i18n-podkop-ru-0.7.10.ipk
cd /
rm -rf "$TMP"
wget -qO /etc/config/podkop https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/podkop
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
