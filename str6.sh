#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

# очистка предыдущих результатов
: > "$RESULTS"

# читаем весь файл и разбиваем на блоки от # до следующего #
awk 'BEGIN{RS=""; ORS="\n\n"} /^#/{print $0}' "$STR_FILE" | while IFS= read -r STRAT_BLOCK; do
    # убираем пустые блоки
    [ -z "$STRAT_BLOCK" ] && continue

    echo -e "\nПрименяем стратегию:\n$STRAT_BLOCK"

    # вставка блока стратегии в конфиг полностью
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$STRAT_BLOCK\n'" "$CONF"

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

    # сохраняем результат (с полным блоком)
    echo -e "$OK/$TOTAL\n$STRAT_BLOCK\n" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий с полными блоками
echo -e "\nТоп-5 лучших стратегий:"
awk 'BEGIN{ORS="";} {if($0 ~ /^[0-9]+\//){score=$0; getline; block=$0; print score "\n" block "\n\n";}}' "$RESULTS" | sort -rn | head -20
