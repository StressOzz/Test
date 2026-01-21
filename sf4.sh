#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow.txt"
ZIP="$TMP/repo.zip"

mkdir -p "$TMP" || exit 1
: > "$OUT"

# качаем архив репозитория
wget -qO "$ZIP" https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip || exit 1

# распаковываем
unzip -oq "$ZIP" -d "$TMP" || exit 1

BASE="$TMP/zapret-discord-youtube-main"

# ищем ВСЕ файлы general*
find "$BASE" -type f -name 'general*' | while read -r F; do
  {
    echo "# $(basename "$F")"
    sed 's/--/\n--/g' "$F" \
    | grep -E '^--filter-(udp|tcp)=' \
    | grep -E '19294-19344,50000-50100|2053,2083,2087,2096,8443|list-google.txt|list-general.txt'
    echo
  } >> "$OUT"
done
