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

FAKE_TLS="$TMP_SF/clienthello.bin"

# ===== TLS GENERATOR =====
generate_tls() {

    # 32 байта random
    RAND=$(hexdump -n 32 -e '1/1 "%02x"' /dev/urandom)

    # случайные cipher suites (4 штуки)
    CIPHERS=""
    for i in 1 2 3 4; do
        C=$(printf "%04x" $((RANDOM % 65535)))
        CIPHERS="${CIPHERS}${C}"
    done

    CIPHER_LEN=$(printf "%04x" $(( ${#CIPHERS} / 2 )))

    BODY="0303"              # TLS 1.2
    BODY="${BODY}${RAND}"
    BODY="${BODY}00"         # session id len
    BODY="${BODY}${CIPHER_LEN}"
    BODY="${BODY}${CIPHERS}"
    BODY="${BODY}01"         # compression len
    BODY="${BODY}00"
    BODY="${BODY}0000"       # no extensions

    BODY_LEN=$(printf "%06x" $(( ${#BODY} / 2 )))

    HANDSHAKE="01${BODY_LEN}${BODY}"

    RECORD_LEN=$(printf "%04x" $(( ${#HANDSHAKE} / 2 )))

    TLS="160301${RECORD_LEN}${HANDSHAKE}"

    echo "$TLS" | xxd -r -p > "$FAKE_TLS"
}

# ===== RESTART =====
ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh 2>/dev/null
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1
}

# ===== URL CHECK =====
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

# ===== MAIN =====
main() {

    mkdir -p "$TMP_SF"
    : > "$RESULTS"

    echo -e "${CYAN}Загрузка DPI сайтов...${NC}"

    curl -fsSL "$RAW" | sed -n 's/.*"id":[[:space:]]*"\([^"]*\)".*"url":[[:space:]]*"\([^"]*\)".*/\1|\2/p' > "$TMP_SF/dpi.txt"

    TOTAL_URLS=$(grep -c "|" "$TMP_SF/dpi.txt")
    echo -e "${CYAN}DPI сайтов:${NC} $TOTAL_URLS"

    cp "$CONF" "$TMP_SF/conf.bak"

    ITER=0

    while true; do
        ITER=$((ITER+1))

        echo -e "\n${CYAN}[$ITER] Генерация TLS ClientHello...${NC}"

        generate_tls

        cp "$TMP_SF/conf.bak" "$CONF"

        sed -i "s|--dpi-desync-fake-tls=.*|--dpi-desync-fake-tls=$FAKE_TLS|" "$CONF"

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
        echo "ITER $ITER → $OK/$TOTAL_URLS" >> "$RESULTS"
    done
}

main
