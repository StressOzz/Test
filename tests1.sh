#!/bin/sh
# simple_check.sh — проверка доступности сайтов из файла

# URL или локальный файл со списком
SITE_LIST_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/site.txt"
TMP_FILE="/tmp/sites.txt"

# скачиваем список
curl -s -o "$TMP_FILE" "$SITE_LIST_URL"

if [ ! -f "$TMP_FILE" ] || [ ! -s "$TMP_FILE" ]; then
    echo "Не удалось скачать список сайтов."
    exit 1
fi

while IFS= read -r site; do
    # игнорируем пустые строки и комментарии
    [ -z "$site" ] && continue
    case "$site" in \#*) continue ;; esac

    # проверка через curl
    if curl -Is --connect-timeout 1 --max-time 2 "https://$site" >/dev/null 2>&1; then
        echo "$site: OK"
    else
        echo "$site: FAIL"
    fi
done < "$TMP_FILE"
