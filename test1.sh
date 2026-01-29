#!/bin/sh
set -e

ARCH=$( . /etc/openwrt_release; echo "$DISTRIB_ARCH" )
BASE_URL="https://raw.githubusercontent.com/remittor/zapret-openwrt/gh-pages/releases"
TMP="/tmp/zapret-install.$$"

mkdir -p "$TMP"
cd "$TMP"

if command -v apk >/dev/null 2>&1; then
    PKG=apk
    EXT=apk
    UPDATE="apk update -q"
    DEPS="apk add -q curl unzip"
    install_pkg() { apk add --allow-untrusted --upgrade -q "$1"; }

elif command -v opkg >/dev/null 2>&1; then
    PKG=opkg
    EXT=ipk
    UPDATE="opkg update"
    DEPS="opkg install curl unzip"
    install_pkg() { opkg install --force-reinstall "$1"; }

else
    echo "No package manager found"
    exit 1
fi

# зависимости
$UPDATE >/dev/null 2>&1 || true
$DEPS   >/dev/null 2>&1 || true

URL=$(curl -fsSL "$BASE_URL/releases_zap1_${ARCH}.json" | grep -m1 browser_download_url | cut -d '"' -f4) || exit 1

curl -fsSL "$URL" -o zapret.zip || exit 1
unzip -qq zapret.zip || exit 1
rm -f zapret.zip

BASE=$(ls zapret*.${EXT} | grep -v luci | head -n1)
LUCI=$(ls luci-app-zapret*.${EXT} | head -n1)

install_pkg "$BASE" >/dev/null 2>&1 || exit 1
install_pkg "$LUCI" >/dev/null 2>&1 || exit 1

cd /
rm -rf "$TMP"
exit 0
