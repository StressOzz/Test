#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Берём все ссылки на ipk из JSON
URLS=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*\.ipk')

# Скачиваем каждый файл
for url in $URLS; do
    file="$TMP_DIR/$(basename "$url")"
    wget -q -O "$file" "$url"
    [ -f "$file" ] && opkg install "$file"
done

