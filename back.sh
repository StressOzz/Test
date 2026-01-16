#!/bin/sh

opkg update

BASE_URL="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.4/routerich"

get_ipk() {
    wget -qO- "$BASE_URL/" | grep -o "$1[^\"']*\.ipk" | head -n1
}

ZAPRET=$(get_ipk "zapret2_")
LUCI=$(get_ipk "luci-app-zapret2_")

[ -z "$ZAPRET" ] && { echo "zapret2_*.ipk не найден"; exit 1; }
[ -z "$LUCI" ] && { echo "luci-app-zapret2_*.ipk не найден"; exit 1; }

wget -qO- "$BASE_URL/$ZAPRET" | opkg install -
wget -qO- "$BASE_URL/$LUCI" | opkg install -
