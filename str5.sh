#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

# очистим предыдущие результаты
: > "$RESULTS"

# читаем блоки стратегий: от # до следующего #
# awk разделяет блоки по строкам, начинающимся с #
awk '
  /^#/ { 
    if (NR != 1) print block; 
    block=$0; 
    next 
  } 
  { block = block "\n" $0 } 
  END { print block }
' "$STR_FILE" | while IFS= read -r STRAT_BLOCK; do

    # пропускаем пустые блоки
    [ -z "$STRAT_BLOCK" ] && continue

    echo -e "\nПрименяем стратегию:\n$STRAT_BLOCK"

    # вставляем блок стратегии в конфиг полностью
    # между option NFQWS_OPT ' и '
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$STRAT_BLOCK\n'" "$CONF"

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
    echo -e "$OK/$TOTAL\n$STRAT_BLOCK\n" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий
echo -e "\nТоп-5 лучших стратегий:"
# сортируем по числу доступных сайтов
awk 'NR%6==1{score=$1; getline; print score, $0}' "$RESULTS" | sort -rn | head -5
