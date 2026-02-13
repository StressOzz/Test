#!/bin/sh

URL="https://example.com/file.txt"
TMP="/tmp/src.txt"
OUT="/tmp/domains.txt"

wget -qO "$TMP" "$URL"

grep -o 'HREF="https://[^"]*"' "$TMP" \
| sed 's|HREF="https://||; s|/".*||' \
> "$OUT"
