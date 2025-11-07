#!/bin/sh
# smart_check_zapret.sh
# Двухэтапная проверка сайтов с Zapret

SITE_FILE="/mnt/data/site.txt"   # список сайтов
TMP_OK="/tmp/sites_ok.txt"
TMP_AFTER="/tmp/sites_after.txt"

GREEN="\033[1;32m"
RED="\033[1;31m"
NC="\033[0m"

# ----------------------------
# Функция проверки сайтов
# $1 = файл со списком сайтов
# $2 = файл для сохранения доступных сайтов
# $3 = только вывод статуса, если 1 — показывать
# ----------------------------
check_sites() {
    INPUT_FILE="$1"
    OUTPUT_FILE="$2"
    SHOW_STATUS="$3"
    > "$OUTPUT_FILE"

    while IFS= read -r site; do
        [ -z "$site" ] && continue
        case "$site" in \#*) continue ;; esac
        if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
            echo "$site" >> "$OUTPUT_FILE"
            [ "$SHOW_STATUS" = "1" ] && echo -e "${GREEN}$site: OK${NC}"
        else
            [ "$SHOW_STATUS" = "1" ] && echo -e "${RED}$site: FAIL${NC}"
        fi
    done < "$INPUT_FILE"
}

# ----------------------------
# 1. Выключаем Zapret
# ----------------------------
echo -e "${GREEN}Выключаем Zapret для первой проверки...${NC}"
/etc/init.d/zapret stop
sleep 3

# ----------------------------
# 2. Проверяем сайты при выключенном Zapret
# ----------------------------
echo "Проверяем доступность сайтов с выключенным Zapret..."
check_sites "$SITE_FILE" "$TMP_OK" 1
echo "------------------------------"

# ----------------------------
# 3. Включаем Zapret
# ----------------------------
echo -e "${GREEN}Включаем Zapret для второй проверки...${NC}"
/etc/init.d/zapret start
sleep 5

# ----------------------------
# 4. Проверяем только рабочие сайты из первого этапа
# ----------------------------
echo "Проверяем ранее доступные сайты с включенным Zapret..."
check_sites "$TMP_OK" "$TMP_AFTER" 0

# ----------------------------
# 5. Выводим сайты, которые перестали работать
# ----------------------------
echo -e "${RED}Сайты, заблокированные после включения Zapret:${NC}"
comm -23 <(sort "$TMP_OK") <(sort "$TMP_AFTER")
