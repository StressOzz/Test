#!/bin/sh

SRC_DIR="/root/configs"
DUMP_FILE="/root/nfqws_dump.txt"
OUT_FILE="/root/nfqws_filtered.txt"

# 1️⃣ Собираем все файлы в один
: > "$DUMP_FILE"

for f in "$SRC_DIR"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "$name" >> "$DUMP_FILE"

    in_block=0
    while IFS= read -r line; do
        case "$line" in
            'NFQWS_OPT="'*) in_block=1; continue ;;
            '"'*) in_block=0; echo "" >> "$DUMP_FILE"; continue ;;
        esac

        if [ $in_block -eq 1 ]; then
            # каждая часть через --
            echo "$line" | tr ' ' '\n' | while IFS= read -r word; do
                case "$word" in
                    --*) echo "$word" >> "$DUMP_FILE" ;;
                esac
            done
        fi
    done < "$f"
    echo "" >> "$DUMP_FILE"
done

# 2️⃣ Фильтруем нужные блоки
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
done < "$DUMP_FILE"
