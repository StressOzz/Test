#!/bin/sh

CONF="/etc/config/zapret"
BACK="/opt/zapret_temp/zapret_back"
STR_FILE="/opt/zapret_temp/str_flow.txt"       # исходный файл — не трогаем
WORK_FILE="/opt/zapret_temp/str_work.txt"     # рабочий файл для перебора
TEMP_FILE="/opt/zapret_temp/str_temp.txt"
RESULTS="/opt/zapret_temp/zapret_bench.txt"
TMP_SF="/opt/zapret_temp"
ZIP="$TMP_SF/repo.zip"

PARALLEL=9

RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
NC="\e[0m"

ZAPRET_RESTART () {
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
}

########################################
# Бэкап конфига
########################################

mkdir -p "$TMP_SF"
cp "$CONF" "$BACK"

########################################
# Формирование стратегий
########################################

echo -e "\n${MAGENTA}Скачиваем и формируем стратегии${NC}"; mkdir -p "$TMP_SF"; : > "$OUT"; wget -qO "$ZIP" https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip || { echo -e "\n${RED}Не удалось загрузить файл стратегий${NC}\n"PAUSE; return; }
if ! command -v unzip >/dev/null 2>&1; then echo -e "${CYAN}Устанавливаем ${NC}unzip" && opkg install unzip >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить unzip!${NC}\n"; PAUSE; return; }; fi; unzip -oq "$ZIP" -d "$TMP_SF" || { echo -e "\n${RED}Не удалось распоковать файл${NC}\n"; PAUSE; return; }
BASE="$TMP_SF/zapret-discord-youtube-main"; find "$BASE" -type f -name 'general*.bat' ! -name 'general (ALT5).bat' | while read -r F; do MATCH=$(grep -E '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' "$F")
[ -z "$MATCH" ] && continue; NAME=$(basename "$F" .bat); { echo "#$NAME"; echo "$MATCH" | sed 's/--/\n--/g' | sed '/^$/d' | sed 's/[[:space:]]*$//'; echo; } >> "$OUT"; done; sed -i 's|"%BIN%tls_clienthello_www_google_com.bin"|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' "$OUT"; sed -i '/--hostlist="%LISTS%list-general.txt"/d' "$OUT"
sed -i '/--ipset-exclude="%LISTS%ipset-exclude.txt"/d' "$OUT"; sed -i 's|"%LISTS%list-exclude.txt"|/opt/zapret/ipset/zapret-hosts-user-exclude.txt|g' "$OUT"; sed -i 's/--new[[:space:]]\^/--new/g' "$OUT"; sed -i 's|"%LISTS%list-google.txt"|/opt/zapret/ipset/zapret-hosts-google.txt|g' "$OUT"
sed -i 's|"%BIN%tls_clienthello_4pda_to.bin"|/opt/zapret/files/fake/4pda.bin|g' "$OUT"; sed -i 's|"%BIN%tls_clienthello_max_ru.bin"|/opt/zapret/files/fake/max.bin|g' "$OUT"; sed -i 's|\^!|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' "$OUT"; sed -i 's/[[:space:]]\+$//g' "$OUT"; sed -i '/^--new$/ { N; /^\--new\n$/d; }' "$OUT"
rm -rf "$TMP_SF/zapret-discord-youtube-main" "$ZIP"; echo -e "${GREEN}Стратегии сформированы!${NC}\n"

