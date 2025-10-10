#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "Скачиваем список пакетов последнего релиза..."
URLS=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*\.ipk')

echo "Скачиваем пакеты..."
for url in $URLS; do
    file="$TMP_DIR/$(basename "$url")"
    wget -q -O "$file" "$url"
done

echo "Устанавливаем podkop..."
for file in "$TMP_DIR"/podkop*.ipk; do
    [ -f "$file" ] && opkg install "$file" >/dev/null 2>&1
done

echo "Устанавливаем luci-app..."
for file in "$TMP_DIR"/luci-app*.ipk; do
    [ -f "$file" ] && opkg install "$file" >/dev/null 2>&1
done

read -p "Устанавливать русский язык для Podkop? (y/n) " RUS
case "$RUS" in
    y|Y)
        echo "Устанавливаем русскую локализацию..."
        for file in "$TMP_DIR"/luci-i18n*.ipk; do
            [ -f "$file" ] && opkg install "$file" >/dev/null 2>&1
        done
        ;;
    *) echo "Русский язык не будет установлен." ;;
esac

rm -rf "$TMP_DIR"
echo "Установка завершена."
