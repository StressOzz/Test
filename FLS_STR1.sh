#!/bin/sh

SRC_DIR="/root/configs"
OUT_FILE="/root/nfqws_dump.txt"

: > "$OUT_FILE"

for f in "$SRC_DIR"/*; do
    [ -f "$f" ] || continue

    name="$(basename "$f")"

    awk -v title="$name" '
        BEGIN { in=0 }
        /^NFQWS_OPT="/ { in=1; print title; next }
        in && /^"/ { in=0; print ""; next }
        in {
            gsub(/\r/, "")
            n = split($0, a, /[[:space:]]+--/)
            for (i=1; i<=n; i++) {
                if (a[i] != "") {
                    if (i == 1 && $0 !~ /^--/) {
                        print "--" a[i]
                    } else {
                        print "--" a[i]
                    }
                }
            }
        }
    ' "$f" >> "$OUT_FILE"

done
