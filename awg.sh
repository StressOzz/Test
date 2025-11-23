#!/bin/sh
opkg update
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
