#!/bin/sh
# smart_check_parallel_openwrt.sh
# Быстрая двухэтапная проверка сайтов с Zapret на OpenWRT

SITE_FILE="/tmp/site.txt"
TMP_OFF="/tmp/sites_off.txt"
TMP_ON="/tmp/sites_on.txt"
PARALLEL=10  # число одновременных проверок

GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
NC="\033[0m"

# ----------------------------
# Скачиваем список сайтов, если его нет
# ----------------------------
if [ ! -f "$SITE_FILE" ]; then
    echo "Скачиваем список сайтов..."
    wget -O "$SITE_FILE" https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/site.txt
    if [ ! -f "$SITE_FILE" ]; then
        echo -e "${RED}Ошибка: не удалось скачать список сайтов${NC}"
        exit 1
    fi
fi

# ----------------------------
# Функция проверки сайта
# $1 = сайт
# $2 = файл для записи доступного сайта
# $3 = вывод статуса (1 = да)
# ----------------------------
check_site() {
    site="$1"
    out_file="$2"
    show="$3"

    [ -z "$site" ] && return
    case "$site" in \#*) return ;; esac

    if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
        echo "$site" >> "$out_file"
        [ "$show" = "1" ] && echo -e "${GREEN}$site: OK${NC}"
    else
        [ "$show" = "1" ] && echo -e "${RED}$site: FAIL${NC}"
    fi
}

# ----------------------------
# Функция параллельной проверки
# $1 = входной файл
# $2 = файл для записи доступных сайтов
# $3 = вывод статуса
# ----------------------------
check_sites_parallel() {
    INPUT="$1"
    OUTPUT="$2"
    SHOW="$3"
    > "$OUTPUT"

    while IFS= read -r site; do
        check_site "$site" "$OUTPUT" "$SHOW" &
        # ограничиваем число параллельных процессов
        while [ "$(jobs | wc -l)" -ge "$PARALLEL" ]; do
            sleep 0.1
        done
    done < "$INPUT"
    wait
}

# ----------------------------
# 1. Проверка при выключенном Zapret
# ----------------------------
echo -e "${YELLOW}Выключаем Zapret...${NC}"
/etc/init.d/zapret stop
sleep 3

echo -e "${YELLOW}Проверяем сайты при выключенном Zapret...${NC}"
check_sites_parallel "$SITE_FILE" "$TMP_OFF" 1
echo "------------------------------"

# ----------------------------
# 2. Проверка при включенном Zapret
# ----------------------------
echo -e "${YELLOW}Включаем Zapret...${NC}"
/etc/init.d/zapret start
sleep 5

echo -e "${YELLOW}Проверяем сайты при включенном Zapret...${NC}"
check_sites_parallel "$SITE_FILE" "$TMP_ON" 1
echo "------------------------------"

# ----------------------------
# 3. Сравнение результатов
# ----------------------------
echo -e "${RED}Сайты, которые работали без запрета, но заблокированы после включения:${NC}"
while IFS= read -r site; do
    if grep -qx "$site" "$TMP_OFF" && ! grep -qx "$site" "$TMP_ON"; then
        echo -e "${RED}$site${NC}"
    fi
done < "$SITE_FILE"

echo -e "${GREEN}Сайты, которые работают в обоих режимах:${NC}"
while IFS= read -r site; do
    if grep -qx "$site" "$TMP_OFF" && grep -qx "$site" "$TMP_ON"; then
        echo -e "${GREEN}$site${NC}"
    fi
done < "$SITE_FILE"

echo -e "${YELLOW}Сайты, которые не работали изначально (с выключенным запретом):${NC}"
while IFS= read -r site; do
    if ! grep -qx "$site" "$TMP_OFF"; then
        echo -e "${YELLOW}$site${NC}"
    fi
done < "$SITE_FILE"
