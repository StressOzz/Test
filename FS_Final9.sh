#!/bin/sh

# Конфиги и файлы
CONF="/etc/config/zapret"
DUMP_FILE="/opt/FS_dump.txt"
OUT_FILE="/opt/FS_filtered.txt"
STR_FILE="/opt/FS_Str.txt"
TMP_DIR="/tmp/zapret_configs"
HOSTLIST_FILE="/opt/zapret/ipset/zapret-hosts-user.txt"
RKN_URL="https://raw.githubusercontent.com/IndeecFOX/zapret4rocket/refs/heads/master/extra_strats/TCP/RKN/List.txt"
IP_SET_ALL="https://raw.githubusercontent.com/kartavkun/zapret-discord-youtube/refs/heads/main/hostlists/ipset-all.txt"
IP_SET="/opt/zapret/ipset/zapret-ip-user.txt"


# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
NC='\033[0m'

# Функция перезапуска Zapret
ZAPRET_RESTART() {
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
}
clear
echo -e "${MAGENTA}===== Проверка GitHub =====${NC}"
RATE=$(curl -s https://api.github.com/rate_limit | grep '"remaining"' | head -1 | awk '{print $2}' | tr -d ,)
[ -z "$RATE" ] && RATE_OUT="${RED}N/A${NC}" || RATE_OUT=$([ "$RATE" -eq 0 ] && echo -e "${RED}0${NC}" || echo -e "${GREEN}$RATE${NC}")
echo -n "API: "
curl -Is --connect-timeout 3 https://api.github.com >/dev/null 2>&1 && echo -e "${GREEN}ok${NC} | Limit: $RATE_OUT" || echo -e "${RED}fail${NC} | Limit: $RATE_OUT"

echo -e "${MAGENTA}===== Обновление стратегий NFQWS с GitHub =====${NC}"

# 1️⃣ Создаём временную папку
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# 2️⃣ Получаем список файлов из GitHub
GITHUB_API="https://api.github.com/repos/kartavkun/zapret-discord-youtube/contents/configs"
echo -e "${CYAN}Получаем список файлов из GitHub...${NC}"
wget -q -O "/tmp/files.json" "$GITHUB_API"

# 3️⃣ Скачиваем все файлы
echo -e "${GREEN}Скачиваем файлы из configs...${NC}"
cat /tmp/files.json | grep -o '"download_url": *"[^"]*"' | cut -d'"' -f4 | while read url; do
    fname="$(basename "$url")"
    echo -e "${CYAN}Скачиваем ${NC}$fname"
    wget -q -O "$TMP_DIR/$fname" "$url"
done

# 4️⃣ Собираем все файлы в один DUMP_FILE
echo -e "${GREEN}Собираем все стратегии в ${NC}$DUMP_FILE"
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
echo -e "${GREEN}Фильтруем TCP-блоки в ${NC}$OUT_FILE"
: > "$OUT_FILE"

include=0
skip_last_new=0

while IFS= read -r line; do
    case "$line" in
        ""|--*) ;;
        *) echo "$line" >> "$OUT_FILE"; continue ;;
    esac

    case "$line" in
        "--filter-tcp=80,443")
            include=1; skip_last_new=1; echo "$line" >> "$OUT_FILE"; continue ;;
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

# 6️⃣ Постобработка файлов
# echo -e "${CYAN}Применяем финальные правки к ${NC}$OUT_FILE${NC}"
sed -i \
    -e 's/%20//g' \
    -e 's/80,//g' \
    -e 's/"//g' \
    -e '/^--hostlist=/d' \
    -e '/^--ipset-exclude=/d' \
    -e 's|^--hostlist-exclude=.*|--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt|' \
    "$OUT_FILE"

# echo -e "${CYAN}Применяем финальные правки к ${NC}$DUMP_FILE${NC}"
sed -i'' \
    -e 's/%20//g' \
    -e 's/"//g' \
    -e 's/\$GAME_FILTER/1024-65535/g' \
    -e 's|^--hostlist=/opt/zapret/hostlists/list-google.txt.*|--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt|' \
    -e 's|^--hostlist=/opt/zapret/hostlists/list-general.txt.*|--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt|' \
    -e 's|^--hostlist-exclude=.*|--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt|' \
    -e 's|^--ipset=.*|--ipset=/opt/zapret/ipset/zapret-ip-user.txt|' \
    -e 's|^--ipset-exclude=.*|--ipset-exclude=/opt/zapret/ipset/zapret-ip-user-exclude.txt|' \
    -e '/^[[:space:]]*$/d' \
    "$DUMP_FILE"

# 7️⃣ Очистка временных файлов

