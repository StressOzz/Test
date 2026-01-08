#!/bin/sh

SRC_DIR="/root/configs"
OUT_FILE="/root/nfqws_filtered.txt"

: > "$OUT_FILE"

for f in "$SRC_DIR"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "#$name" >> "$OUT_FILE"

    in_block=0
    while IFS= read -r line; do
        case "$line" in
            'NFQWS_OPT="'*) in_block=1; continue ;;
            '"'*) in_block=0; continue ;;
        esac

        if [ $in_block -eq 1 ]; then
            # каждая часть через --
            echo "$line" | tr ' ' '\n' | while IFS= read -r word; do
                case "$word" in
                    --*) echo "$word" >> "$OUT_FILE" ;;
                esac
            done
        fi
    done < "$f"

    # пустая строка между стратегиями (имя следующего файла)
    echo "" >> "$OUT_FILE"
done

# --- фильтруем только нужные блоки ---
TEMP_FILE="/root/nfqws_temp.txt"
mv "$OUT_FILE" "$TEMP_FILE"
: > "$OUT_FILE"

include=0
skip_last_new=0

while IFS= read -r line; do
    # строки без "--" — это заголовки
    case "$line" in
        ""|--*) ;;
        *) 
           echo "$line" >> "$OUT_FILE"
           continue 
           ;;
    esac

    # проверяем начало нужного блока (строгое сравнение)
    case "$line" in
        "--filter-tcp=2053,2083,2087,2096,8443")
            include=1
            skip_last_new=0
            echo "$line" >> "$OUT_FILE"
            continue
            ;;
        "--filter-tcp=80,443")
            include=1
            skip_last_new=1
            echo "$line" >> "$OUT_FILE"
            continue
            ;;
    esac

    # если мы в нужном блоке, включаем строки до --new
    if [ $include -eq 1 ]; then
        if [ "$line" = "--new" ]; then
            if [ $skip_last_new -eq 1 ]; then
                echo "" >> "$OUT_FILE"
            else
                echo "$line" >> "$OUT_FILE"
            fi
            include=0
        else
            echo "$line" >> "$OUT_FILE"
        fi
    fi
done < "$TEMP_FILE"

rm -f "$TEMP_FILE"
