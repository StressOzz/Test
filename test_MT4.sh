#!/bin/sh

# --- настройки цветов ---
RED="\033[31m"
GREEN="\033[32m"
BLUE="\033[34m"
NC="\033[0m"  # сброс цвета

# --- настройки ---
URL="https://raw.githubusercontent.com/SoliSpirit/mtproto/refs/heads/master/all_proxies.txt"
TMP_RAW="/tmp/mtproto_raw.txt"
TMP_LIST="/tmp/mtproto_list.txt"
RESULT="/tmp/mtproto_result.txt"
FINAL="/tmp/mtproto_alive.txt"

# --- скачиваем список ---
echo -e "${BLUE}Скачиваем список MTProto-прокси...${NC}"
wget -q -O "$TMP_RAW" "$URL" || { echo -e "${RED}Ошибка скачивания${NC}"; exit 1; }

> "$TMP_LIST"
> "$RESULT"

# --- вытаскиваем server и port ---
echo -e "${BLUE}Формируем чистый список server:port...${NC}"
while read -r line; do
    case "$line" in
        *server=*port=*)
            SERVER=$(echo "$line" | sed -n 's/.*server=\([^&]*\).*/\1/p')
            PORT=$(echo "$line" | sed -n 's/.*port=\([^&]*\).*/\1/p')

            [ -z "$SERVER" ] && continue
            [ -z "$PORT" ] && continue

            # фильтр валидных портов
            if [ "$PORT" -gt 65535 ] 2>/dev/null || [ "$PORT" -lt 1 ] 2>/dev/null; then
                continue
            fi

            echo "$SERVER $PORT" >> "$TMP_LIST"
        ;;
    esac
done < "$TMP_RAW"

echo -e "${BLUE}Чистый список сформирован: $TMP_LIST ($(wc -l < "$TMP_LIST") прокси)${NC}"

# --- проверка прокси через nc ---
echo
echo -e "${BLUE}Проверяем доступность прокси через TCP connect...${NC}"
while read -r SERVER PORT; do
    [ -z "$SERVER" ] && continue
    [ -z "$PORT" ] && continue

    printf "Проверка %s:%s ... " "$SERVER" "$PORT"

    nc -z -w3 "$SERVER" "$PORT" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}OK${NC}"
        echo "$SERVER $PORT" >> "$RESULT"
    else
        echo -e "${RED}FAIL${NC}"
    fi

done < "$TMP_LIST"

# --- сортировка (по алфавиту) ---
sort "$RESULT" > "$FINAL"

echo
echo -e "${BLUE}Живые прокси:${NC}"
echo "======================="
cat "$FINAL"

echo
echo -e "${BLUE}Готово. Итоговый файл: $FINAL${NC}"
