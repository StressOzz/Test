#!/bin/sh

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
RESULTS="/tmp/zapret_bench.txt"

ZAPRET_RESTART () { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1; }

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

URLS=$(cat <<EOF
https://gosuslugi.ru
https://esia.gosuslugi.ru
https://nalog.ru
https://lkfl2.nalog.ru
https://rutube.ru
https://youtube.com
https://instagram.com
https://rutor.info
https://ntc.party
https://rutracker.org
https://epidemz.net.co
https://nnmclub.to
https://openwrt.org
https://sxyprn.net
https://spankbang.com
https://pornhub.com
https://discord.com
https://x.com
https://filmix.my
https://flightradar24.com
https://cdn77.com
https://play.google.com
https://genderize.io
https://ottai.com
EOF
)

: > "$RESULTS"

echo "$URLS" | wc -l > /tmp/z_total
TOTAL=$(cat /tmp/z_total)

########################################
# перебор стратегий
########################################

grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do

    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s{print;exit}')

    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    BLOCK=$(cat "$TEMP_FILE")
    NAME=$(head -n1 "$TEMP_FILE")

    ########################################
    # вставка блока
    ########################################

    awk -v block="$BLOCK" '
        BEGIN{skip=0}
        /option NFQWS_OPT '\''/ {
            print "\toption NFQWS_OPT '\''"
            print block
            print "'\''"
            skip=1
            next
        }
        skip && /^'\''$/ { skip=0; next }
        !skip { print }
    ' "$CONF" > "${CONF}.tmp"

    mv "${CONF}.tmp" "$CONF"

    ZAPRET_RESTART

    ########################################
    # проверка сайтов
    ########################################

    OK=0

    echo
    echo -e "${YELLOW}${NAME}${NC}"

    while read URL; do
        if curl -Is --connect-timeout 3 --max-time 4 "$URL" >/dev/null 2>&1; then
            echo -e "${GREEN}$URL → OK${NC}"
            OK=$((OK+1))
        else
            echo -e "${RED}$URL → FAIL${NC}"
        fi
    done <<EOF
$URLS
EOF

    if [ "$OK" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$OK" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi

    echo -e "${COLOR}Доступно: $OK/$TOTAL${NC}"

    echo "$OK $NAME" >> "$RESULTS"

done

########################################
# топ 5
########################################

echo
echo -e "${YELLOW}Топ-5 стратегий:${NC}"

sort -rn "$RESULTS" | head -5 | while read COUNT NAME; do
    if [ "$COUNT" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$COUNT" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi
    echo -e "${COLOR}${NAME} → $COUNT/$TOTAL${NC}"
done
