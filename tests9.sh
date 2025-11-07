#!/bin/sh
# smart_check_zapret_openwrt.sh
# Проверка доступности сайтов с Zapret на OpenWRT
SITE_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/site.txt"
TMP_LIST="/tmp/site.txt"
TMP_OFF="/tmp/sites_off.txt"
TMP_ON="/tmp/sites_on.txt"
PROG_OFF="/tmp/prog_off.txt"
PROG_ON="/tmp/prog_on.txt"
PARALLEL=12

# ---- Скачиваем список ----
echo "Скачиваем список сайтов..."
wget -O "$TMP_LIST" "$SITE_URL" 2>/dev/null || { echo "Не удалось скачать список"; exit 1; }

TOTAL=$(grep -cv '^\s*$\|^\s*#' "$TMP_LIST")
[ "$TOTAL" -le 0 ] && echo "Список пуст" && exit 1

# ---- Очистка временных файлов ----
for f in "$TMP_OFF" "$TMP_ON" "$PROG_OFF" "$PROG_ON"; do [ -f "$f" ] && rm -f "$f"; done
touch "$TMP_OFF" "$TMP_ON" "$PROG_OFF" "$PROG_ON"

# ---- Проверка одного сайта ----
check_site() {
  site="$1"
  out_file="$2"
  prog_file="$3"
  [ -z "$site" ] && { echo " " >> "$prog_file"; return; }
  case "$site" in \#*) echo " " >> "$prog_file"; return ;; esac
  if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
    echo "$site" >> "$out_file"
  fi
  echo "$site" >> "$prog_file"
}

# ---- Монитор прогресса ----
progress_monitor() {
  progfile="$1"
  total="$2"
  label="$3"
  while :; do
    done_count=$(wc -l < "$progfile" 2>/dev/null || echo 0)
    printf "\r%s: Проверено %d / %d" "$label" "$done_count" "$total"
    if [ "$done_count" -ge "$total" ]; then
      printf "\n"
      break
    fi
    sleep 0.3
  done
}

# ---- Параллельная проверка ----
check_sites_parallel() {
  infile="$1"; outfile="$2"; progfile="$3"; label="$4"
  progress_monitor "$progfile" "$TOTAL" "$label" &
  monitor_pid=$!
  while IFS= read -r site; do
    check_site "$site" "$outfile" "$progfile" &
    while [ "$(jobs | wc -l)" -ge "$PARALLEL" ]; do sleep 0.05; done
  done < "$infile"
  wait
  wait "$monitor_pid" 2>/dev/null || true
}

# ---- Фаза 1: выключаем Zapret ----
echo "Фаза 1: выключаем Zapret..."
/etc/init.d/zapret stop 2>/dev/null || echo "(не удалось вызвать /etc/init.d/zapret stop)"
sleep 2
check_sites_parallel "$TMP_LIST" "$TMP_OFF" "$PROG_OFF" "OFF (Zapret выкл)"

# ---- Фаза 2: включаем Zapret ----
echo "Фаза 2: включаем Zapret..."
/etc/init.d/zapret start 2>/dev/null || echo "(не удалось вызвать /etc/init.d/zapret start)"
sleep 4
> "$PROG_ON"
> "$TMP_ON"
check_sites_parallel "$TMP_LIST" "$TMP_ON" "$PROG_ON" "ON  (Zapret вкл)"

# ---- Сравнение результатов ----
echo "Сайты, которые работали с выкл Zapret, но упали с вкл Zapret:"
while IFS= read -r site; do
  [ -z "$site" ] && continue
  case "$site" in \#*) continue ;; esac
  if grep -qx "$site" "$TMP_OFF" && ! grep -qx "$site" "$TMP_ON"; then
    echo "$site"
  fi
done < "$TMP_LIST"

exit 0
