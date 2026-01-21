#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow.txt"
BASE_RAW="https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main"

mkdir -p "$TMP" || exit 1
: > "$OUT"

# Явный список файлов, которые скорее всего есть
LIST="
general.bat
README.md
service.bat
"

for F in $LIST; do
  wget -qO "$TMP/$F" "$BASE_RAW/$F"
  if [ -s "$TMP/$F" ]; then
    {
      echo "# $F"
      sed 's/--/\n--/g' "$TMP/$F" \
      | grep '^--filter-' \
      | sed '/^$/d'
      echo
    } >> "$OUT"
  fi
done
