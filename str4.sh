#!/bin/bash

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEST_SITES="youtube.com google.com github.com discord.com wikipedia.org reddit.com instagram.com microsoft.com openai.com"
RESULTS="/tmp/zapret_bench.txt"

# очистим предыдущие результаты
: > "$RESULTS"

# делим файл на блоки стратегий (от # до следующего #)
awk '
  /^#/ { 
    if (NR != 1) print block; 
    block=$0; 
    next 
  } 
  { block = block "\n" $0 } 
  END { print block }
' "$STR_FILE" | while IFS= read -r STRAT_BLOCK; do
    # вставляем блок стратегии в конфиг между option NFQWS_OPT ' и '
    sed -i "/option NFQWS_OPT '/,/^'/c\	option NFQWS_OPT '\n$STRAT_BLOCK\n'" "$CONF"

    echo -e "\nПрименяем стратегию:\n$STRAT_BLOCK"

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
    echo "$OK/$TOTAL" >> "$RESULTS"
    echo "Доступно: $OK/$TOTAL"
done

# вывод топ-5 лучших стратегий
echo -e "\nТоп-5 лучших стратегий:"
paste -d ' ' <(awk '/^#/{print $0}' "$STR_FILE") "$RESULTS" | sort -rn -k2 | head -5
