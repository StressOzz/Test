#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
clear
echo "Скачиваем список пакетов последнего релиза..."
URLS=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*\.ipk')

echo "Скачиваем пакеты..."
for url in $URLS; do
    file="$TMP_DIR/$(basename "$url")"
    wget -q -O "$file" "$url"
done

install_pkg() {
    pkg="$1"
    echo "Устанавливаем $pkg..."
    for file in "$TMP_DIR"/$pkg*.ipk; do
        if [ -f "$file" ]; then
            opkg install "$file" || echo "Не удалось установить $file (возможна несовместимая архитектура или зависимость)"
        fi
    done
}

install_pkg "podkop"
install_pkg "luci-app"

read -p "Устанавливать русский язык для Podkop? (y/n) " RUS
case "$RUS" in
    y|Y)
        install_pkg "luci-i18n"
        ;;
    *) echo "Русский язык не будет установлен." ;;
esac

rm -rf "$TMP_DIR"
echo "Установка завершена."
