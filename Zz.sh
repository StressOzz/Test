#!/bin/sh
clear

B="https://github.com/routerich/packages.routerich"
H="$B/tree/24.10.4/routerich"
R="$B/raw/refs/heads/24.10.4/routerich"
T=/tmp
G="\033[1;32m"; N="\033[0m"

f() { wget -qO- "$H" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1; }
i() { P=$(f "$1") && [ -n "$P" ] || { echo "$1 не найден"; exit 1; }; echo -e "${G}$P${N}"; wget -q "$R/$P" -O "$T/$P" && opkg install "$T/$P" >/dev/null; }

echo -e "${G}opkg update${N}"
opkg update >/dev/null 2>&1 || exit 1

i zapret2_
i luci-app-zapret2_

echo -e "${G}Готово${N}"

