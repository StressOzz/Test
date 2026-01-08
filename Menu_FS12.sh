#!/bin/sh

DUMP_FILE="/opt/FS_dump.txt"
OUT_FILE="/opt/FS_Str.txt"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

[ ! -f "$DUMP_FILE" ] && { echo -e "${RED}Файл $DUMP_FILE не найден${NC}"; exit 1; }

# 1️⃣ Создаём меню стратегий
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

case "$SEL" in
    ''|*[!0-9]*)
        echo -e "${RED}Неверный ввод${NC}"
        exit 1
        ;;
esac

[ "$SEL" -lt 1 ] || [ "$SEL" -gt "$COUNT" ] && { echo -e "${RED}Номер вне диапазона${NC}"; exit 1; }

# 2️⃣ Определяем строки выбранного блока
START_LINE=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f1)
NAME=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f2)

# Находим строку следующего #
NEXT_LINE=$(awk -v s="$START_LINE" 'NR>s && /^#/ {print NR; exit}' "$DUMP_FILE")
[ -z "$NEXT_LINE" ] && NEXT_LINE=$(wc -l < "$DUMP_FILE" | tr -d ' '); NEXT_LINE=$((NEXT_LINE+1))

# 3️⃣ Сохраняем выбранную стратегию в OUT_FILE
echo -e "${GREEN}Сохраняем стратегию в $OUT_FILE:${NC} $NAME"
{
    # Заголовок сверху
    echo "#$NAME"
    # Сам блок стратегии (строки между текущим # и следующим #)
    sed -n "$((START_LINE+1)),$((NEXT_LINE-1))p" "$DUMP_FILE"
} > "$OUT_FILE"

echo -e "${GREEN}Готово. Стратегия сохранена в $OUT_FILE${NC}"
