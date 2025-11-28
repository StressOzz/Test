#!/bin/sh
GREEN="\033[1;32m"; RED="\033[1;31m"; NC="\033[0m"
CONF="/etc/config/zapret"
clear

echo -e "\n${GREEN}===== Информация о системе =====${NC}"
MODEL=$(cat /tmp/sysinfo/model)
TARGET=$(sed -n "s/.*TARGET='\(.*\)'/\1/p" /etc/openwrt_release)
ARCH=$(sed -n "s/.*ARCH='\(.*\)'/\1/p" /etc/openwrt_release)
OWRT=$(sed -n "s/.*OpenWrt \([0-9.]*\).*/\1/p" /etc/openwrt_release)
echo -e "${GREEN}$MODEL${NC}"
echo -e "${GREEN}$ARCH${NC} | ${GREEN}$TARGET${NC}"
echo -e "${GREEN}$OWRT${NC}"

echo -e "\n${GREEN}===== Пользовательские пакеты =====${NC}"
PKGS=$(awk '/^Package:/ {p=$2} /^Status: install user/ {print p}' /usr/lib/opkg/status)
i=0; for p in $PKGS; do i=$((i+1)); eval "pkg$i='$p'"; done
half=$(( (i+1)/2 ))
for n in $(seq 1 $half); do
    eval "l=\$pkg$n"; eval "r=\$pkg$((n+half))"
    printf "%-20s %s\n" "$l" "$r"
done

echo -e "\n${GREEN}===== Flow Offloading =====${NC}"
sw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)
grep -q 'ct original packets ge 30' /usr/share/firewall4/templates/ruleset.uc && dpi="${RED}yes${NC}" || dpi="${GREEN}no${NC}"
[ "$hw" = 1 ] && out="HW: ${RED}on${NC}" || \
[ "$sw" = 1 ] && out="SW: ${RED}on${NC}" || \
out="SW: ${GREEN}off${NC} | HW: ${GREEN}off${NC}"
echo -e "$out | FIX: $dpi"

echo -e "\n${GREEN}===== Проверка GitHub =====${NC}"
RATE=$(curl -s https://api.github.com/rate_limit | grep '"remaining"' | head -1 | tr -d '",' | awk '{print $2}')
[ -z "$RATE" ] && RATE_OUT="${RED}N/A${NC}" || RATE_OUT=$([ "$RATE" -eq 0 ] && echo "${RED}0${NC}" || echo "${GREEN}$RATE${NC}")

printf "IPv4: "; curl -4 -Is --connect-timeout 3 https://github.com >/dev/null 2>&1 && echo -ne "${GREEN}ok${NC}" || echo -ne "${RED}fail${NC}"
printf "  IPv6: "; curl -6 -Is --connect-timeout 3 https://github.com >/dev/null 2>&1 && echo -e "${GREEN}ok${NC}" || echo -e "${RED}fail${NC}"
printf "API: "; curl -Is --connect-timeout 3 https://api.github.com >/dev/null 2>&1 \
&& echo -e "${GREEN}ok${NC}   Limit: $RATE_OUT" \
|| echo -e "${RED}fail${NC}   Limit: $RATE_OUT"

echo -e "\n${GREEN}===== Настройки Zapret =====${NC}"
zpr_info() {
    INSTALLED_VER=$(opkg list-installed | awk '/^zapret /{print $3}')
    /etc/init.d/zapret status 2>/dev/null | grep -qi running && Z="${GREEN}запущен${NC}" || Z="${RED}остановлен${NC}"

    SCRIPT="/opt/zapret/init.d/openwrt/custom.d/50-script.sh"
    [ -f "$SCRIPT" ] && head -1 "$SCRIPT" | grep -qi quic && name="50-quic4all" \
        || head -1 "$SCRIPT" | grep -qi stun && name="50-stun4all" \
        || head -1 "$SCRIPT" | grep -qi "discord media" && name="50-discord-media" \
        || head -1 "$SCRIPT" | grep -qi "discord subnets" && name="50-discord"

    TCP_VAL=$(sed -n "s/.*NFQWS_PORTS_TCP'\(.*\)'.*/\1/p" "$CONF")
    UDP_VAL=$(sed -n "s/.*NFQWS_PORTS_UDP'\(.*\)'.*/\1/p" "$CONF")

    echo -e "${GREEN}$INSTALLED_VER${NC} | $Z"
    [ -n "$name" ] && echo -e "${GREEN}$name${NC}"
    echo -e "TCP: ${GREEN}$TCP_VAL${NC} | UDP: ${GREEN}$UDP_VAL${NC}"

    echo -e "\n${GREEN}===== Стратегия =====${NC}"
    awk '
    /^[[:space:]]*option[[:space:]]+NFQWS_OPT/ {flag=1; sub(/.*'\''/, ""); next}
    flag {print; if (/\'\'$/) exit}
    ' "$CONF"
}

[ -f /etc/init.d/zapret ] && zpr_info || echo -e "${RED}Zapret не установлен!${NC}\n"

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

sites_clean=$(echo "$SITES")
count=$(echo "$sites_clean" | wc -w)
half=$(( (count+1)/2 ))

for n in $(seq 1 $half); do
    l=$(echo $sites_clean | cut -d" " -f$n)
    r=$(echo $sites_clean | cut -d" " -f$((n+half)))
    lp=$(printf "%-25s" "$l")
    rp=$(printf "%-25s" "$r")

    curl -Is --connect-timeout 3 --max-time 4 "https://$l" >/dev/null 2>&1 && lc="[${GREEN}OK${NC}]" || lc="[${RED}FAIL${NC}]"
    if [ -n "$r" ]; then
        curl -Is --connect-timeout 3 --max-time 4 "https://$r" >/dev/null 2>&1 && rc="[${GREEN}OK${NC}]" || rc="[${RED}FAIL${NC}]"
        echo -e "$lc  $lp $rc  $rp"
    else
        echo -e "$lc  $lp"
    fi
done

echo
