#!/bin/sh

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
RESULTS="/tmp/zapret_bench.txt"

ZAPRET_RESTART () { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1; }

# цвета
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

# список сайтов как текстовый блок
URLS=$(cat <<EOF
https://img.wzstats.gg/cleaver/gunFullDisplay
https://genshin.jmp.blue/characters/all
https://api.frankfurter.dev/v1/2000-01-01..2002-12-31
https://www.bigcartel.com/
https://genderize.io/
https://j.dejure.org/jcg/doctrine/doctrine_banner.webp
https://maps.gnosis.earth/ogcapi/api/swagger-ui/swagger-ui-standalone-preset.js
https://251b5cd9.nip.io/1MB.bin
https://nioges.com/libs/fontawesome/webfonts/fa-solid-900.woff2
https://5fd8bdae.nip.io/1MB.bin
https://5fd8bca5.nip.io/1MB.bin
https://eu.api.ovh.com/console/rapidoc-min.js
https://ovh.sfx.ovh/10M.bin
https://oracle.sfx.ovh/10M.bin
https://www.getscope.com/assets/fonts/fa-solid-900.woff2
https://corp.kaltura.com/wp-content/cache/min/1/wp-content/themes/airfleet/dist/styles/theme.css
https://api.usercentrics.eu/gvl/v3/en.json
https://www.jetblue.com/footer/footer-element-es2015.js
https://www.cnn10.com/
https://www.roxio.com/static/roxio/images/products/creator/nxt9/call-action-footer-bg.jpg
https://media-assets.stryker.com/is/image/stryker/gateway_1?\$max_width=1410\$
https://cdn.eso.org/images/banner1920/eso2520a.jpg
https://airsea.no/images/main_logo.png
https://www.velivole.fr/img/header.jpg
https://cdn.xuansiwei.com/common/lib/font-awesome/4.7.0/fontawesome-webfont.woff2?v=4.7.0
EOF
)

: > "$RESULTS"

# перебор блоков стратегий
grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do
    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s {print $1; exit}')

    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    BLOCK=$(cat "$TEMP_FILE")
    BLOCK_NAME=$(echo "$BLOCK" | head -n1)

    # вставка блока
    awk -v block="$BLOCK" '
        BEGIN{inside=0}
        /option NFQWS_OPT '\''/ {print "	option NFQWS_OPT '\''\n" block "\n'\''"; inside=1; next}
        /^'\''$/ && inside==1 {inside=0; next}
        {if(!inside) print}
    ' "$CONF" > "${CONF}.tmp"
    mv "${CONF}.tmp" "$CONF"

    ZAPRET_RESTART

    # проверка сайтов
    OK=0
    TOTAL=$(echo "$URLS" | wc -l)
    echo "$URLS" | while read URL; do
        HTTP_CODE=$(curl -k -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 "$URL")
        if [ "$HTTP_CODE" = "200" ]; then
            OK=$((OK+1))
        fi
    done

    # вывод результата с цветом
    if [ "$OK" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$OK" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi

    echo -e "${COLOR}${BLOCK_NAME} → Доступно: $OK/$TOTAL${NC}"
    echo "$OK/$TOTAL" >> "$RESULTS"
done
