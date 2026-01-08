#!/bin/sh

SRC_DIR="/root/configs"
OUT_FILE="/root/nfqws_dump.txt"

: > "$OUT_FILE"

for f in "$SRC_DIR"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "$name" >> "$OUT_FILE"

    in_block=0
    while IFS= read -r line; do
        case "$line" in
            'NFQWS_OPT="'*) in_block=1; continue ;;
            '"'*) in_block=0; echo "" >> "$OUT_FILE"; continue ;;
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

    echo "" >> "$OUT_FILE"
done
