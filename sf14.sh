#!/bin/sh

TMP="/opt/zapret_temp"
OUT="$TMP/str_flow.txt"
ZIP="$TMP/repo.zip"

mkdir -p "$TMP" || exit 1
: > "$OUT"

# Скачиваем репозиторий
wget -qO "$ZIP" https://github.com/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip || exit 1
unzip -oq "$ZIP" -d "$TMP" || exit 1

BASE="$TMP/zapret-discord-youtube-main"

# 1. Берём файлы general*, исключаем ALT5
find "$BASE" -type f -name 'general*.bat' ! -name 'general (ALT5).bat' | while read -r F; do
  MATCH=$(grep -E \
    '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' \
    "$F")

  [ -z "$MATCH" ] && continue

  NAME=$(basename "$F" .bat)

  {
    echo "#$NAME"
    echo "$MATCH" | sed 's/--/\n--/g' | sed '/^$/d' | sed 's/[[:space:]]*$//'
    echo
  } >> "$OUT"
done

# 2. Замены по списку

sed -i 's|"%BIN%tls_clienthello_www_google_com.bin"|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' "$OUT"
sed -i '/--hostlist="%LISTS%list-general.txt"/d' "$OUT"
sed -i '/--ipset-exclude="%LISTS%ipset-exclude.txt"/d' "$OUT"
sed -i 's|"%LISTS%list-exclude.txt"|/opt/zapret/ipset/zapret-hosts-user-exclude.txt|g' "$OUT"
sed -i 's/--new[[:space:]]\^/--new/g' "$OUT"
sed -i 's|"%LISTS%list-google.txt"|/opt/zapret/ipset/zapret-hosts-google.txt|g' "$OUT"
sed -i 's|"%BIN%tls_clienthello_4pda_to.bin"|/opt/zapret/files/fake/4pda.bin|g' "$OUT"
sed -i 's|"%BIN%tls_clienthello_max_ru.bin"|/opt/zapret/files/fake/max.bin|g' "$OUT"
sed -i 's|\^!|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' "$OUT"

# убрать trailing spaces
sed -i 's/[[:space:]]\+$//g' "$OUT"

# 3. Удаляем пустые строки перед #general и лишние --new выше
sed -i '/^--new$/{
    N
    /^\--new\n$/d
}' "$OUT"
