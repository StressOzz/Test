#!/bin/sh

URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/ttt"
TMP="/opt/src.txt"
OUT="/opt/domains.txt"

wget -qO "$TMP" "$URL"

grep -o 'HREF="https://[^"]*"' "$TMP" \
| sed 's|HREF="https://||; s|/".*||' \
> "$OUT"
