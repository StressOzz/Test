#!/bin/sh

REPO="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
DOWNLOAD_DIR="/tmp/podkop"

PKG_IS_APK=0
command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

rm -rf "$DOWNLOAD_DIR"
mkdir -p "$DOWNLOAD_DIR"

# Цвета
GREEN="\033[32;1m"
WHITE="\033[37;1m"
NC="\033[0m"

msg() {
    # $1 — действие, $2 — название пакета/объекта (необязательное)
    if [ -n "$2" ]; then
        printf "${GREEN}%s ${WHITE}%s${NC}\n" "$1" "$2"
    else
        printf "${GREEN}%s${NC}\n" "$1"
    fi
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
    msg "Удаляем" "$pkg_name..."
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk del "$pkg_name" >/dev/null 2>&1
    else
        opkg remove --force-depends "$pkg_name" >/dev/null 2>&1
    fi
}

pkg_list_update() {
    msg "Обновляем список пакетов..."
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk update >/dev/null 2>&1
    else
        opkg update >/dev/null 2>&1
    fi
}

pkg_install() {
    local pkg_file="$1"
    msg "Устанавливаем" "$(basename "$pkg_file")"
    if [ "$PKG_IS_APK" -eq 1 ]; then
        apk add --allow-untrusted "$pkg_file" >/dev/null 2>&1
    else
        opkg install "$pkg_file" >/dev/null 2>&1
    fi
}

check_system() {
    MODEL=$(cat /tmp/sysinfo/model)
    msg "Модель роутера:" "$MODEL"

    openwrt_version=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2 | cut -d'.' -f1)
    [ "$openwrt_version" = "23" ] && {
        msg "OpenWrt 23.05 не поддерживается начиная с Podkop 0.5.0"
        exit 1
    }

    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=15360
    [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && { msg "Недостаточно свободного места"; exit 1; }

    nslookup google.com >/dev/null 2>&1 || { msg "DNS не работает"; exit 1; }

    if pkg_is_installed https-dns-proxy; then
        msg "Обнаружен конфликтный пакет" "https-dns-proxy. Удаляем..."
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

    msg "Синхронизация времени..."
    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123 >/dev/null 2>&1

    pkg_list_update || { msg "Не удалось обновить список пакетов"; exit 1; }

    if [ -f "/etc/init.d/podkop" ]; then
        msg "Podkop уже установлен. Обновляем..."
    else
        msg "Устанавливаем Podkop..."
    fi

    # Проверка GitHub API
    if command -v curl >/dev/null 2>&1; then
        check_response=$(curl -s "$REPO")
        if echo "$check_response" | grep -q 'API rate limit '; then
            msg "Превышен лимит запросов GitHub. Повторите позже."
            exit 1
        fi
    fi

    # Шаблон для поиска пакета
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    # Упрощённое скачивание (один раз)
    download_success=0
    urls=$(wget -qO- "$REPO" 2>/dev/null | grep -o "$grep_url_pattern")
    for url in $urls; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"

        msg "Скачиваем" "$filename..."
        if wget -q -O "$filepath" "$url" >/dev/null 2>&1 && [ -s "$filepath" ]; then
            msg "Скачано" "$filename"
            download_success=1
        else
            msg "Ошибка скачивания" "$filename"
        fi
    done

    [ $download_success -eq 0 ] && { msg "Нет успешно скачанных пакетов"; exit 1; }

    # Установка основных пакетов
    for pkg in podkop luci-app-podkop; do
        file=$(ls "$DOWNLOAD_DIR" | grep "^$pkg" | head -n 1)
        [ -n "$file" ] && pkg_install "$DOWNLOAD_DIR/$file"
    done

    # Русский интерфейс
    ru=$(ls "$DOWNLOAD_DIR" | grep "luci-i18n-podkop-ru" | head -n 1)
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop-ru; then
            msg "Обновляем русский язык..." "$ru"
            pkg_remove luci-i18n-podkop* >/dev/null 2>&1
            pkg_install "$DOWNLOAD_DIR/$ru"
        else
            msg "Установить русский интерфейс? y/N (Enter = Нет)"
            read -r RUS
            case "$RUS" in
                y|Y) pkg_install "$DOWNLOAD_DIR/$ru" ;;
                n|N|"") break ;;
                *) exit 0 ;;
            esac
        fi
    fi

    # Очистка временных файлов
    find "$DOWNLOAD_DIR" -type f -name '*podkop*' -exec rm -f {} \;
}

main
