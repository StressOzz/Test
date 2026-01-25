#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

# очистка предыдущих результатов
: > "$RESULTS"

# находим все линии с # и их позиции
grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do
    # находим следующую строку с #
    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s {print $1; exit}')
    
    if [ -z "$NEXT" ]; then
        # если следующего # нет, берём до конца файла
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        # берём от текущего # до предыдущей строки перед следующим #
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    # читаем блок из временного файла
    BLOCK=$(cat "$TEMP_FILE")

    echo -e "\nПрименяем стратегию:\n$BLOCK"

    # вставляем блок полностью в конфиг между option NFQWS_OPT ' и '
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$BLOCK\n'" "$CONF"

    # рестарт Zapret
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 5  # даём время подняться

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

# вывод топ-5 лучших стратегий с полными блоками
echo -e "\nТоп-5 лучших стратегий:"
awk 'BEGIN{ORS="\n\n"} {if($0 ~ /^[0-9]+\//){score=$0; getline; block=$0; print score "\n" block}}' "$RESULTS" | sort -rn | head -20