rm -rf "$TMP_DIR" /tmp/files.json
echo -e "${GREEN}Стратегии готовы !${NC}\n"
read -p "Нажмите Enter..." dummy

# 8️⃣ Меню выбора стратегии по кругу
while true; do
    clear

    # Текущая стратегия
    CURRENT=$(sed -n "/^[[:space:]]*option NFQWS_OPT '/,/^'/p" "$CONF" | sed -n '2p' | grep -v "^[[:space:]]*'$" | head -1 | sed 's/^#//')
    [ -z "$CURRENT" ] && CURRENT="не выбрана"

    echo -e "${MAGENTA}===== Меню выбора стратегии =====${NC}\n"
    echo -e "${YELLOW}Текущая стратегия:${NC}$CURRENT\n"

    # Создаём карту меню
    MAP="/tmp/nfqws_menu.map"
    : > "$MAP"
    awk '/^#/ {print NR "|" substr($0,2)}' "$DUMP_FILE" > "$MAP"
    COUNT=$(wc -l < "$MAP" | tr -d ' ')

    i=1
    while IFS="|" read -r line name; do
        printf "${CYAN}%2d)${NC} %s\n" "$i" "$name"
        i=$((i+1))
    done < "$MAP"

    echo ""
    printf "${YELLOW}Выберите стратегию (1-%s): ${NC}" "$COUNT"
    read SEL

    # Любой неверный ввод — выход
    case "$SEL" in
        ''|*[!0-9]*)
            echo; exit 0
            ;;
    esac
    [ "$SEL" -lt 1 ] || [ "$SEL" -gt "$COUNT" ] && { echo; exit 0; }

    # Определяем строки выбранного блока
    START_LINE=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f1)
    NAME=$(sed -n "${SEL}p" "$MAP" | cut -d'|' -f2)
    NEXT_LINE=$(awk -v s="$START_LINE" 'NR>s && /^#/ {print NR; exit}' "$DUMP_FILE")
    [ -z "$NEXT_LINE" ] && NEXT_LINE=$(wc -l < "$DUMP_FILE" | tr -d ' '); NEXT_LINE=$((NEXT_LINE+1))

    # Сохраняем выбранную стратегию в STR_FILE
    {
        echo "#$NAME"
        sed -n "$((START_LINE+1)),$((NEXT_LINE-1))p" "$DUMP_FILE" | grep -v '^#'
    } > "$STR_FILE"

    # Вставляем стратегию в конфиг
    echo -e "\n${MAGENTA}Применяем новую стратегию${NC}"
    echo -e "\n${CYAN}Применяем стратегию ${NC}$CONF"
    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
    {
        echo "  option NFQWS_OPT '"
        grep -v '^[[:space:]]*$' "$STR_FILE"
        echo "'"
    } >> "$CONF"

    # Скачиваем список РКН и IP
    echo -e "${CYAN}Применяем списки ${NC}РКН ${CYAN}и ${NC}IP"
    curl -fsSL "$RKN_URL" -o "$HOSTLIST_FILE" || { echo -e "${RED}Не удалось скачать список РКН${NC}"; exit 1; }
    curl -fsSL "$IP_SET_ALL" -o "$IP_SET" || { echo -e "${RED}Не удалось скачать список IP${NC}"; exit 1; }

    # Перезапуск Zapret
    echo -e "${CYAN}Применяем настройки ${NC}Zapret"
    ZAPRET_RESTART

    echo -e "${GREEN}Стратегия ${NC}${NAME} ${GREEN}применена!${NC}\n"
    echo -e "${YELLOW}Проверьте работу стратегии!${NC}\n"

    # Проверка работы стратегии
    while true; do
        read -p "$(echo -e "${YELLOW}Стратегия работает? ${NC}Y/N: ")" RESP
        case "$RESP" in
            [Yy])
                break
                ;;
            [Nn])
                echo -e "\n${MAGENTA}Возвращаем настройки по умолчанию${NC}"
                for i in 1 2 3 4; do rm -f "/opt/zapret/ipset/cust$i.txt"; done
                /etc/init.d/zapret stop >/dev/null 2>&1
                echo -e "${CYAN}Возвращаем ${NC}настройки, стратегию и hostlist к значениям по умолчанию${NC}"
                cp -f /opt/zapret/ipset_def/* /opt/zapret/ipset/
                chmod +x /opt/zapret/restore-def-cfg.sh && /opt/zapret/restore-def-cfg.sh
                ZAPRET_RESTART
                echo -e "Настройки по умолчанию ${GREEN}возвращены!${NC}\n"
                break
                ;;
            *)
                echo -e "${RED}Неверный ввод, введите Y или N${NC}"
                ;;
        esac
    done

    read -p "Нажмите Enter..." dummy
done
