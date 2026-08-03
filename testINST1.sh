#!/bin/sh

# Цвета
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

FILES=$(find /root -maxdepth 1 -type f -name "*.apk" | sort)

[ -z "$FILES" ] && {
    echo -e "${RED}APK-файлы не найдены.${NC}"
    exit 1
}

echo -e "${MAGENTA}Найденные APK-файлы:${NC}"
echo

i=1
for f in $FILES; do
    eval "APK_$i=\"$f\""
    echo -e "${CYAN}$i${NC} - ${GREEN}$(basename "$f")${NC}"
    i=$((i + 1))
done

echo
printf "${YELLOW}Введите порядок установки (например: 2 1 3): ${NC}"
read ORDER

echo
echo -e "${MAGENTA}Обновляем список пакетов...${NC}"
apk update || {
    echo -e "${RED}Ошибка обновления пакетов.${NC}"
    exit 1
}

echo
echo -e "${MAGENTA}Начинаем установку:${NC}"
echo

for n in $ORDER; do
    eval "APK=\$APK_$n"

    if [ -f "$APK" ]; then
        NAME=$(basename "$APK")

        echo -e "${GREEN}>>> Устанавливаем:${NC} ${CYAN}$NAME${NC}"

        apk add --allow-untrusted "$APK" || {
            echo -e "${RED}Ошибка установки $NAME${NC}"
            exit 1
        }

        echo -e "${GREEN}✓ ${CYAN}$NAME установлен${NC}"
        echo
    else
        echo -e "${RED}Неверный номер: $n${NC}"
    fi
done

echo -e "${MAGENTA}================================${NC}"
echo -e "${GREEN}✓ Установка завершена.${NC}"
echo -e "${MAGENTA}================================${NC}"
