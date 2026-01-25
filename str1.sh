#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="gosuslugi.ru youtube.com instagram.com rutor.info ntc.party rutracker.org epidemz.net.co nnmclub.to"
RESULTS="/tmp/zapret_bench.txt"

# очистим предыдущие результаты
: > "$RESULTS"

# читаем файл стратегий, каждая стратегия начинается с #
grep '^#' "$STR_FILE" | while read STRAT; do
    echo -e "\nПрименяем стратегию: $STRAT"

    # вставляем стратегию в конфиг
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$STRAT\n'" "$CONF"

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
    echo "$OK/$TOTAL $STRAT" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий
echo -e "\nТоп-5 лучших стратегий:"
sort -rn "$RESULTS" | head -5 | while read RES STR; do
    echo "$RES → $STR"
done
