#!/bin/sh

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"
TMP="/tmp/dpi_urls.$$"

echo "Скачиваем список тестов..."

if ! curl -fsSL "$RAW" -o "$TMP"; then
    echo "Ошибка загрузки"
    exit 1
fi

awk -F'"' '
/id:[[:space:]]*"/  { id=$2 }
/url:[[:space:]]*"/ { print id "|" $2 }
' "$TMP"

rm -f "$TMP"
