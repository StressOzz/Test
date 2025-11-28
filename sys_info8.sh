#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"
CONF="/etc/config/zapret"
clear

# ===== Функции =====
chk_github() {
    curl -"$1" -Is --connect-timeout 3 https://github.com >/dev/null 2>&1 \
        && echo -ne "${GREEN}ok${NC}" || echo -ne "${RED}fail${NC}"
}

chk_api() {
    curl -Is --connect-timeout 3 https://api.github.com >/dev/null 2>&1
}

get_rate() {
    RATE=$(curl -s https://api.github.com/rate_limit | awk -F: '/remaining/ {gsub(/,/, "", $2); print $2; exit}')
    [ -n "$RATE" ] && echo "${GREEN}${RATE}${NC}" || echo "${RED}N/A${NC}"
}

zpr_info() {
    echo -e "\n${GREEN}===== Настройки запрет =====${NC}"
    INSTALLED_VER=$(opkg list-installed | awk '/^zapret / {print $3}')
    /etc/init.d/zapret status 2>/dev/null | grep -qi running \
        && ZAPRET_STATUS="${GREEN}запущен${NC}" \
        || ZAPRET_STATUS="${RED}остановлен${NC}"

    SCRIPT_FILE="/opt/zapret/init.d/openwrt/custom.d/50-script.sh"
    [ -f "$SCRIPT_FILE" ] || return
    case "$(head -n1 "$SCRIPT_FILE")" in
        *QUIC*) name="50-quic4all" ;;
        *stun*) name="50-stun4all" ;;
        *"discord media"*) name="50-discord-media" ;;
        *"discord subnets"*) name="50-discord" ;;
        *) name="" ;;
    esac

    TCP_VAL=$(awk -F"'" '/option NFQWS_PORTS_TCP/ {print $2}' "$CONF")
    UDP_VAL=$(awk -F"'" '/option NFQWS_PORTS_UDP/ {print $2}' "$CONF")

    echo -e "Версия: ${GREEN}$INSTALLED_VER${NC}"
    echo -e "Статус: $ZAPRET_STATUS"
    echo -e "Скрипт: ${GREEN}$name${NC}"
    echo -e "Порты: TCP: ${GREEN}$TCP_VAL${NC} | UDP: ${GREEN}$UDP_VAL${NC}"

    echo -e "\n${GREEN}===== Стратегия=====${NC}"
    awk '
        /^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/ {sub(/.*'\''/, ""); flag=1; next}
        flag {if (/'\''$/){sub(/'\''$/,""); print; exit} print}
    ' "$CONF"
}

check_sites_async() {
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
genderize.io
"
    sites=($SITES)
    total=${#sites[@]}
    half=$(( (total + 1) / 2 ))

    for idx in $(seq 0 $((half-1))); do
        left=${sites[$idx]}
        right_idx=$((idx + half))
        right=${sites[$right_idx]}

        # асинхронные проверки
        { curl -Is --connect-timeout 3 --max-time 4 "https://$left" >/dev/null 2>&1 && lcol="[${GREEN}OK${NC}]" || lcol="[${RED}FAIL${NC}]"; echo "$lcol $left"; } &
        if [ -n "$right" ]; then
            { curl -Is --connect-timeout 3 --max-time 4 "https://$right" >/dev/null 2>&1 && rcol="[${GREEN}OK${NC}]" || rcol="[${RED}FAIL${NC}]"; echo "$rcol $right"; } &
        fi
    done
    wait
}

# ===== Сбор информации =====
echo -e "\n${GREEN}===== Информация о системе =====${NC}"
MODEL=$(cat /tmp/sysinfo/model)
eval "$(awk -F= '/DISTRIB_(TARGET|ARCH|DESCRIPTION)/ {
    gsub(/'\''/, "", $2);
    if ($1=="DISTRIB_TARGET") t=$2;
    if ($1=="DISTRIB_ARCH") a=$2;
    if ($1=="DISTRIB_DESCRIPTION"){ gsub(/OpenWrt /,"",$2); o=$2 }
} END {print "TARGET=" t "\nARCH=" a "\nOWRT=" o}' /etc/openwrt_release)"

echo -e "Роутер: ${GREEN}$MODEL${NC}"
echo -e "Архитектура: ${GREEN}$ARCH${NC} | ${GREEN}$TARGET${NC}"
echo -e "OpenWrt: ${GREEN}$OWRT${NC}"

echo -e "\n${GREEN}===== Пользовательские пакеты =====${NC}"
awk '/^Package:/ {p=$2} /^Status: install user/ {print p}' /usr/lib/opkg/status

# ===== Flow Offloading =====
echo -e "\n${GREEN}===== Flow Offloading =====${NC}"
sw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)
grep -q 'ct original packets ge 30' /usr/share/firewall4/templates/ruleset.uc 2>/dev/null \
    && dpi="${RED}yes${NC}" || dpi="${GREEN}no${NC}"

if [ "$hw" = "1" ]; then
    out="HW: ${RED}on${NC}"
elif [ "$sw" = "1" ]; then
    out="SW: ${RED}on${NC}"
else
    out="SW: ${GREEN}off${NC} | HW: ${GREEN}off${NC}"
fi
echo -e "$out | FIX: $dpi"

# ===== Проверка GitHub =====
echo -e "\n${GREEN}===== Проверка GitHub =====${NC}"
RATE_OUT=$(get_rate)
echo -n "GitHub IPv4: "; chk_github 4
echo -n "  IPv6: "; chk_github 6
echo -n "GitHub API: "; chk_api && echo -e "${GREEN}ok${NC}    Остаток: $RATE_OUT" || echo -e "${RED}fail${NC}   Остаток: $RATE_OUT"

# ===== Настройки запрета =====
[ -f /etc/init.d/zapret ] && zpr_info

# ===== Доступность сайтов =====
check_sites_async
