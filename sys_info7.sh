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

echo -e "\n${GREEN}===== 50000-50099 в стратегии =====${NC}"

# Проверка наличия filter-udp=50000-50099
if grep -q "filter-udp=50000-50099" "$CONF"; then
    echo "50000-50099 найден"
else
    echo "50000-50099 отсутствует"
fi

echo ""


echo -e "\n${GREEN}===== порты =====${NC}"


TCP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")

UDP_VAL=$(grep -E "^[[:space:]]*option NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
    | sed "s/.*'\(.*\)'.*/\1/")

echo "TCP: $TCP_VAL    UDP: $UDP_VAL"





echo -e "\n${GREEN}===== стратегия =====${NC}"
awk '
/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/ {flag=1; sub(/^[[:space:]]*option[[:space:]]+NFQWS_OPT[[:space:]]*'\''/, ""); next}
flag {
    if (/'\''/) {sub(/'\''$/, ""); print; exit}
    print
}' "$CONF"



echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
