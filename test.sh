#!/bin/sh

CONF="/etc/config/zapret"
TMP_SF="/tmp/zapret_hostbench"
RESULTS="/opt/zapret/tmp/zapret_hostbench.txt"

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.json"

PARALLEL=10

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

show_test_results() {
    clear
    echo -e "${MAGENTA}Результат тестирования стратегий${NC}\n"
    [ ! -f "$RESULTS" ] || [ ! -s "$RESULTS" ] && { echo -e "${RED}Результат не найден!${NC}\n"; return; }
    TOTAL=$(head -n1 "$RESULTS" | cut -d'/' -f2)
    sort -nr -k1,1 <(awk -F'[/ ]' '{for(i=1;i<=NF;i++) if($i~/^[0-9]+$/){print $i "/" $(i+1), $0; break}}' "$RESULTS") | while read -r line
    do
        COUNT=$(echo "$line" | awk -F'/' '{print $1}')
        TEXT=$(echo "$line" | cut -d' ' -f2-)
        if [[ "$TEXT" =~ Zapret ]]; then
            COLOR="$CYAN"
        elif [ "$COUNT" -eq "$TOTAL" ]; then
            COLOR="$GREEN"
        elif [ "$COUNT" -gt $((TOTAL/2)) ]; then
            COLOR="$YELLOW"
        else
            COLOR="$RED"
        fi
        echo -e "${COLOR}${TEXT}${NC}"
    done
    echo
}

ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh 2>/dev/null
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1
}

check_url() {
    TEXT="${1%%|*}"
    LINK="${1##*|}"

    if curl -sL --connect-timeout 1 --max-time 2 --speed-time 2 --speed-limit 1 -o /dev/null "$LINK" >/dev/null 2>&1; then
        echo 1 >> "$TMP_OK"
        echo -e "${GREEN}[ OK ]${NC} $TEXT"
    else
        echo -e "${RED}[FAIL]${NC} $TEXT"
    fi
}

check_all_urls() {
    TMP_OK="$TMP_SF/ok.$$"
    : > "$TMP_OK"

    RUN=0

    while IFS= read -r U; do
        check_url "$U" &
        RUN=$((RUN+1))

        if [ "$RUN" -ge "$PARALLEL" ]; then
            wait
            RUN=0
        fi
    done < "$TMP_SF/dpi.txt"

    wait

    OK=$(wc -l < "$TMP_OK" | tr -d ' ')
    rm -f "$TMP_OK"
}

main() {

    mkdir -p "$TMP_SF"
    : > "$RESULTS"

    echo -e "${CYAN}Загрузка DPI сайтов...${NC}"

    curl -fsSL "$RAW" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*"url":[[:space:]]*"\([^"]*\)".*/\1|\2/p' > "$TMP_SF/dpi.txt"

    TOTAL_URLS=$(grep -c "|" "$TMP_SF/dpi.txt")
    echo -e "${CYAN}DPI сайтов:${NC} $TOTAL_URLS"

    # --- создаем резервную копию конфига ---
    cp "$CONF" "$TMP_SF/conf.bak"

    CUR=0

    # --- бесконечный цикл ---
    while true; do
        CUR=$((CUR+1))
        
        # Генерация случайной длины от 1 до 15
        LEN=$((1 + RANDOM % 15))
        
        # Генерация STUN-паттерна
        STUN_PATTERN=""
        for j in $(seq 1 $LEN); do
            BYTE=$((RANDOM % 256))
            HEX=$(printf "%02x" $BYTE)
            STUN_PATTERN="${STUN_PATTERN}x${HEX}"
        done

        echo -e "\n${CYAN}[$CUR] STUN=${YELLOW}$STUN_PATTERN${NC}"

        # Восстанавливаем конфиг
        cp "$TMP_SF/conf.bak" "$CONF"

        # Подставляем в конфиг
        sed -i "s|--dpi-desync-split-seqovl-pattern=.*|--dpi-desync-split-seqovl-pattern=$STUN_PATTERN|" "$CONF"
        sed -i "s|--dpi-desync-fake-tls=.*|--dpi-desync-fake-tls=$STUN_PATTERN|" "$CONF"

        # Перезапуск zapret
        ZAPRET_RESTART

        # Проверка сайтов
        check_all_urls

        # Цвет результата
        if [ "$OK" -eq "$TOTAL_URLS" ]; then
            COLOR="$GREEN"
        elif [ "$OK" -ge $((TOTAL_URLS/2)) ]; then
            COLOR="$YELLOW"
        else
            COLOR="$RED"
        fi

        echo -e "${CYAN}Результат:${NC} ${COLOR}$OK/$TOTAL_URLS${NC}"
        echo "$STUN_PATTERN → $OK/$TOTAL_URLS" >> "$RESULTS"
    done
}

main
