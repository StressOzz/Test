#!/bin/sh

URL="https://raw.githubusercontent.com/SoliSpirit/mtproto/refs/heads/master/all_proxies.txt"
TMP="/tmp/mtproto_list.txt"
RESULT="/tmp/mtproto_result.txt"
FINAL="/tmp/mtproto_sorted.txt"

wget -q -O "$TMP" "$URL" || { echo "Ошибка загрузки"; exit 1; }

> "$RESULT"

echo "Проверяем прокси..."

while read -r line; do
    case "$line" in
        *server=*port=*)
            SERVER=$(echo "$line" | sed -n 's/.*server=\([^&]*\).*/\1/p')
            PORT=$(echo "$line" | sed -n 's/.*port=\([^&]*\).*/\1/p')

            [ -z "$SERVER" ] && continue
            [ -z "$PORT" ] && continue

            # фильтр невалидных портов
            if [ "$PORT" -gt 65535 ] 2>/dev/null || [ "$PORT" -lt 1 ] 2>/dev/null; then
                continue
            fi

            printf "Проверка %s:%s ... " "$SERVER" "$PORT"

            # пробуем подключение через wget
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
        ;;
    esac
done < "$TMP"

echo
echo "Сортировка..."

sort -n "$RESULT" > "$FINAL"

echo
echo "Лучшие прокси:"
echo "=============================="

while read -r line; do
    P=$(echo "$line" | awk '{print $1}')
    S=$(echo "$line" | awk '{print $2}')
    O=$(echo "$line" | awk '{print $3}')
    echo "$S:$O  —  ${P} ms"
done < "$FINAL"

echo
echo "Готово. Результат: $FINAL"
