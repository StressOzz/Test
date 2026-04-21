#!/bin/sh

SCRIPT="/root/Zapret-Manager.sh"
URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/Zapret-Manager.sh"

RESULT="/opt/zapret/tmp/results_all.txt"
STR_FILE="/opt/zapret/tmp/strategies.txt"

CONF="/opt/zapret/config"
TMP_CONF="/opt/zapret/config.tmp"

# проверка curl
command -v curl >/dev/null 2>&1 || exit 1

# скачиваем свежий скрипт
curl -fsSL "$URL" -o "$SCRIPT" || exit 1
chmod +x "$SCRIPT"

# запускаем тест
NO_PAUSE=1
. "$SCRIPT"

run_all_tests > /dev/null 2>&1

# проверка результата
[ ! -s "$RESULT" ] && exit 1

# берём лучшую стратегию
BEST_LINE=$(head -n1 "$RESULT")
BEST_NAME=$(echo "$BEST_LINE" | cut -d'→' -f1 | sed 's/[[:space:]]*$//')

[ -z "$BEST_NAME" ] && exit 1

echo "Лучшая стратегия: $BEST_NAME"

# проверка файла стратегий
[ ! -s "$STR_FILE" ] && exit 1

# вытаскиваем блок стратегии
awk -v name="$BEST_NAME" '
$0 ~ "^#"name {flag=1}
flag && /^#/ && $0 !~ "^#"name {flag=0}
flag {print}
' "$STR_FILE" > /tmp/best_strategy.txt

BLOCK=$(cat /tmp/best_strategy.txt)
[ -z "$BLOCK" ] && exit 1

# применяем стратегию
awk -v block="$BLOCK" '
BEGIN{skip=0}
/option NFQWS_OPT '\''/ {
    printf "\toption NFQWS_OPT '\''\n%s\n'\''\n", block
    skip=1
    next
}
skip && /^'\''$/ {skip=0; next}
!skip {print}
' "$CONF" > "$TMP_CONF"

mv "$TMP_CONF" "$CONF"

# перезапуск
chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; sleep 1;

echo "Готово"
