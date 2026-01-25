#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

: > "$RESULTS"

# читаем файл блоками: от # до следующего #
awk 'BEGIN{RS="^#"; ORS=""} NR>1{print "#" $0 "\n"}' "$STR_FILE" | while IFS= read -r BLOCK; do
    # убираем пустые блоки
    [ -z "$BLOCK" ] && continue

    echo -e "\nПрименяем стратегию:\n$BLOCK"

    # вставляем блок полностью в конфиг
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$BLOCK\n'" "$CONF"

    # рестарт Zapret
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 5

    # проверка сайтов
    OK=0
    TOTAL=0
    for URL in $TEST_SITES; do
        TOTAL=$((TOTAL+1))
        if curl -k -s --connect-timeout 5 --max-time 8 https://$URL >/dev/null; then
            OK=$((OK+1))
        fi
    done

    # сохраняем результат
    echo -e "$OK/$TOTAL\n$BLOCK\n" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий с блоками
echo -e "\nТоп-5 лучших стратегий:"
awk 'BEGIN{ORS="\n\n"} {if($0 ~ /^[0-9]+\//){score=$0; getline; block=$0; print score "\n" block}}' "$RESULTS" | sort -rn | head -20
