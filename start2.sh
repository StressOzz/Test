#!/bin/sh
OPENWRT_VER=$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2 | cut -d. -f1)
if [ "$OPENWRT_VER" -lt 25 ]; then sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/ZM_24.sh)
else sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/ZM_25.sh); fi
