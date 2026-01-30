#!/bin/sh

RAW="https://raw.githubusercontent.com/hyperion-cs/dpi-checkers/main/ru/tcp-16-20/index.html"
TMP="/tmp/dpi_urls.$$"

curl -fsSL "$RAW" -o "$TMP" || {
    echo "Ошибка загрузки"
    exit 1
}

awk '
match($0, /id:[[:space:]]*"([^"]+)"/, a)  { id=a[1] }
match($0, /url:[[:space:]]*"([^"]+)"/, b) { print id "|" b[1] }
' "$TMP"

rm -f "$TMP"
