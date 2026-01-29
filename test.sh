#!/bin/sh

set -e

ARCH=$( . /etc/openwrt_release; echo "$DISTRIB_ARCH" )
BASE_URL="https://raw.githubusercontent.com/remittor/zapret-openwrt/gh-pages/releases"
TMP="/tmp/zapret-install.$$"

mkdir -p "$TMP"
cd "$TMP"

# --- менеджер пакетов ---
if command -v apk >/dev/null 2>&1; then
    PKG=apk
    EXT=apk
    UPDATE="apk update -q"
    INSTALL="apk add --allow-untrusted --upgrade -q"
    DEPS="apk add -q curl unzip"
elif command -v opkg >/dev/null 2>&1; then
    PKG=opkg
    EXT=ipk
    UPDATE="opkg update >/dev/null 2>&1"
    INSTALL="opkg install --force-reinstall >/dev/null 2>&1"
    DEPS="opkg install curl unzip >/dev/null 2>&1"
else
    echo "No package manager found"
    exit 1
fi

# --- зависимости ---
$UPDATE || true
$DEPS || true

# --- получить ссылку ---
URL=$(curl -fsSL "$BASE_URL/releases_zap1_${ARCH}.json" | grep -m1 browser_download_url | cut -d '"' -f4) || exit 1

# --- скачать ---
curl -fsSL "$URL" -o zapret.zip || exit 1
unzip -qq zapret.zip || exit 1
rm -f zapret.zip

BASE=$(ls zapret*.${EXT} | grep -v luci | head -n1)
LUCI=$(ls luci-app-zapret*.${EXT} | head -n1)

# --- установка ---
$INSTALL "$BASE" || exit 1
$INSTALL "$LUCI" || exit 1

cd /
rm -rf "$TMP"

exit 0
