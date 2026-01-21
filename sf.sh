#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow"
BASE_HTML="https://github.com/Flowseal/zapret-discord-youtube/tree/main"
BASE_RAW="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main"

mkdir -p "$TMP" || exit 1
: > "$OUT"

# получаем список файлов general*
FILES=$(wget -qO- "$BASE_HTML" | grep -o 'general[^"]*' | sort -u)

for F in $FILES; do
  wget -qO "$TMP/$F" "$BASE_RAW/$F" || continue

  {
    echo "### $F"
    grep -E -- '--filter-udp=19294-19344,50000-50100|--filter-tcp=2053,2083,2087,2096,8443|--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' "$TMP/$F" \
    | sed 's/--/\n--/g' \
    | sed '/^$/d'
    echo
  } >> "$OUT"
done
