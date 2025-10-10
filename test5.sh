#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

# Очистка и создание временной папки
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Получаем последнюю версию
LATEST_TAG=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)

# URL файлов
URL_BASE="https://github.com/$REPO/releases/download/$LATEST_TAG"

wget -q -P "$TMP_DIR" "$URL_BASE/podkop-${LATEST_TAG}-all.ipk"
wget -q -P "$TMP_DIR" "$URL_BASE/luci-app-podkop-${LATEST_TAG}-all.ipk"
wget -q -P "$TMP_DIR" "$URL_BASE/luci-i18n-podkop-ru-${LATEST_TAG}.ipk"

# Установка пакетов, только если файл существует
[ -f "$TMP_DIR/podkop-${LATEST_TAG}-all.ipk" ] && opkg install "$TMP_DIR/podkop-${LATEST_TAG}-all.ipk"
[ -f "$TMP_DIR/luci-app-podkop-${LATEST_TAG}-all.ipk" ] && opkg install "$TMP_DIR/luci-app-podkop-${LATEST_TAG}-all.ipk"
[ -f "$TMP_DIR/luci-i18n-podkop-ru-${LATEST_TAG}.ipk" ] && opkg install "$TMP_DIR/luci-i18n-podkop-ru-${LATEST_TAG}.ipk"

