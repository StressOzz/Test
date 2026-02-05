#!/bin/sh

########################################
# переменные
########################################

CONF="/etc/config/zapret"
TMP_SF="/tmp/zapret_hostbench"
RESULTS="/opt/zapret/tmp/zapret_hostbench.txt"

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"

PARALLEL=8

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

########################################
# ТВОЙ список хостов (локально)
########################################

HOSTS_LIST="
tile4.maps.2gis.com
i2.photo.2gis.com
alpha4.minigames.mail.ru
cobma.mail.ru
five.predict.mail.ru
knights.mail.ru
pp.mail.ru
townwars.mail.ru
m.ok.ru
www.rzd.ru
keys.api.2gis.com
api.photo.2gis.com
filekeeper-vod.2gis.com
i1.photo.2gis.com
i3.photo.2gis.com
i7.photo.2gis.com
i8.photo.2gis.com
i9.photo.2gis.com
catalog.api.2gis.com
sntr.avito.ru
s0.bss.2gis.com
"

########################################
# функции
########################################

ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh 2>/dev/null
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
    sleep 1
}

check_url() {
    TEXT=$(echo "$1" | cut -d"|" -f1)
    LINK=$(echo "$1" | cut -d"|" -f2)

    if curl -sL --connect-timeout 3 --max-time 5 -o /dev/null "$LINK" >/dev/null 2>&1; then
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

    printf "%s\n" "$URLS" | while read U; do
        check_url "$U" &
        RUN=$((RUN+1))
        [ "$RUN" -ge "$PARALLEL" ] && { wait; RUN=0; }
    done

    wait
    OK=$(wc -l < "$TMP_OK" | tr -d ' ')
    rm -f "$TMP_OK"
}

########################################
# main
########################################

mkdir -p "$TMP_SF"
: > "$RESULTS"

echo -e "${CYAN}Загрузка DPI сайтов...${NC}"

curl -fsSL "$RAW" | grep 'url:' | \
sed -n 's/.*id: "\([^"]*\)".*url: "\([^"]*\)".*/\1|\2/p' > "$TMP_SF/dpi.txt" || exit 1

URLS="$(cat "$TMP_SF/dpi.txt")"
TOTAL_URLS=$(grep -c "|" "$TMP_SF/dpi.txt")

echo -e "${CYAN}DPI сайтов:${NC} $TOTAL_URLS"

cp "$CONF" "$TMP_SF/conf.bak"

TOTAL_HOSTS=$(printf "%s\n" "$HOSTS_LIST" | grep -c .)

CUR=0

printf "%s\n" "$HOSTS_LIST" | while read HOST; do

    [ -z "$HOST" ] && continue

    CUR=$((CUR+1))

    echo -e "\n${CYAN}[$CUR/$TOTAL_HOSTS] host=${YELLOW}$HOST${NC}"

    cp "$TMP_SF/conf.bak" "$CONF"

    sed -i "s|--dpi-desync-hostfakesplit-mod=host=.*|--dpi-desync-hostfakesplit-mod=host=$HOST|" "$CONF"

    ZAPRET_RESTART

    check_all_urls

    echo "$HOST → $OK/$TOTAL_URLS" >> "$RESULTS"
    echo -e "${CYAN}Результат:${NC} $OK/$TOTAL_URLS"

done

mv "$TMP_SF/conf.bak" "$CONF"
ZAPRET_RESTART

echo -e "\n${MAGENTA}===== ИТОГ =====${NC}"
sort -t'/' -k1 -nr "$RESULTS"
