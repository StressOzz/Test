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

echo -e "\n${GREEN}===== 50000-50099 в стратегии и портах =====${NC}"

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


echo -e "\n${GREEN}===== порты =====${NC}"

echo "TCP:"
grep -E "^[[:space:]]*option[[:space:]]+NFQWS_PORTS_TCP[[:space:]]+'" "$CONF" \
    | sed -nE "s/^[[:space:]]*option[[:space:]]+NFQWS_PORTS_TCP[[:space:]]+'([^']*)'.*/\1/p"

echo "UDP:"
grep -E "^[[:space:]]*option[[:space:]]+NFQWS_PORTS_UDP[[:space:]]+'" "$CONF" \
    | sed -nE "s/^[[:space:]]*option[[:space:]]+NFQWS_PORTS_UDP[[:space:]]+'([^']*)'.*/\1/p"




echo -e "\n${GREEN}===== стратегия =====${NC}"
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
