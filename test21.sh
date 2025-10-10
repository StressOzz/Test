#!/bin/sh

REPO="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
DOWNLOAD_DIR="/tmp/podkop"
COUNT=3

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

msg() {
    printf "\033[32;1m%s\033[0m\n" "$1"
}

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
    msg "Removing $pkg_name..."
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk del "$pkg_name" >/dev/null 2>&1
    else
        opkg remove --force-depends "$pkg_name" >/dev/null 2>&1
    fi
}

pkg_list_update() {
    msg "Updating package list..."
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update >/dev/null 2>&1
    else
        opkg update >/dev/null 2>&1
    fi
}

pkg_install() {
    local pkg_file="$1"
    msg "Installing $(basename "$pkg_file")..."
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk add --allow-untrusted "$pkg_file" >/dev/null 2>&1
    else
        opkg install "$pkg_file" >/dev/null 2>&1
    fi
}

check_system() {
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Router model: $MODEL"

    openwrt_version=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2 | cut -d'.' -f1)
    [ "$openwrt_version" = "23" ] && {
        msg "OpenWrt 23.05 не поддерживается начиная с podkop 0.5.0"
        exit 1
    }

    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=15360
    [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && { msg "Недостаточно места в памяти"; exit 1; }

    nslookup google.com >/dev/null 2>&1 || { msg "DNS не работает"; exit 1; }

    if pkg_is_installed https-dns-proxy; then
        msg "Конфликт пакета https-dns-proxy. Удаляем..."
        pkg_remove luci-app-https-dns-proxy
        pkg_remove https-dns-proxy
        pkg_remove luci-i18n-https-dns-proxy*
    fi
}

sing_box() {
    pkg_is_installed "^sing-box" || return
    sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
    required_version="1.12.4"
    if [ "$(echo -e "$sing_box_version\n$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
        msg "sing-box устарел. Удаляем..."
        service podkop stop >/dev/null 2>&1
        pkg_remove sing-box
    fi
}

main() {
    check_system
    sing_box

    msg "Syncing time..."
    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123 >/dev/null 2>&1

    pkg_list_update || { msg "Package list update failed"; exit 1; }

    if [ -f "/etc/init.d/podkop" ]; then
        msg "Podkop already installed. Upgrading..."
    else
        msg "Installing podkop..."
    fi

    # Проверка GitHub API
    if command -v curl >/dev/null 2>&1; then
        check_response=$(curl -s "$REPO")
        if echo "$check_response" | grep -q 'API rate limit '; then
            msg "GitHub API rate limit reached. Retry later."
            exit 1
        fi
    fi

    # Шаблон для поиска пакета
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    # Цикл скачивания
    download_success=0
    urls=$(wget -qO- "$REPO" 2>/dev/null | grep -o "$grep_url_pattern")
    for url in $urls; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"
        attempt=0
        while [ $attempt -lt $COUNT ]; do
            msg "Downloading $filename (attempt $((attempt+1)))..."
            if wget -q -O "$filepath" "$url" >/dev/null 2>&1; then
                [ -s "$filepath" ] && { msg "$filename downloaded"; download_success=1; break; }
            fi
            msg "Download failed, retrying..."
            rm -f "$filepath"
            attempt=$((attempt+1))
        done
        [ $attempt -eq $COUNT ] && msg "Failed to download $filename after $COUNT attempts"
    done

    [ $download_success -eq 0 ] && { msg "No packages downloaded"; exit 1; }

    # Установка основных пакетов
    for pkg in podkop luci-app-podkop; do
        file=$(ls "$DOWNLOAD_DIR" | grep "^$pkg" | head -n 1)
        [ -n "$file" ] && pkg_install "$DOWNLOAD_DIR/$file"
    done

    # Русский интерфейс
    ru=$(ls "$DOWNLOAD_DIR" | grep "luci-i18n-podkop-ru" | head -n 1)
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop-ru; then
            msg "Upgrading Russian translation..."
            pkg_remove luci-i18n-podkop* >/dev/null 2>&1
            pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Русский интерфейс? y/n"
            while true; do
                read -r RUS
                case $RUS in
                    y) pkg_install "$DOWNLOAD_DIR/$ru"; break ;;
                    n) break ;;
                    *) msg "Введите y или n" ;;
                esac
            done
        fi
    fi

    # Очистка временных файлов
    find "$DOWNLOAD_DIR" -type f -name '*podkop*' -exec rm -f {} \;
}

main
