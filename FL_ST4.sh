#!/bin/sh

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}=== Обновление стратегий NFQWS с GitHub ===${NC}"

GITHUB_API="https://api.github.com/repos/kartavkun/zapret-discord-youtube/contents/configs"
TMP_DIR="/tmp/zapret_configs"
DUMP_FILE="/root/nfqws_dump.txt"
OUT_FILE="/root/nfqws_filtered.txt"

# 1️⃣ Создаём временную папку
echo -e "${GREEN}Создаём временную папку $TMP_DIR${NC}"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 2️⃣ Получаем список файлов из GitHub
echo -e "${GREEN}Получаем список файлов из GitHub...${NC}"
wget -q -O "/tmp/files.json" "$GITHUB_API"

# 3️⃣ Скачиваем все файлы
echo -e "${GREEN}Скачиваем файлы из configs...${NC}"
cat /tmp/files.json | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read url; do
    fname="$(basename "$url")"
    echo -e "${YELLOW}Скачиваем $fname${NC}"
    wget -q -O "$TMP_DIR/$fname" "$url"
done

# 4️⃣ Собираем все файлы в один nfqws_dump.txt
echo -e "${GREEN}Собираем все стратегии в $DUMP_FILE${NC}"
: > "$DUMP_FILE"

for f in "$TMP_DIR"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    echo "#$name" >> "$DUMP_FILE"

    in_block=0
    while IFS= read -r line; do
        case "$line" in
            'NFQWS_OPT="'*) in_block=1; continue ;;
            '"'*) in_block=0; continue ;;
        esac

        [ $in_block -eq 1 ] && echo "$line" | tr ' ' '\n' | grep '^--' >> "$DUMP_FILE"
    done < "$f"

    echo "" >> "$DUMP_FILE"
done

# 5️⃣ Фильтруем нужные TCP блоки
echo -e "${GREEN}Фильтруем TCP-блоки для nfqws_filtered.txt${NC}"
: > "$OUT_FILE"

include=0
skip_last_new=0

while IFS= read -r line; do
    case "$line" in
        ""|--*) ;;
        *) echo "$line" >> "$OUT_FILE"; continue ;;
    esac

    case "$line" in
        "--filter-tcp=2053,2083,2087,2096,8443")
            include=1; skip_last_new=0; echo "$line" >> "$OUT_FILE"; continue
            ;;
        "--filter-tcp=80,443")
            include=1; skip_last_new=1; echo "$line" >> "$OUT_FILE"; continue
            ;;
    esac

    [ $include -eq 1 ] && {
        if [ "$line" = "--new" ]; then
            [ $skip_last_new -eq 1 ] && echo "" >> "$OUT_FILE" || echo "$line" >> "$OUT_FILE"
            include=0
        else
            echo "$line" >> "$OUT_FILE"
        fi
    }
done < "$DUMP_FILE"

# 6️⃣ Постобработка финального файла
echo -e "${GREEN}Применяем финальные правки к $OUT_FILE${NC}"
sed -i \
    -e 's/%20//g' \
    -e 's/80,//g' \
    -e 's/"//g' \
    -e '/^--hostlist=/d' \
    -e '/^--ipset-exclude=/d' \
    -e 's|^--hostlist-exclude=.*|--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt|' \
    "$OUT_FILE"

# 7️⃣ Очистка временных файлов
echo -e "${GREEN}Удаляем временные файлы...${NC}"
rm -rf "$TMP_DIR" /tmp/files.json

echo -e "${YELLOW}=== Готово! ===${NC}"
echo -e "${GREEN}Полный сборный файл: $DUMP_FILE${NC}"
echo -e "${GREEN}Финальный фильтрованный файл: $OUT_FILE${NC}"
