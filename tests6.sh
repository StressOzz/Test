#!/bin/sh
# smart_check_minimal_openwrt.sh
# Проверка сайтов с Zapret на OpenWRT, минимальный вывод

SITE_FILE="/tmp/site.txt"
TMP_OFF="/tmp/sites_off.txt"
TMP_ON="/tmp/sites_on.txt"
PARALLEL=10  # число одновременных проверок

# ----------------------------
# Скачиваем список сайтов, если его нет
# ----------------------------
if [ ! -f "$SITE_FILE" ]; then
    wget -O "$SITE_FILE" https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/site.txt
    [ ! -f "$SITE_FILE" ] && echo "Ошибка: не удалось скачать список сайтов" && exit 1
fi

# ----------------------------
# Проверка одного сайта
# ----------------------------
check_site() {
    site="$1"
    out_file="$2"

    [ -z "$site" ] && return
    case "$site" in \#*) return ;; esac

    if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
        echo "$site" >> "$out_file"
    fi
}

# ----------------------------
# Параллельная проверка списка сайтов
# ----------------------------
check_sites_parallel() {
    INPUT="$1"
    OUTPUT="$2"
    > "$OUTPUT"

    while IFS= read -r site; do
        check_site "$site" "$OUTPUT" &
        while [ "$(jobs | wc -l)" -ge "$PARALLEL" ]; do
            sleep 0.1
        done
    done < "$INPUT"
    wait
}

# ----------------------------
# 1. Проверка при выключенном Zapret
# ----------------------------
/etc/init.d/zapret stop
sleep 3
check_sites_parallel "$SITE_FILE" "$TMP_OFF"

# ----------------------------
# 2. Проверка при включенном Zapret
# ----------------------------
/etc/init.d/zapret start
sleep 5
check_sites_parallel "$SITE_FILE" "$TMP_ON"

# ----------------------------
# 3. Вывод сайтов, заблокированных после включения Zapret
# ----------------------------
echo "Сайты, которые работали с выключенным Zapret, но перестали работать со включённым:"
while IFS= read -r site; do
    if grep -qx "$site" "$TMP_OFF" && ! grep -qx "$site" "$TMP_ON"; then
        echo "$site"
    fi
done < "$SITE_FILE"
