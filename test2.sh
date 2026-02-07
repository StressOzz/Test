#!/usr/bin/env bash

CONF="/etc/config/zapret"
TMP_SF="/tmp/zapret_hostbench"
RESULTS="/opt/zapret/tmp/zapret_hostbench.txt"

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"
WHITELIST_URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/list.txt"

PARALLEL=10

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

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

    echo -e "\n${MAGENTA}===== ИТОГ =====${NC}"
    sort -t'/' -k1 -nr "$RESULTS"
}

main
