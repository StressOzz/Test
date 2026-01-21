#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow"

HTML="https://github.com/Flowseal/zapret-discord-youtube/tree/main/general"
RAW="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/general"

mkdir -p "$TMP" || exit 1
: > "$OUT"

FILES=$(wget -qO- "$HTML" | grep -o 'general[^"]*\.sh' | sort -u)

for F in $FILES; do
  wget -qO "$TMP/$F" "$RAW/$F" || continue

  {
    echo "### $F"
    sed 's/--/\n--/g' "$TMP/$F" \
    | grep -E '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"'
    echo
  } >> "$OUT"
done
