#!/bin/sh

CONF="/etc/config/zapret"
DUMP_FILE="/opt/FS_dump.txt"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
}

[ ! -f "$DUMP_FILE" ] && {
    echo -e "${RED}Файл $DUMP_FILE не найден${NC}"
    exit 1
}

echo -e "\n${YELLOW}=== Выбор стратегии NFQWS ===${NC}"

MAP="/tmp/nfqws_menu.map"
: > "$MAP"

awk '
/^#/ {
    name=substr($0,2)
    print NR "|" name
}
' "$DUMP_FILE" > "$MAP"

COUNT=$(wc -l < "$MAP")

[ "$COUNT" -eq 0 ] && {
    echo -e "${RED}Стратегии не найдены${NC}"
    exit 1
}

i=1
while IFS="|" read -r line name; do
    printf "%2d) %s\n" "$i" "$name"
    i=$((i+1))
done < "$MAP"

echo ""
printf "Выберите стратегию (1-%s): " "$COUNT"
read SEL

case "$SEL" in
    ''|*[!0-9]*)
        echo -e "${RED}Неверный ввод${NC}"
        exit 1
        ;;
esac

[ "$SEL" -lt 1 ] || [ "$SEL" -gt "$COUNT" ] && {
    echo -e "${RED}Номер вне диапазона${NC}"
    exit 1
}

START_LINE=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f1)
NAME=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f2)

END_LINE=$(awk -v s="$START_LINE" '
NR > s && /^#/ { print NR-1; exit }
END { print NR }
' "$DUMP_FILE")

echo -e "${GREEN}Применяем стратегию:${NC} $NAME"

TMP_CONF="/tmp/zapret.new"
: > "$TMP_CONF"

# Всё ДО NFQWS_OPT
awk '
/option NFQWS_OPT '\''/ { exit }
{ print }
' "$CONF" >> "$TMP_CONF"

# Новый NFQWS_OPT
echo -e "\toption NFQWS_OPT '" >> "$TMP_CONF"
sed -n "${START_LINE},${END_LINE}p" "$DUMP_FILE" | sed '1d; s/^/\t\t/' >> "$TMP_CONF"
echo -e "\t'" >> "$TMP_CONF"

# Всё ПОСЛЕ старого NFQWS_OPT
awk '
found && print
/option NFQWS_OPT '\''/ { found=1; next }
found && /^\t'\''$/ { next }
' "$CONF" >> "$TMP_CONF"

mv "$TMP_CONF" "$CONF"

ZAPRET_RESTART

echo -e "${GREEN}Готово. Стратегия применена.${NC}"
