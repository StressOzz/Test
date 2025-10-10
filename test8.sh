#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

# Очистка и создание временной папки
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Получаем все ссылки на .ipk из последнего релиза
URLS=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep -o 'https://[^"]*\.ipk')

# Скачиваем и устанавливаем каждый пакет
for url in $URLS; do
    file="$TMP_DIR/$(basename "$url")"
    wget -q -O "$file" "$url"
    [ -f "$file" ] && opkg install "$file" || true
done
