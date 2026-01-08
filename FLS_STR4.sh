#!/bin/sh

IN_FILE="/root/nfqws_dump.txt"
OUT_FILE="/root/nfqws_filtered.txt"

: > "$OUT_FILE"

include=0

while IFS= read -r line; do
    # строки без "--" — это заголовки
    case "$line" in
        ""|--*) ;;
        *) echo "#$line" >> "$OUT_FILE"; continue ;;
    esac

    # проверяем начало нужного блока (только точные строки)
    case "$line" in
        "--filter-tcp=2053,2083,2087,2096,8443"|"--filter-tcp=80,443")
            include=1
            echo "$line" >> "$OUT_FILE"
            continue
            ;;
    esac

    # если мы в нужном блоке, включаем всё до --new
    if [ $include -eq 1 ]; then
        echo "$line" >> "$OUT_FILE"
        case "$line" in
            --new) include=0 ;;
        esac
    fi
done < "$IN_FILE"
