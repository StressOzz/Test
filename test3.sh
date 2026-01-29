#!/bin/sh
# zapret silent installer (wget only, busybox safe)

set -e

ARCH=$( . /etc/openwrt_release; echo "$DISTRIB_ARCH" )
BASE_URL="https://raw.githubusercontent.com/remittor/zapret-openwrt/gh-pages/releases"
TMP="/tmp/zapret.$$"

mkdir -p "$TMP" || exit 1
cd "$TMP" || exit 1

# ----------------------------
# выбор пакетного менеджера
# ----------------------------
if command -v apk >/dev/null 2>&1; then
    EXT=apk
    update_pkg() { apk update -q >/dev/null 2>&1; }
    install_pkg() { apk add --allow-untrusted --upgrade -q "$1" >/dev/null 2>&1; }

elif command -v opkg >/dev/null 2>&1; then
    EXT=ipk
    update_pkg() { opkg update >/dev/null 2>&1; }
    install_pkg() { opkg install --force-reinstall "$1" >/dev/null 2>&1; }

else
    echo "No package manager found"
    exit 1
fi

update_pkg || true

# ----------------------------
# получаем ссылку на релиз
# ----------------------------
JSON="$BASE_URL/releases_zap1_${ARCH}.json"

wget -qO rel.json "$JSON" || exit 1
URL=$(grep -m1 browser_download_url rel.json | cut -d '"' -f4)

[ -z "$URL" ] && exit 1

# ----------------------------
# скачиваем архив
# ----------------------------
wget -qO pkg.zip "$URL" || exit 1
unzip -qq pkg.zip || exit 1

rm -f pkg.zip rel.json

# ----------------------------
# находим пакеты
# ----------------------------
BASE_PKG=$(ls zapret*.${EXT} 2>/dev/null | grep -v luci | head -n1)
LUCI_PKG=$(ls luci-app-zapret*.${EXT} 2>/dev/null | head -n1)

[ -f "$BASE_PKG" ] || exit 1
[ -f "$LUCI_PKG" ] || exit 1

# ----------------------------
# установка
# ----------------------------
install_pkg "$BASE_PKG"
install_pkg "$LUCI_PKG"

cd /
rm -rf "$TMP"

exit 0
