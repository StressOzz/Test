#!/bin/sh

# API ссылка для получения списка файлов
API_URL="https://api.github.com/repos/kartavkun/zapret-discord-youtube/contents/configs"

TMP_DIR="/root/zapret_configs"
DUMP_FILE="/root/nfqws_dump.txt"
OUT_FILE="/root/nfqws_filtered.txt"

# 1) Очищаем и создаём временную папку
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 2) Получаем список файлов
wget -q -O "/tmp/files.json" "$API_URL"

# 3) Скачиваем каждый файл из configs
cat /tmp/files.json | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read url; do
    fname="$(basename "$url")"
    wget -q -O "$TMP_DIR/$fname" "$url"
done

# 4) Собираем в один nfqws_dump.txt
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

# 5) Фильтрация нужных TCP блоков
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
            include=1; skip_last_new=0; echo "$line" >> "$OUT_FILE"; continue
            ;;
        "--filter-tcp=80,443")
            include=1; skip_last_new=1; echo "$line" >> "$OUT_FILE"; continue
            ;;
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

# 6) Удаляем временные данные
rm -rf "$TMP_DIR" /tmp/files.json
