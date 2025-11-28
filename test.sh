#!/bin/sh

# URL-списки
URLS="
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/hodca.lst
"

TARGET="/opt/mylist.txt"   # куда собрать итог
TMP="$(mktemp)"

for url in $URLS; do
    echo "Скачиваю $url …"
    # используем curl, можно wget — если есть
    curl -fsSL "$url" >> "$TMP" || {
        echo "Ошибка при скачивании $url"
    }
    echo "" >> "$TMP"
done

# Чистим: убираем пустые строки, пробелы, дубли
sed -e 's/^[ \t]*//; s/[ \t]*$//' "$TMP" \
    | grep -v '^$' \
    | sort -u > "$TARGET"

rm "$TMP"

echo "Сделано — итог в $TARGET"
