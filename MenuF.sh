#!/bin/sh

# Конфиг и файлы
CONF="/etc/config/zapret"
DUMP_FILE="/opt/FS_dump.txt"
STR_FILE="/opt/FS_Str.txt"

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

# Проверка файла со стратегиями
[ ! -f "$DUMP_FILE" ] && { echo -e "${RED}Файл $DUMP_FILE не найден${NC}"; exit 1; }

# Создаём меню стратегий
MAP="/tmp/nfqws_menu.map"
: > "$MAP"
awk '/^#/ {print NR "|" substr($0,2)}' "$DUMP_FILE" > "$MAP"

COUNT=$(wc -l < "$MAP" | tr -d ' ')

[ "$COUNT" -eq 0 ] && { echo -e "${RED}Стратегии не найдены${NC}"; exit 1; }

echo -e "\n${YELLOW}=== Выбор стратегии NFQWS ===${NC}"
i=1
while IFS="|" read -r line name; do
    printf "%2d) %s\n" "$i" "$name"
    i=$((i+1))
done < "$MAP"

echo ""
printf "Выберите стратегию (1-%s): " "$COUNT"
read SEL

# Проверка ввода
case "$SEL" in
    ''|*[!0-9]*)
        echo -e "${RED}Неверный ввод${NC}"
        exit 1
        ;;
esac

[ "$SEL" -lt 1 ] || [ "$SEL" -gt "$COUNT" ] && { echo -e "${RED}Номер вне диапазона${NC}"; exit 1; }

# Определяем строки выбранного блока
START_LINE=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f1)
NAME=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f2)

# Находим строку следующего #
NEXT_LINE=$(awk -v s="$START_LINE" 'NR>s && /^#/ {print NR; exit}' "$DUMP_FILE")
[ -z "$NEXT_LINE" ] && NEXT_LINE=$(wc -l < "$DUMP_FILE" | tr -d ' '); NEXT_LINE=$((NEXT_LINE+1))

# Сохраняем выбранную стратегию в STR_FILE
echo -e "${GREEN}Сохраняем выбранную стратегию в $STR_FILE:${NC} $NAME"
{
    echo "#$NAME"
    sed -n "$((START_LINE+1)),$((NEXT_LINE-1))p" "$DUMP_FILE" | grep -v '^#'
} > "$STR_FILE"

# Применяем стратегию в конфиг
echo -e "${GREEN}Вставляем стратегию из $STR_FILE в $CONF${NC}"

# Удаляем старый блок NFQWS_OPT
sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"

# Вставляем новый блок
{
    echo "  option NFQWS_OPT '"
    sed "s/^/    /" "$STR_FILE"
    echo "  '"
} >> "$CONF"

# Перезапуск Zapret
echo -e "${YELLOW}Применяем настройки Zapret...${NC}"
chmod +x /opt/zapret/sync_config.sh
/opt/zapret/sync_config.sh
/etc/init.d/zapret restart >/dev/null 2>&1

echo -e "${GREEN}Готово. Стратегия '${NAME}' применена.${NC}"
