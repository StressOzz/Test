#!/bin/sh

# ================= Цвета для вывода =================
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# ================= Конфиги и временные файлы =================
CONF="/etc/config/zapret"
DUMP_FILE="/opt/FS_dump.txt"
OUT_FILE="/opt/FS_filtered.txt"
STR_FILE="/opt/FS_Str.txt"
TMP_DIR="/tmp/zapret_configs"

GITHUB_API="https://api.github.com/repos/kartavkun/zapret-discord-youtube/contents/configs"

ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
}

# ================= Проверка GitHub =================
echo -e "\n${YELLOW}===== Проверка GitHub =====${NC}"
RATE=$(curl -s https://api.github.com/rate_limit | grep '"remaining"' | head -1 | awk '{print $2}' | tr -d ,)
[ -z "$RATE" ] && RATE_OUT="${RED}N/A${NC}" || RATE_OUT=$([ "$RATE" -eq 0 ] && echo -e "${RED}0${NC}" || echo -e "${GREEN}$RATE${NC}")
echo -n "API: "; curl -Is --connect-timeout 3 https://api.github.com >/dev/null 2>&1 && echo -e "${GREEN}ok${NC} | Limit: $RATE_OUT" || echo -e "${RED}fail${NC} | Limit: $RATE_OUT"

# ================= 1️⃣ Обновление стратегий NFQWS =================
echo -e "${YELLOW}=== Обновление стратегий NFQWS с GitHub ===${NC}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

wget -q -O "/tmp/files.json" "$GITHUB_API"
echo -e "${GREEN}Скачиваем файлы из configs...${NC}"
cat /tmp/files.json | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read url; do
    fname="$(basename "$url")"
    echo -e "${YELLOW}Скачиваем $fname${NC}"
    wget -q -O "$TMP_DIR/$fname" "$url"
done

# ================= 2️⃣ Собираем все стратегии в DUMP_FILE =================
echo -e "${GREEN}Собираем все стратегии в $DUMP_FILE${NC}"
: > "$DUMP_FILE"
for f in "$TMP_DIR"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "#$name" >> "$DUMP_FILE"

    in_block=0
    while IFS= read -r line; do
        case "$line" in
            'NFQWS_OPT="'*) in_block=1; continue ;;
            '"'*) in_block=0; continue ;;
        esac

        [ $in_block -eq 1 ] && echo "$line" | tr ' ' '\n' | grep '^--' >> "$DUMP_FILE"
    done < "$f"
    echo "" >> "$DUMP_FILE"
done

# ================= 3️⃣ Фильтруем TCP блоки в OUT_FILE =================
echo -e "${GREEN}Фильтруем TCP-блоки для $OUT_FILE${NC}"
: > "$OUT_FILE"
include=0
skip_last_new=0

while IFS= read -r line; do
    case "$line" in
        ""|--*) ;;
        *) echo "$line" >> "$OUT_FILE"; continue ;;
    esac

    case "$line" in
        "--filter-tcp=2053,2083,2087,2096,8443")
            include=1; skip_last_new=0; echo "$line" >> "$OUT_FILE"; continue ;;
        "--filter-tcp=80,443")
            include=1; skip_last_new=1; echo "$line" >> "$OUT_FILE"; continue ;;
    esac

    [ $include -eq 1 ] && {
        if [ "$line" = "--new" ]; then
            [ $skip_last_new -eq 1 ] && echo "" >> "$OUT_FILE" || echo "$line" >> "$OUT_FILE"
            include=0
        else
            echo "$line" >> "$OUT_FILE"
        fi
    }
done < "$DUMP_FILE"

# ================= 4️⃣ Финальная постобработка =================
echo -e "${GREEN}Применяем финальные правки к файлам${NC}"
sed -i \
    -e 's/%20//g' \
    -e 's/80,//g' \
    -e 's/"//g' \
    -e '/^--hostlist=/d' \
    -e '/^--ipset-exclude=/d' \
    -e 's|^--hostlist-exclude=.*|--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt|' \
    "$OUT_FILE"

sed -i'' \
    -e 's/%20//g' \
    -e 's/"//g' \
    -e 's/\$GAME_FILTER/1024-65535/g' \
    -e 's|^--hostlist=/opt/zapret/hostlists/list-google.txt.*|--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt|' \
    -e 's|^--hostlist=/opt/zapret/hostlists/list-general.txt.*|--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt|' \
    -e 's|^--hostlist-exclude=.*|--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt|' \
    -e 's|^--ipset=.*|--ipset=/opt/zapret/ipset/zapret-ip-user.txt|' \
    -e 's|^--ipset-exclude=.*|--ipset-exclude=/opt/zapret/ipset/zapret-ip-user-exclude.txt|' \
    -e '/^[[:space:]]*$/d' \
    "$DUMP_FILE"

# ================= 5️⃣ Удаляем временные файлы =================
rm -rf "$TMP_DIR" /tmp/files.json


    echo -e "${YELLOW}Нажмите Enter...${NC}"
    read

# ================= 6️⃣ Меню стратегий по кругу с отображением текущей =================
