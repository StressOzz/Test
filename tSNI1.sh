#!/bin/sh

CONF="/etc/config/zapret"
TMP_SF="/tmp/zapret_hostbench"
RESULTS="/opt/zapret/tmp/zapret_hostbench.txt"

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/refs/heads/main/ru/tcp-16-20/suite.json"
WHITELIST_URL="https://raw.githubusercontent.com/hxehex/russia-mobile-internet-whitelist/refs/heads/main/whitelist.txt"
#  WHITELIST_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/sni.txt"

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

    if curl -sL --connect-timeout 2 --max-time 3 --speed-time 3 --speed-limit 1 --range 0-65535 -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) curl/8.0" -o /dev/null "$LINK" >/dev/null 2>&1; then
        echo 1 >> "$TMP_OK"
        echo -e "${GREEN}[ OK ]${NC} $TEXT"
    else
        echo -e "${RED}[FAIL]${NC} $TEXT"
    fi
}

check_url() {
    TEXT="${1%%|*}"
    LINK="${1##*|}"

    TSIZE=65536
    TMP_BASE="$TMP_SF/test.$$.$RANDOM"

    curl -4 -s \
        --connect-timeout 3 \
        --max-time 5 \
        --speed-time 3 \
        --speed-limit 1 \
        --range 0-$((TSIZE-1)) \
        -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) curl/8.12" \
        -D "$TMP_BASE.hdr" \
        -o "$TMP_BASE.body" \
        "$LINK" >/dev/null 2>&1

    SIZE=0
    [ -f "$TMP_BASE.body" ] && SIZE=$(wc -c < "$TMP_BASE.body" 2>/dev/null)

    if [ -s "$TMP_BASE.hdr" ] && [ "$SIZE" -ge "$TSIZE" ]; then
        echo 1 >> "$TMP_OK"
        echo -e "${GREEN}[ OK ]${NC} $TEXT"
    else
        echo -e "${RED}[FAIL]${NC} $TEXT"
    fi

    rm -f "$TMP_BASE.hdr" "$TMP_BASE.body"
}

main() {

    mkdir -p "$TMP_SF"
    : > "$RESULTS"

    echo -e "${CYAN}Загрузка DPI сайтов...${NC}"

curl -fsSL "$RAW" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*"url":[[:space:]]*"\([^"]*\)".*/\1|\2/p' > "$TMP_SF/dpi.txt"

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
