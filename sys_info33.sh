
#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"
CONF="/etc/config/zapret"
clear
echo -e "\n${GREEN}===== Информация о системе =====${NC}"
MODEL=$(cat /tmp/sysinfo/model)
TARGET=$(awk -F= '/DISTRIB_TARGET/ {gsub(/'\''/, "", $2); print $2}' /etc/openwrt_release)
ARCH=$(awk -F= '/DISTRIB_ARCH/ {gsub(/'\''/, "", $2); print $2}' /etc/openwrt_release)
OWRT=$(awk -F= '/DISTRIB_DESCRIPTION/ {gsub(/'\''|OpenWrt /, "", $2); print $2}' /etc/openwrt_release)
echo -e "Роутер: ${GREEN}$MODEL${NC}"
echo -e "Архитектура: ${GREEN}$ARCH${NC} | ${GREEN}$TARGET${NC}"
echo -e "OpenWrt: ${GREEN}$OWRT${NC}"
echo -e "\n${GREEN}===== Пользовательские пакеты =====${NC}"
PKGS=$(awk '/^Package:/ {p=$2} /^Status: install user/ {print p}' /usr/lib/opkg/status | grep -v '^$')
idx=0
for pkg in $PKGS; do
idx=$((idx+1))
eval "pkg$idx='$pkg'"
done
total=$idx
half=$(( (total + 1) / 2 ))
for i in $(seq 1 $half); do
eval "left=\$pkg$i"
right_idx=$((i + half))
eval "right=\$pkg$right_idx"
left_pad=$(printf "%-20s" "$left")
if [ -n "$right" ]; then
right_pad=$(printf "%-20s" "$right")
echo "$left_pad $right_pad"
else
echo "$left_pad"
fi
done
echo -e "\n${GREEN}===== Flow Offloading =====${NC}"
sw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)
if grep -q 'ct original packets ge 30' /usr/share/firewall4/templates/ruleset.uc 2>/dev/null; then
dpi="${RED}yes${NC}"
else
dpi="${GREEN}no${NC}"
fi
if [ "$hw" = "1" ]; then
out="HW: ${RED}on${NC}"
elif [ "$sw" = "1" ]; then
out="SW: ${RED}on${NC}"
else
out="SW: ${GREEN}off${NC} | HW: ${GREEN}off${NC}"
fi
out="$out | FIX: ${dpi}"
echo -e "$out"
echo -e "\n${GREEN}===== Проверка GitHub =====${NC}"
RATE=$(curl -s https://api.github.com/rate_limit | grep '"remaining"' | head -1 | awk '{print $2}' | tr -d ,)
[ -z "$RATE" ] && RATE_OUT="${RED}N/A${NC}" || RATE_OUT=$([ "$RATE" -eq 0 ] && echo -e "${RED}0${NC}" || echo -e "${GREEN}$RATE${NC}")
echo -n "GitHub IPv4: "
curl -4 -Is --connect-timeout 3 https://github.com >/dev/null 2>&1 && echo -ne "${GREEN}ok${NC}" || echo -ne "${RED}fail${NC}"
echo -n "  IPv6: "
curl -6 -Is --connect-timeout 3 https://github.com >/dev/null 2>&1 && echo -e "${GREEN}ok${NC}" || echo -e "${RED}fail${NC}"
echo -n "GitHub API: "
curl -Is --connect-timeout 3 https://api.github.com >/dev/null 2>&1 \
&& echo -e "${GREEN}ok${NC}   Остаток: $RATE_OUT" \
|| echo -e "${RED}fail${NC}   Остаток: $RATE_OUT"
echo -e "\n${GREEN}===== Настройки Zapret =====${NC}"
zpr_info() {
INSTALLED_VER=$(opkg list-installed | grep '^zapret ' | awk '{print $3}')
if /etc/init.d/zapret status 2>/dev/null | grep -qi "running"; then
ZAPRET_STATUS="${GREEN}запущен${NC}"
else
ZAPRET_STATUS="${RED}остановлен${NC}"
fi
SCRIPT_FILE="/opt/zapret/init.d/openwrt/custom.d/50-script.sh"
if [ -f "$SCRIPT_FILE" ]; then
line=$(head -n1 "$SCRIPT_FILE")
case "$line" in
*QUIC*) name="50-quic4all" ;;
*stun*) name="50-stun4all" ;;
*"discord media"*) name="50-discord-media" ;;
*"discord subnets"*) name="50-discord" ;;
*) name="" ;;
esac
fi
TCP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
| sed "s/.*'\(.*\)'.*/\1/")
UDP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
| sed "s/.*'\(.*\)'.*/\1/")
echo -e "Версия: ${GREEN}$INSTALLED_VER${NC} | $ZAPRET_STATUS"
[ -n "$name" ] && echo -e "Скрипт: ${GREEN}$name${NC}"
echo -e "Порты TCP: ${GREEN}$TCP_VAL${NC} | UDP: ${GREEN}$UDP_VAL${NC}"
echo -e "\n${GREEN}===== Стратегия =====${NC}"
awk '
/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/ {flag=1; sub(/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/, ""); next}
flag {
if (/'\''/) {sub(/'\''$/, ""); print; exit}
print
}' "$CONF"
}
if [ -f /etc/init.d/zapret ]; then
zpr_info
else
echo -e "\n${RED}Zapret не установлен!${NC}\n"
fi



echo -e "${GREEN}===== Доступность сайтов =====${NC}"

SITES="
gosuslugi.ru
esia.gosuslugi.ru/login
rutube.ru
youtube.com
instagram.com
rutor.info
ntc.party
rutracker.org
epidemz.net.co
nnmclub.to
openwrt.org
sxyprn.net
pornhub.com
discord.com
x.com
filmix.my
flightradar24.com
cdn77.com
play.google.com
genderize.io
"

TMPDIR="/tmp/checksites.$$"
mkdir -p "$TMPDIR"

i=0
for s in $SITES; do
    i=$((i+1))
    echo "$s" > "$TMPDIR/site_$i"
    (
        curl -Is --connect-timeout 3 --max-time 4 "https://$s" >/dev/null 2>&1
        [ $? -eq 0 ] && echo OK > "$TMPDIR/res_$i" || echo FAIL > "$TMPDIR/res_$i"
    ) &
done

wait

TOTAL=$i
HALF=$(( (TOTAL+1)/2 ))

for n in $(seq 1 $HALF); do
    L_SITE=$(cat "$TMPDIR/site_$n")
    L_RES=$(cat "$TMPDIR/res_$n")

    [ "$L_RES" = "OK" ] && L_COLOR="[${GREEN}OK${NC}]" || L_COLOR="[${RED}FAIL${NC}]"
    L_PAD=$(printf "%-25s" "$L_SITE")

    R_IDX=$((n+HALF))

    if [ $R_IDX -le $TOTAL ]; then
        R_SITE=$(cat "$TMPDIR/site_$R_IDX")
        R_RES=$(cat "$TMPDIR/res_$R_IDX")

        [ "$R_RES" = "OK" ] && R_COLOR="[${GREEN}OK${NC}]" || R_COLOR="[${RED}FAIL${NC}]"
        R_PAD=$(printf "%-25s" "$R_SITE")

        echo -e "$L_COLOR  $L_PAD $R_COLOR  $R_PAD"
    else
        echo -e "$L_COLOR  $L_PAD"
    fi
done

rm -rf "$TMPDIR"
echo
