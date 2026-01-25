#!/bin/sh

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
RESULTS="/tmp/zapret_bench.txt"

ZAPRET_RESTART () { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1; }

# цвета
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

# список сайтов
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

# перебор блоков стратегий
grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do
    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s {print $1; exit}')

    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    BLOCK=$(cat "$TEMP_FILE")
    BLOCK_NAME=$(echo "$BLOCK" | head -n1)

    # вставка блока в конфиг
    awk -v block="$BLOCK" '
        BEGIN{inside=0}
        /option NFQWS_OPT '\''/ {print "	option NFQWS_OPT '\''\n" block "\n'\''"; inside=1; next}
        /^'\''$/ && inside==1 {inside=0; next}
        {if(!inside) print}
    ' "$CONF" > "${CONF}.tmp"
    mv "${CONF}.tmp" "$CONF"

    ZAPRET_RESTART

    # проверка сайтов
    OK=0
    TOTAL=$(echo "$URLS" | wc -l)

    echo -e "\n${YELLOW}${BLOCK_NAME}${NC}"

    while read URL; do
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 3 --max-time 3 "$URL")
        if [ "$HTTP_CODE" = "200" ]; then
            echo -e "${GREEN}$URL → OK${NC}"
            OK=$((OK+1))
        else
            echo -e "${RED}$URL → FAIL${NC}"
        fi
    done <<EOF
$URLS
EOF

    # вывод доступности блока
    if [ "$OK" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$OK" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi

    echo -e "${COLOR}Доступно: $OK/$TOTAL${NC}"

    # сохраняем результат
    echo -e "$OK/$TOTAL\n$BLOCK_NAME" >> "$RESULTS"
done

# вывод топ-5 стратегий
echo -e "\n${YELLOW}Топ-5 стратегий:${NC}"
sort -rn "$RESULTS" | head -10 | while read LINE; do
    if [ $(echo "$LINE" | grep -q '/' && echo 1 || echo 0) -eq 1 ]; then
        COUNT_LINE="$LINE"
    else
        BLOCK_NAME_LINE="$LINE"
        # определяем цвет
        OK=$(echo "$COUNT_LINE" | cut -d'/' -f1)
        TOTAL=$(echo "$COUNT_LINE" | cut -d'/' -f2)
        if [ "$OK" -eq "$TOTAL" ]; then
            COLOR="$GREEN"
        elif [ "$OK" -gt 0 ]; then
            COLOR="$YELLOW"
        else
            COLOR="$RED"
        fi
        echo -e "${COLOR}${BLOCK_NAME_LINE} → $COUNT_LINE${NC}"
    fi
done
