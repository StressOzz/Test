#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow.txt"
ZIP="$TMP/repo.zip"

mkdir -p "$TMP" || exit 1
: > "$OUT"

wget -qO "$ZIP" https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip || exit 1
unzip -oq "$ZIP" -d "$TMP" || exit 1

BASE="$TMP/zapret-discord-youtube-main"

find "$BASE" -type f -name 'general*' | while read -r F; do
  MATCH=$(grep -E \
    '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' \
    "$F")

  [ -z "$MATCH" ] && continue

  {
    echo "# $(basename "$F")"
    echo "$MATCH" | sed 's/--/\n--/g' | sed '/^$/d'
    echo
  } >> "$OUT"
done
