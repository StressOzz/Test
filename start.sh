#!/bin/sh
FULL_VER=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
[ -z "$FULL_VER" ] && FULL_VER="0.0"
OPENWRT_VER=$(echo "$FULL_VER" | cut -d. -f1)
if [ "$OPENWRT_VER" -lt 25 ]; then
echo "Запуск скрипта для OpenWrt <=24"
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)
else
echo "Запуск скрипта для OpenWrt 25+"
sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Test/main/ow18.sh)
fi
