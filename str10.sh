#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

: > "$RESULTS"

# перебор блоков
grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do
    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s {print $1; exit}')
    
    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    echo -e "\nПрименяем стратегию:"
    cat "$TEMP_FILE"

    # используем временный файл, чтобы вставить блок в конфиг
    # сначала создаём новый конфиг с заменой
    awk -v block="$(cat "$TEMP_FILE")" '
        BEGIN{inside=0}
        /option NFQWS_OPT '\''/ {print "	option NFQWS_OPT '\''\n" block "\n'\''"; inside=1; next}
        /^'\''$/ && inside==1 {inside=0; next}
        {if(!inside) print}
    ' "$CONF" > "${CONF}.tmp"

    mv "${CONF}.tmp" "$CONF"

    # рестарт Zapret
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1

    # проверка сайтов
    OK=0
    TOTAL=0
    for URL in $TEST_SITES; do
        TOTAL=$((TOTAL+1))
        if curl -k -s --connect-timeout 5 --max-time 8 https://$URL >/dev/null; then
            OK=$((OK+1))
        fi
    done

    echo "$OK/$TOTAL" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done
