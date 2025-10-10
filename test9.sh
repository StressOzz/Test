#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

# Очистка и создание временной папки
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Получаем все ссылки на .ipk из последнего релиза
URLS=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*\.ipk')

# Скачиваем все файлы
for url in $URLS; do
    wget -q -O "$TMP_DIR/$(basename "$url")" "$url"
done

# Устанавливаем podkop*.ipk
for file in "$TMP_DIR"/podkop*.ipk; do
    [ -f "$file" ] && opkg install "$file"
done

# Устанавливаем luci-app*.ipk
for file in "$TMP_DIR"/luci-app*.ipk; do
    [ -f "$file" ] && opkg install "$file"
done

# Спрашиваем про русский язык
read -p "Устанавливать русский язык для Podkop? (y/n) " RUS
case "$RUS" in
    y|Y)
        for file in "$TMP_DIR"/luci-i18n*.ipk; do
            [ -f "$file" ] && opkg install "$file"
        done
        ;;
    *) ;;
esac
