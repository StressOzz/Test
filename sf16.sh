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
    '^--filter-udp=%GameFilter%' \
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
sed -i 's|"%BIN%quic_initial_www_google_com.bin"|/opt/zapret/files/fake/quic_initial_www_google_com.bin|g' "$OUT"

# убрать trailing spaces
sed -i 's/[[:space:]]\+$//g' "$OUT"

# 3. Удаляем блоки --new + пустая строка
sed -i '/^--new$/{
    N
    /^\--new\n$/d
}' "$OUT"

# 4. Убираем временные файлы репозитория
rm -rf "$TMP/zapret-discord-youtube-main" "$ZIP"
