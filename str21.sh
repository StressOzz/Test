#!/bin/sh

CONF="/etc/config/zapret"
STR_FILE="/opt/zapret_temp/str_flow.txt"
TEMP_FILE="/opt/str_temp.txt"
RESULTS="/tmp/zapret_bench.txt"

ZAPRET_RESTART () { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1; }

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

URLS=$(cat <<EOF
https://gosuslugi.ru
https://esia.gosuslugi.ru
https://nalog.ru
https://lkfl2.nalog.ru
https://rutube.ru
https://youtube.com
https://instagram.com
https://rutor.info
https://ntc.party
https://rutracker.org
https://epidemz.net.co
https://nnmclub.to
https://openwrt.org
https://sxyprn.net
https://spankbang.com
https://pornhub.com
https://discord.com
https://x.com
https://filmix.my
https://flightradar24.com
https://cdn77.com
https://play.google.com
https://genderize.io
https://ottai.com
https://img.wzstats.gg/cleaver/gunFullDisplay?t=0.8379293615805524
https://genshin.jmp.blue/characters/all
https://api.frankfurter.dev/v1/2000-01-01..2002-12-31?t=0.10086058232485262
https://www.bigcartel.com/?t=0.05350771418326239
https://genderize.io/?t=0.690010399215886
https://genderize.io/?t=0.8043720968884225
https://j.dejure.org/jcg/doctrine/doctrine_banner.webp?t=0.9998959160553804
https://accesorioscelular.com/tienda/css/plugins.css?t=0.21851062503227425
https://251b5cd9.nip.io/1MB.bin?t=0.4002108804473481
https://nioges.com/libs/fontawesome/webfonts/fa-solid-900.woff2?t=0.5863188987474373
https://5fd8bdae.nip.io/1MB.bin?t=0.2578104779291205
https://5fd8bca5.nip.io/1MB.bin?t=0.15580206924030682
https://eu.api.ovh.com/console/rapidoc-min.js?t=0.4173820664969895
https://ovh.sfx.ovh/10M.bin?t=0.8326647985641201
https://oracle.sfx.ovh/10M.bin?t=0.23943050058539272
https://www.getscope.com/assets/fonts/fa-solid-900.woff2?t=0.5476677250009963
https://corp.kaltura.com/wp-content/cache/min/1/wp-content/themes/airfleet/dist/styles/theme.css?t=0.4091857736085579
https://api.usercentrics.eu/gvl/v3/en.json?t=0.9164301389568108
https://www.jetblue.com/footer/footer-element-es2015.js?t=0.3058062700141776
https://www.cnn10.com/?t=0.8325471181626721
https://www.roxio.com/static/roxio/images/products/creator/nxt9/call-action-footer-bg.jpg?t=0.3837369616891504
https://media-assets.stryker.com/is/image/stryker/gateway_1?$max_width_1410$&t=0.6966182400011641
https://cdn.eso.org/images/banner1920/eso2520a.jpg?t=0.5186907385065521
https://bandobaskent.com/logo.png?t=0.9087762933670076
https://www.velivole.fr/img/header.jpg?t=0.7058447082956326
https://cdn.xuansiwei.com/common/lib/font-awesome/4.7.0/fontawesome-webfont.woff2?v=4.7.0&t=0.45608957890091195
https://cdn.amplitude.com/script/fcf83c280a5dc45267f3ade26c5ade4d.experiment.js
EOF
)

: > "$RESULTS"

echo "$URLS" | wc -l > /tmp/z_total
TOTAL=$(cat /tmp/z_total)

########################################
# перебор стратегий
########################################

grep -n '^#' "$STR_FILE" | cut -d: -f1 | while read START; do

    NEXT=$(grep -n '^#' "$STR_FILE" | cut -d: -f1 | awk -v s="$START" '$1>s{print;exit}')

    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$STR_FILE" > "$TEMP_FILE"
    else
        END=$((NEXT-1))
        sed -n "${START},${END}p" "$STR_FILE" > "$TEMP_FILE"
    fi

    BLOCK=$(cat "$TEMP_FILE")
    NAME=$(head -n1 "$TEMP_FILE")

    ########################################
    # вставка блока
    ########################################

    awk -v block="$BLOCK" '
        BEGIN{skip=0}
        /option NFQWS_OPT '\''/ {
            print "\toption NFQWS_OPT '\''"
            print block
            print "'\''"
            skip=1
            next
        }
        skip && /^'\''$/ { skip=0; next }
        !skip { print }
    ' "$CONF" > "${CONF}.tmp"

    mv "${CONF}.tmp" "$CONF"

    ZAPRET_RESTART

    ########################################
    # проверка сайтов
    ########################################

    OK=0

    echo
    echo -e "${YELLOW}${NAME}${NC}"

    while read URL; do
        if curl -Is --connect-timeout 3 --max-time 4 "$URL" >/dev/null 2>&1; then
            echo -e "${GREEN}$URL → OK${NC}"
            OK=$((OK+1))
        else
            echo -e "${RED}$URL → FAIL${NC}"
        fi
    done <<EOF
$URLS
EOF

    if [ "$OK" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$OK" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi

    echo -e "${COLOR}Доступно: $OK/$TOTAL${NC}"

    echo "$OK $NAME" >> "$RESULTS"

done

########################################
# топ 5
########################################

echo
echo -e "${YELLOW}Топ-5 стратегий:${NC}"

sort -rn "$RESULTS" | head -5 | while read COUNT NAME; do
    if [ "$COUNT" -eq "$TOTAL" ]; then
        COLOR="$GREEN"
    elif [ "$COUNT" -gt 0 ]; then
        COLOR="$YELLOW"
    else
        COLOR="$RED"
    fi
    echo -e "${COLOR}${NAME} → $COUNT/$TOTAL${NC}"
done
