#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

# очистим предыдущие результаты
: > "$RESULTS"

# читаем стратегии от # до следующего #
awk '/^#/{if (s!="") print s; s=$0; next} {s=s"\n"$0} END{print s}' "$STR_FILE" | while read -r -d $'\n' STRAT_BLOCK; do
    echo -e "\nПрименяем стратегию:\n$STRAT_BLOCK"

    # вставляем стратегию в конфиг между option NFQWS_OPT ' и '
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$STRAT_BLOCK\n'" "$CONF"

    # рестарт Zapret
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1  # даём время подняться

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
    echo "$OK/$TOTAL $STRAT_BLOCK" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий
echo -e "\nТоп-5 лучших стратегий:"
sort -rn "$RESULTS" | head -5 | while read RES STR; do
    echo "$RES → $STR"
done
