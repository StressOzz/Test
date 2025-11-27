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
echo -e "$INSTALLED_VER"
echo -e "$ZAPRET_STATUS"
echo -e "$name"



echo -e "\n${GREEN}===== порты и стратегия =====${NC}"
TCP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
UDP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")
echo "TCP: ${GREEN}$TCP_VAL${NC}    UDP: ${GREEN}$UDP_VAL${NC}\n"

awk '
/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/ {flag=1; sub(/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/, ""); next}
flag {
    if (/'\''/) {sub(/'\''$/, ""); print; exit}
    print
}' "$CONF"



echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
