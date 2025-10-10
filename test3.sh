#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Получаем последний тег
LATEST_TAG=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)

# Точные имена файлов
FILE1="luci-app-podkop-${LATEST_TAG}-all.ipk"
FILE2="luci-i18n-podkop-ru-${LATEST_TAG}.ipk"
FILE3="podkop-${LATEST_TAG}-all.ipk"

URL_BASE="https://github.com/$REPO/releases/download/$LATEST_TAG"

# Скачиваем файлы
wget -q -P "$TMP_DIR" "$URL_BASE/$FILE1"
wget -q -P "$TMP_DIR" "$URL_BASE/$FILE2"
wget -q -P "$TMP_DIR" "$URL_BASE/$FILE3"

# Ставим, только если файл существует
[ -f "$TMP_DIR/$FILE1" ] && opkg install "$TMP_DIR/$FILE1"
[ -f "$TMP_DIR/$FILE2" ] && opkg install "$TMP_DIR/$FILE2"
[ -f "$TMP_DIR/$FILE3" ] && opkg install "$TMP_DIR/$FILE3"

rm -rf "$TMP_DIR"
