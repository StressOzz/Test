#!/usr/bin/env bash

CONF="/etc/config/zapret"
TMP_SF="/tmp/zapret_SNI_test_tmp"
RESULTS="/opt/zapret/tmp/zapret_SNI_test.txt"

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"
WHITELIST_URL="https://raw.githubusercontent.com/StressOzz/test/refs/heads/main/list.txt"

PARALLEL=10

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

check_host_line() {
if ! grep -q -- "--dpi-desync-hostfakesplit-mod=host=" "$CONF"; then
    echo -e "${RED}Стратегия не подходит!$CONF${NC}"
    exit 1
fi
}


ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh 2>/dev/null
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1
}

show_host_results() {
    clear
    echo -e "${MAGENTA}Результат тестирования host=${NC}\n"

    TOTAL=$(head -n1 "$RESULTS" | cut -d'/' -f2)

    sort -nr -k3 "$RESULTS" | while read -r line; do
        COUNT=$(echo "$line" | awk -F'[ /]' '{print $(NF-1)}')

        if [ "$COUNT" -eq "$TOTAL" ]; then
            COLOR="$GREEN"
        elif [ "$COUNT" -ge $((TOTAL/2)) ]; then
            COLOR="$YELLOW"
        else
            COLOR="$RED"
        fi

        echo -e "${COLOR}${line}${NC}"
    done

    echo -e "\n${GREEN}Файл результатов:${NC} $RESULTS\n"
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
    PIDS=()

    while IFS= read -r U; do
        (
            # проверка с таймаутом 5 сек
            if curl -sL --connect-timeout 1 --max-time 5 --speed-time 3 --speed-limit 1 -o /dev/null "$U" >/dev/null 2>&1; then
                echo 1 >> "$TMP_OK"
                echo -e "${GREEN}[ OK ]${NC} $U"
            else
                echo -e "${RED}[FAIL]${NC} $U"
            fi
        ) &

        PIDS+=($!)
        RUN=$((RUN+1))

        if [ "$RUN" -ge "$PARALLEL" ]; then
            wait "${PIDS[@]}"
            RUN=0
            PIDS=()
        fi
    done < "$TMP_SF/dpi.txt"

    # дождаться оставшиеся
    [ ${#PIDS[@]} -gt 0 ] && wait "${PIDS[@]}"

    OK=$(wc -l < "$TMP_OK" | tr -d ' ')
    rm -f "$TMP_OK"
}

main() {

    check_host_line

    mkdir -p "$TMP_SF"
    : > "$RESULTS"

    echo -e "${CYAN}Загрузка DPI сайтов...${NC}"

    curl -fsSL "$RAW" | grep 'url:' | \
    sed -n 's/.*id: "\([^"]*\)".*url: "\([^"]*\)".*/\1|\2/p' > "$TMP_SF/dpi.txt" || {
        echo -e "${RED}Не удалось получить DPI список${NC}"
        exit 1
    }

    URLS="$(cat "$TMP_SF/dpi.txt")"
    TOTAL_URLS=$(grep -c "|" "$TMP_SF/dpi.txt")

    echo -e "${CYAN}DPI сайтов:${NC} $TOTAL_URLS"


    echo -e "${CYAN}Загрузка whitelist...${NC}"

    curl -fsSL "$WHITELIST_URL" > "$TMP_SF/hosts.txt" || exit 1
    TOTAL_HOSTS=$(wc -l < "$TMP_SF/hosts.txt")

    cp "$CONF" "$TMP_SF/conf.bak"

    CUR=0

    while IFS= read -r HOST; do
        [ -z "$HOST" ] && continue

        CUR=$((CUR+1))

        echo -e "\n${CYAN}[$CUR/$TOTAL_HOSTS] host=${YELLOW}$HOST${NC}"

        cp "$TMP_SF/conf.bak" "$CONF"

        sed -i "s|--dpi-desync-hostfakesplit-mod=host=.*|--dpi-desync-hostfakesplit-mod=host=$HOST|" "$CONF"

        ZAPRET_RESTART

        check_all_urls

        if [ "$OK" -eq "$TOTAL_URLS" ]; then
            COLOR="$GREEN"
        elif [ "$OK" -ge $((TOTAL_URLS/2)) ]; then
            COLOR="$YELLOW"
        else
            COLOR="$RED"
        fi

        echo -e "${CYAN}Результат:${NC} ${COLOR}$OK/$TOTAL_URLS${NC}"
        echo "$HOST → $OK/$TOTAL_URLS" >> "$RESULTS"

    done < "$TMP_SF/hosts.txt"


    mv "$TMP_SF/conf.bak" "$CONF"
    ZAPRET_RESTART

    show_host_results
}

main