strategy_v1() { printf '%s\n' "#v1" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake,multidisorder" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq"
printf '%s\n' "--dpi-desync-badseq-increment=10000000" "--dpi-desync-repeats=6" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com" "--new"
printf '%s\n' "--filter-udp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin"; }
strategy_v2() { printf '%s\n' "#v2" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake,fakeddisorder" "--dpi-desync-split-pos=10,midsld" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_vk_com.bin" "--dpi-desync-split-seqovl=336"
printf '%s\n' "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_gosuslugi_ru.bin" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-badseq-increment=0" "--new" "--filter-udp=443"
printf '%s\n' "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin"; }
strategy_v3() { printf '%s\n' "#v3" "#Dv1" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--ip-id=zero" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake,fakeddisorder" "--dpi-desync-split-pos=10,midsld" "--dpi-desync-fake-tls=/opt/zapret/files/fake/t2.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=m.ok.ru" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_vk_com.bin"
printf '%s\n' "--dpi-desync-split-seqovl=336" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_gosuslugi_ru.bin" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-badseq-increment=0"
printf '%s\n' "--new" "--filter-udp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin"; }
strategy_v4() { printf '%s\n' "#v4" "#Yv15" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--dpi-desync=fake,multisplit" "--dpi-desync-split-pos=2,sld" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=google.com" "--dpi-desync-split-seqovl=2108" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fooling=badseq" "--new" "--filter-tcp=443"
printf '%s\n' "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync-any-protocol=1" "--dpi-desync-cutoff=n5" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=582" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/4pda.bin"
printf '%s\n' "--new" "--filter-udp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin"; }
strategy_v5() { printf '%s\n' "#v5" "#Yv01" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--ip-id=zero" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake,fakeddisorder" "--dpi-desync-split-pos=10,midsld" "--dpi-desync-fake-tls=/opt/zapret/files/fake/max.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid"
printf '%s\n' "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_vk_com.bin" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-badseq-increment=0" "--new" "--filter-udp=443"
printf '%s\n' "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin"; }
strategy_v6() { printf '%s\n' "#v6" "#Yv03" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--dpi-desync=fake,multisplit" "--dpi-desync-split-pos=2,sld" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=ggpht.com" "--dpi-desync-split-seqovl=620" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fooling=badsum,badseq"
printf '%s\n' "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=max.ru" "--dpi-desync-hostfakesplit-midhost=host-2" "--dpi-desync-split-seqovl=726" "--dpi-desync-fooling=badsum,badseq" "--dpi-desync-badseq-increment=0"; }
strategy_v7() { printf '%s\n' "#v7" "#Yv03" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--dpi-desync=fake,multisplit" "--dpi-desync-split-pos=2,sld" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=ggpht.com" "--dpi-desync-split-seqovl=620" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fooling=badsum,badseq"
printf '%s\n' "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=654" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/max.bin" "--dpi-desync-fake-tls=/opt/zapret/files/fake/max.bin"; }
strategy_v8() { printf '%s\n' "#v8" "#Yv03" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--dpi-desync=fake,multisplit" "--dpi-desync-split-pos=2,sld" "--dpi-desync-fake-tls=0x0F0F0F0F" "--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin"
printf '%s\n' "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=ggpht.com" "--dpi-desync-split-seqovl=620" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "--dpi-desync-fooling=badsum,badseq"
printf '%s\n' "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=/opt/zapret/files/fake/4pda.bin" "--dpi-desync-fake-tls-mod=none" ; }


# Создаем рабочий файл (str_work.txt)
: > "$WORK_FILE"
cat "$STR_FILE" >> "$WORK_FILE"

# Добавляем нужные стратегии из переменных
for N in 1 2 3 4 5 6 7 8; do
    strategy_v$N >> "$WORK_FILE"
done

# Убираем все строки с #Y только в рабочем файле
sed -i '/#Y/d' "$WORK_FILE"

########################################
# Сайты для проверки
########################################

URLS="$(cat <<EOF
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
EOF
)"

TOTAL=$(echo "$URLS" | wc -l)
: > "$RESULTS"

check_all_urls() {
    TMP_OK="/tmp/z_ok.$$"
    : > "$TMP_OK"

    check_url() {
        if curl -Is --connect-timeout 2 --max-time 3 "$1" >/dev/null 2>&1; then
            echo 1 >> "$TMP_OK"
            echo -e "${GREEN}$1 → OK${NC}"
        else
            echo -e "${RED}$1 → FAIL${NC}"
        fi
    }

    RUN=0
    while read URL; do
        check_url "$URL" &
        RUN=$((RUN+1))
        if [ "$RUN" -ge "$PARALLEL" ]; then wait; RUN=0; fi
    done <<EOF
$URLS
EOF

    wait
    OK=$(wc -l < "$TMP_OK")
    rm -f "$TMP_OK"
}

########################################
# Перебор стратегий
########################################

LINES=$(grep -n '^#' "$WORK_FILE" | cut -d: -f1)

echo "$LINES" | while read START; do
    NEXT=$(echo "$LINES" | awk -v s="$START" '$1>s{print;exit}')
    if [ -z "$NEXT" ]; then
        sed -n "${START},\$p" "$WORK_FILE" > "$TEMP_FILE"
    else
        sed -n "${START},$((NEXT-1))p" "$WORK_FILE" > "$TEMP_FILE"
    fi

    BLOCK=$(cat "$TEMP_FILE")
    NAME=$(head -n1 "$TEMP_FILE")

    awk -v block="$BLOCK" '
        BEGIN{skip=0}
        /option NFQWS_OPT '\''/ {
            print "\toption NFQWS_OPT '\''"
            print block
            print "'\''"
            skip=1; next
        }
        skip && /^'\''$/ { skip=0; next }
        !skip { print }
    ' "$CONF" > "${CONF}.tmp"

    mv "${CONF}.tmp" "$CONF"
    ZAPRET_RESTART

    echo; echo -e "${YELLOW}${NAME}${NC}"

    OK=0
    check_all_urls

    [ "$OK" -eq "$TOTAL" ] && COLOR="$GREEN"
    [ "$OK" -gt 0 ] && [ "$OK" -lt "$TOTAL" ] && COLOR="$YELLOW"
    [ "$OK" -eq 0 ] && COLOR="$RED"

    echo -e "${COLOR}Доступно: $OK/$TOTAL${NC}"
    echo "$OK $NAME" >> "$RESULTS"
done

########################################
# Топ-5 стратегий
########################################

echo; echo -e "${YELLOW}=========== Топ-5 стратегий ===========${NC}"

sort -rn "$RESULTS" | head -5 | while read COUNT NAME; do
    if [ "$COUNT" -eq "$TOTAL" ]; then COLOR="$GREEN"
    elif [ "$COUNT" -gt 0 ]; then COLOR="$YELLOW"
    else COLOR="$RED"; fi
    echo -e "${COLOR}${NAME} → $COUNT/$TOTAL${NC}"
done

########################################
# Восстановление конфига
########################################

echo; echo "Восстанавливаем исходный конфиг..."
mv -f "$BACK" "$CONF"
rm -f "$TEMP_FILE" "$RESULTS"

ZAPRET_RESTART
