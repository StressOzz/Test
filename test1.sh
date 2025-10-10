#!/bin/sh
set -e

REPO="itdoginfo/podkop"
TMP_DIR="/tmp/podkop_install"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# Получаем последний тег без -P
LATEST_TAG=$(wget -qO- "https://api.github.com/repos/$REPO/releases/latest" | grep '"tag_name":' | head -n1 | cut -d'"' -f4)

FILES=(
    "luci-app-podkop-${LATEST_TAG}-all.ipk"
    "luci-i18n-podkop-ru-${LATEST_TAG}.ipk"
    "podkop-${LATEST_TAG}-all.ipk"
)

for FILE in "${FILES[@]}"; do
    wget -q -P "$TMP_DIR" "https://github.com/$REPO/releases/download/$LATEST_TAG/$FILE"
done

opkg install "$TMP_DIR"/*.ipk

rm -rf "$TMP_DIR"

