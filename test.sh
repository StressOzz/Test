#!/bin/sh

opkg update

# Определяем архитектуру и версию OpenWrt
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"

# Определяем версию AWG
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
printf "\033[32;1mDetected AWG version: $AWG_VERSION\033[0m\n"

AWG_DIR="/tmp/amneziawg"
mkdir -p "$AWG_DIR"

install_pkg() {
    local pkgname=$1
    local filename="${pkgname}${PKGPOSTFIX}"
    local url="${BASE_URL}v${VERSION}/${filename}"

    if opkg list-installed | grep -q "$pkgname"; then
        echo "$pkgname already installed"
        return
    fi

    echo "Downloading $pkgname..."
    if wget -O "$AWG_DIR/$filename" "$url"; then
        echo "Installing $pkgname..."
        if opkg install "$AWG_DIR/$filename"; then
            echo "$pkgname installed successfully"
        else
            echo "Error installing $pkgname. Please install manually."
            exit 1
        fi
    else
        echo "Error downloading $pkgname. Please install manually."
        exit 1
    fi
}

# Устанавливаем пакеты
install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "$LUCI_PACKAGE_NAME"

# Русская локализация только для AWG 2.0
if [ "$AWG_VERSION" = "2.0" ]; then
    printf "\033[32;1mInstall Russian language pack? (y/n) [n]: \033[0m"
    read INSTALL_RU_LANG
    INSTALL_RU_LANG=${INSTALL_RU_LANG:-n}

    if [ "$INSTALL_RU_LANG" = "y" ] || [ "$INSTALL_RU_LANG" = "Y" ]; then
        install_pkg "luci-i18n-amneziawg-ru" || echo "Warning: Russian localization not installed (non-critical)"
    else
        echo "Skipping Russian language pack."
    fi
fi

rm -rf "$AWG_DIR"
