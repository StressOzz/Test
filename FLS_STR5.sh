#!/bin/sh

IN_FILE="/root/nfqws_dump.txt"
OUT_FILE="/root/nfqws_filtered.txt"

: > "$OUT_FILE"

include=0
skip_last_new=0

while IFS= read -r line; do
    # строки без "--" — это заголовки
    case "$line" in
        ""|--*) ;;
        *) 
           echo "#$line" >> "$OUT_FILE"
           echo "" >> "$OUT_FILE"   # пустая строка после заголовка
           continue 
           ;;
    esac

    # проверяем начало нужного блока
    case "$line" in
        "--filter-tcp=2053,2083,2087,2096,8443")
            include=1
            skip_last_new=0
            echo "$line" >> "$OUT_FILE"
            continue
            ;;
        "--filter-tcp=80,443")
            include=1
            skip_last_new=1   # будем игнорировать последний --new
            echo "$line" >> "$OUT_FILE"
            continue
            ;;
    esac

    # если мы в нужном блоке, включаем строки до --new
    if [ $include -eq 1 ]; then
        if [ "$line" = "--new" ]; then
            if [ $skip_last_new -eq 1 ]; then
                echo "" >> "$OUT_FILE"  # вместо --new пустая строка
            else
                echo "$line" >> "$OUT_FILE"
            fi
            include=0
        else
            echo "$line" >> "$OUT_FILE"
        fi
    fi
done < "$IN_FILE"
