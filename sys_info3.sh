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

echo -e "\n${GREEN}===== 50000-50099 =====${NC}"

# Проверка наличия filter-udp=50000-50099
if grep -q "filter-udp=50000-50099" "$CONF"; then
    echo "filter-udp найден"
else
    echo "filter-udp отсутствует"
fi

# Проверка наличия 50000-50099 именно в строке option NFQWS_PORTS_UDP
if grep -E "^\\s*option NFQWS_PORTS_UDP" "$CONF" | grep -q "50000-50099"; then
    echo "диапазон в NFQWS_PORTS_UDP найден"
else
    echo "диапазон в NFQWS_PORTS_UDP отсутствует"
fi

echo ""


echo -e "\n${GREEN}===== стратегия и порты =====${NC}"
CONF="/etc/config/zapret"

CONF="/etc/config/zapret"

echo "UDP:"
grep -E "^[[:space:]]*option NFQWS_PORTS_UDP" "$CONF" \
    | sed -nE "s/.*'([^']*)'.*/\1/p"

echo "TCP:"
grep -E "^[[:space:]]*option NFQWS_PORTS_TCP" "$CONF" \
    | sed -nE "s/.*'([^']*)'.*/\1/p"






sed -n "
/^[[:space:]]*option[[:space:]]\\+NFQWS_OPT[[:space:]]*'/,/'/{
    /^[[:space:]]*option[[:space:]]\\+NFQWS_OPT[[:space:]]*'/{
        s/^[[:space:]]*option[[:space:]]\\+NFQWS_OPT[[:space:]]*'//; t pr
        d
    }
    /'/{
        s/'$//; p; q
    }
    :pr
    p
}
" "$CONF"




echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
