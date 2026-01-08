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

echo -e "\n${YELLOW}=== Выбор стратегии NFQWS ===${NC}"

# Собираем список стратегий
MAP_FILE="/tmp/nfqws_menu.map"
: > "$MAP_FILE"

awk '
/^#/ {
    name=substr($0,2)
    print NR "|" name
}
' "$DUMP_FILE" > "$MAP_FILE"

COUNT=$(wc -l < "$MAP_FILE")

[ "$COUNT" -eq 0 ] && {
    echo -e "${RED}Стратегии не найдены${NC}"
    exit 1
}

# Печатаем меню
i=1
while IFS="|" read -r line name; do
    printf "%2d) %s\n" "$i" "$name"
    i=$((i+1))
done < "$MAP_FILE"

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

START_LINE=$(sed -n "${SEL}p" "$MAP_FILE" | cut -d'|' -f1)

# Определяем конец блока
END_LINE=$(awk -v s="$START_LINE" '
NR > s && /^#/ { print NR-1; exit }
END { print NR }
' "$DUMP_FILE")

echo -e "${GREEN}Применяем стратегию:${NC} $(sed -n "${SEL}p" "$MAP_FILE" | cut -d'|' -f2)"

# Формируем новый NFQWS_OPT
TMP_OPT="/tmp/NFQWS_OPT.new"
: > "$TMP_OPT"

sed -n "${START_LINE},${END_LINE}p" "$DUMP_FILE" | sed '1d' >> "$TMP_OPT"

# Переписываем конфиг
sed -i'' "/option NFQWS_OPT '/,\$c\
\toption NFQWS_OPT '\\
$(sed 's/^/\t\t/' "$TMP_OPT")\
\t'
" "$CONF"

ZAPRET_RESTART

echo -e "${GREEN}Готово. Стратегия применена.${NC}"
