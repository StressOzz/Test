#!/bin/sh

# --- настройки ---
URL="https://raw.githubusercontent.com/SoliSpirit/mtproto/refs/heads/master/all_proxies.txt"
TMP_RAW="/tmp/mtproto_raw.txt"
TMP_LIST="/tmp/mtproto_list.txt"
RESULT="/tmp/mtproto_result.txt"
FINAL="/tmp/mtproto_sorted.txt"

# --- скачиваем список ---
echo "Скачиваем список MTProto-прокси..."
wget -q -O "$TMP_RAW" "$URL" || { echo "Ошибка скачивания"; exit 1; }

> "$TMP_LIST"
> "$RESULT"

# --- вытаскиваем server и port ---
echo "Формируем чистый список server:port..."
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

echo "Чистый список сформирован: $TMP_LIST ($(wc -l < "$TMP_LIST") прокси)"

# --- проверка прокси ---
echo
echo "Проверяем доступность прокси..."
while read -r SERVER PORT; do
    [ -z "$SERVER" ] && continue
    [ -z "$PORT" ] && continue

    printf "Проверка %s:%s ... " "$SERVER" "$PORT"

    # проверка TCP через wget
    if [ "$PORT" = "443" ] || [ "$PORT" = "2053" ]; then
        wget -q --timeout=3 --spider "https://$SERVER:$PORT" >/dev/null 2>&1
    else
        wget -q --timeout=3 --spider "http://$SERVER:$PORT" >/dev/null 2>&1
    fi

    if [ $? -ne 0 ]; then
        echo "FAIL"
        continue
    fi

    # замер пинга
    PING=$(ping -c1 -W1 "$SERVER" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | awk '{print $1}')
    [ -z "$PING" ] && PING=9999

    echo "OK (${PING} ms)"
    echo "$PING $SERVER $PORT" >> "$RESULT"

done < "$TMP_LIST"

# --- сортировка по пингу ---
echo
echo "Сортировка по пингу..."
sort -n "$RESULT" > "$FINAL"

echo
echo "Лучшие прокси:"
echo "======================="
while read -r P S O; do
    echo "$S:$O — ${P} ms"
done < "$FINAL"

echo
echo "Готово. Итоговый файл: $FINAL"
