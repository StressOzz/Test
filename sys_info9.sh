#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
DGRAY="\033[38;5;236m"
clear
##########################################################################################################################
CONF="/etc/config/zapret"
echo -e "${GREEN}===== Модель и архитектура роутера =====${NC}"
cat /tmp/sysinfo/model
awk -F= '
/DISTRIB_ARCH/   { gsub(/'\''/, ""); print $2 }
/DISTRIB_TARGET/ { gsub(/'\''/, ""); print $2 }
' /etc/openwrt_release
echo -e "\n${GREEN}===== Версия OpenWrt =====${NC}"
awk -F= '
/DISTRIB_DESCRIPTION/ {
gsub(/'\''|OpenWrt /, "")
print $2
}
' /etc/openwrt_release
echo -e "\n${GREEN}===== Пользовательские пакеты =====${NC}"
awk '
/^Package:/ { p=$2 }
/^Status: install user/ { print p }
' /usr/lib/opkg/status
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
echo -e "\n${GREEN}===== Настройки запрет =====${NC}"
INSTALLED_VER=$(opkg list-installed | grep '^zapret ' | awk '{print $3}')
if /etc/init.d/zapret status 2>/dev/null | grep -qi "running"; then
ZAPRET_STATUS="${GREEN}запущен${NC}"
else
ZAPRET_STATUS="${RED}остановлен${NC}"
fi
SCRIPT_FILE="/opt/zapret/init.d/openwrt/custom.d/50-script.sh"
[ -f "$SCRIPT_FILE" ] || return
line=$(head -n1 "$SCRIPT_FILE")
case "$line" in
*QUIC*) name="50-quic4all" ;;
*stun*) name="50-stun4all" ;;
*"discord media"*) name="50-discord-media" ;;
*"discord subnets"*) name="50-discord" ;;
*) name="" ;;
esac
echo -e "Версия: ${GREEN}$INSTALLED_VER${NC}"
echo -e "Статус: $ZAPRET_STATUS"
echo -e "Скрипт: ${GREEN}${NC}$name"



echo -e "\n${GREEN}===== Стратегия и порты=====${NC}"
TCP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
UDP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
echo -e "TCP: ${GREEN}$TCP_VAL${NC}    UDP: ${GREEN}$UDP_VAL${NC}\n"

awk '
/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/ {flag=1; sub(/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/, ""); next}
flag {
    if (/'\''/) {sub(/'\''$/, ""); print; exit}
    print
}' "$CONF"

TCP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
UDP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
echo -e "\nTCP: ${GREEN}$TCP_VAL${NC}    UDP: ${GREEN}$UDP_VAL${NC}\n"


echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
