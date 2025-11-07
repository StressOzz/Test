#!/bin/sh
# smart_check_counter_openwrt.sh
# Быстрая двухэтапная проверка сайтов с Zapret (OpenWRT)
# Показывает прогресс: "Проверено X / Y"

SITE_FILE="/mnt/data/site_500.txt"   # <- файл с 500 сайтами (или /tmp/site.txt)
TMP_OFF="/tmp/sites_off.txt"         # успешные при выключенном
TMP_ON="/tmp/sites_on.txt"           # успешные при включенном
PROG_OFF="/tmp/prog_off.txt"         # все обработанные при выключенном (включая FAIL)
PROG_ON="/tmp/prog_on.txt"           # все обработанные при включенном
PARALLEL=12                          # число одновременных проверок (подними, если устройство тянет)

CLEANUP_FILES="$TMP_OFF $TMP_ON $PROG_OFF $PROG_ON"

# ---- проверка наличия файла списка ----
if [ ! -f "$SITE_FILE" ]; then
  echo "Не найден $SITE_FILE. Подтяну файл из репозитория..."
  wget -O "$SITE_FILE" https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/site.txt
  if [ ! -f "$SITE_FILE" ]; then
    echo "Ошибка: не удалось получить список сайтов ($SITE_FILE)" >&2
    exit 1
  fi
fi

TOTAL=$(grep -cv '^\s*$\|^\s*#' "$SITE_FILE" 2>/dev/null || echo 0)
[ "$TOTAL" -le 0 ] && echo "Файл пустой или не содержит сайтов" && exit 1

# ---- очистка старых временных файлов ----
for f in $CLEANUP_FILES; do [ -f "$f" ] && rm -f "$f"; done
touch "$PROG_OFF" "$PROG_ON" "$TMP_OFF" "$TMP_ON"

# ---- функция проверки одного сайта (возвращает 0/1 не ловим) ----
# $1 = сайт
# $2 = файл для записи успешных (OUT)
# $3 = файл прогресса (PROG)
check_site() {
  site="$1"
  out_file="$2"
  prog_file="$3"

  [ -z "$site" ] && { echo " " >> "$prog_file"; return; }
  case "$site" in \#*) echo " " >> "$prog_file"; return ;; esac

  # пробуем https - если не проходит, считаем как FAIL (но в прогрес вставляем запись)
  if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
    echo "$site" >> "$out_file"
  fi
  # отмечаем, что один сайт обработан (независимо от результата)
  echo "$site" >> "$prog_file"
}

# ---- монитор прогресса ----
# $1 = файл прогресса, $2 = total, $3 = описание
progress_monitor() {
  progfile="$1"
  total="$2"
  label="$3"
  while :; do
    done_count=$(wc -l < "$progfile" 2>/dev/null || echo 0)
    # печатаем в одну строку (carriage return) — перезаписываем
    printf "\r%s: Проверено %d / %d" "$label" "$done_count" "$total"
    if [ "$done_count" -ge "$total" ]; then
      printf "\n"
      break
    fi
    sleep 0.3
  done
}

# ---- параллельная проверка списка ----
# $1 = входной файл (список сайтов)
# $2 = OUT файл (успешные)
# $3 = PROG файл (всего обработанных)
# $4 = label для монитора
check_sites_parallel() {
  infile="$1"; outfile="$2"; progfile="$3"; label="$4"

  # запустим монитор в фоне
  progress_monitor "$progfile" "$TOTAL" "$label" &
  monitor_pid=$!

  # читаем список и порождаем процессы
  while IFS= read -r site; do
    # пропускаем пустые и комменты в подсчёте (но оставляем в файле прогресса как строчку)
    case "$site" in \#*|'') : ;; esac
    check_site "$site" "$outfile" "$progfile" &
    # ограничение параллельных задач
    while [ "$(jobs | wc -l)" -ge "$PARALLEL" ]; do
      sleep 0.05
    done
  done < "$infile"

  wait
  # дождёмся монитора
  wait "$monitor_pid" 2>/dev/null || true
}

# ---- ФАЗА 1: выключаем Zapret и проверяем ----
echo "Фаза 1: выключаем Zapret и проверяем все сайты..."
/etc/init.d/zapret stop 2>/dev/null || echo "(не удалось вызвать /etc/init.d/zapret stop — ok продолжим)"
sleep 2
check_sites_parallel "$SITE_FILE" "$TMP_OFF" "$PROG_OFF" "OFF (Zapret выкл)"

# ---- ФАЗА 2: включаем Zapret и проверяем ----
echo "Фаза 2: включаем Zapret и проверяем все сайты..."
/etc/init.d/zapret start 2>/dev/null || echo "(не удалось вызвать /etc/init.d/zapret start — ok продолжим)"
sleep 4
# очистим прогресс-файл на фазу ON (и OUT на ON)
> "$PROG_ON"
> "$TMP_ON"
check_sites_parallel "$SITE_FILE" "$TMP_ON" "$PROG_ON" "ON  (Zapret вкл)"

# ---- Сравнение результатов ----
echo "Сравниваем результаты..."
# выводим только те, которые были в OFF, но отсутствуют в ON
# (используем grep -qx для точного поиска)
while IFS= read -r site; do
  [ -z "$site" ] && continue
  case "$site" in \#*) continue ;; esac
  if grep -qx "$site" "$TMP_OFF" && ! grep -qx "$site" "$TMP_ON"; then
    echo "$site"
  fi
done < "$SITE_FILE"

# ---- Очистка временных файлов (опция) ----
# rm -f $CLEANUP_FILES

exit 0
