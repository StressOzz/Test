#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow.txt"

API="https://api.github.com/repos/Flowseal/zapret-discord-youtube/contents/general"
RAW="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/general"

mkdir -p "$TMP" || exit 1
: > "$OUT"

FILES=$(wget -qO- "$API" | grep '"name":' | grep 'general' | cut -d'"' -f4)

for F in $FILES; do
  wget -qO "$TMP/$F" "$RAW/$F" || continue

  {
    echo "# $F"
    sed 's/--/\n--/g' "$TMP/$F" | grep '^--filter-'
    echo
  } >> "$OUT"
done
