#!/bin/sh

CONF="/etc/opkg/distfeeds.conf"

update_packages() {
    echo ""
    echo "[*] Обновляем списки пакетов..."

    PKG="$(command -v apk >/dev/null 2>&1 && echo apk || echo opkg)"

    $PKG update >/dev/null 2>&1 || {
        echo "[!] Ошибка при обновлении $PKG"
        return 1
    }

    echo "[✓] Обновление выполнено ($PKG)"
}

replace_server() {
    NEW_BASE="$1"

    echo ""
    echo "[*] Переключаем на: $NEW_BASE"

    sed -i "s|https://[^/]*/releases|https://$NEW_BASE/releases|g" "$CONF"

    echo "[✓] Зеркало обновлено"

    update_packages
}

show_menu() {
    echo ""
    echo "Выберите зеркало:"
    echo "1) mirror.tiguinet.net/openwrt"
    echo "2) ftp.snt.utwente.nl/pub/software/openwrt"
    echo "3) mirror.berlin.freifunk.net/downloads.openwrt.org"
    echo "4) mirrors.xjtu.edu.cn/openwrt"
    echo "5) mirrors.cloud.tencent.com/openwrt"
    echo "6) Вернуть downloads.openwrt.org"
    echo "0) Выход"
    echo ""
    printf "Введите номер: "
}

while true; do
    show_menu
    read choice

    case "$choice" in
        1) replace_server "mirror.tiguinet.net/openwrt" ;;
        2) replace_server "ftp.snt.utwente.nl/pub/software/openwrt" ;;
        3) replace_server "mirror.berlin.freifunk.net/downloads.openwrt.org" ;;
        4) replace_server "mirrors.xjtu.edu.cn/openwrt" ;;
        5) replace_server "mirrors.cloud.tencent.com/openwrt" ;;
        6) replace_server "downloads.openwrt.org" ;;
        0) exit 0 ;;
        *) echo "Неверный выбор" ;;
    esac
done
