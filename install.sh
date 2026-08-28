#!/bin/sh

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
NC='\033[0m'

if command -v opkg >/dev/null 2>&1; then
    CONFZ="/etc/opkg/distfeeds.conf"
    UPDATE="opkg update"
    INSTALL="opkg install"
    RAZ="ipk"
else
    CONFZ="/etc/apk/repositories.d/distfeeds.list"
    UPDATE="apk update"
    INSTALL="apk add --allow-untrusted"
    RAZ="apk"
fi

clear

MIRROR=""
CURRENT_MIRROR=$(head -n1 "$CONFZ" | sed 's|https://||;s|/releases/.*||')

echo -e "${CYAN}Проверяем доступность ${NC}$CURRENT_MIRROR"

if ! wget -q --spider --timeout=5 "https://$CURRENT_MIRROR/releases/" >/dev/null 2>&1; then
    echo -e "$CURRENT_MIRROR ${RED}недоступен!${NC}"

    if wget -q --spider --timeout=5 "https://mirror-03.infra.openwrt.org/releases/" >/dev/null 2>&1; then
        MIRROR="mirror-03.infra.openwrt.org"
    elif wget -q --spider --timeout=5 "https://ftp.snt.utwente.nl/pub/software/openwrt/releases/" >/dev/null 2>&1; then
        MIRROR="ftp.snt.utwente.nl/pub/software/openwrt"
    elif wget -q --spider --timeout=5 "https://mirror.berlin.freifunk.net/downloads.openwrt/releases/" >/dev/null 2>&1; then
        MIRROR="mirror.berlin.freifunk.net/downloads.openwrt"
    elif wget -q --spider --timeout=5 "https://mirror.sjtu.edu.cn/openwrt/releases/" >/dev/null 2>&1; then
        MIRROR="mirror.sjtu.edu.cn/openwrt"
    fi

    if [ -n "$MIRROR" ]; then
        echo -e "${CYAN}Переключаемся на ${NC}$MIRROR"
        sed -i "s|https://.*/releases/|https://$MIRROR/releases/|g" "$CONFZ"
    else
        echo -e "${RED}Резервные зеркала недоступны!${NC}"
    fi
else
    echo -e "$CURRENT_MIRROR ${GREEN}доступен!${NC}"
fi

echo

FILES=$(find /root -maxdepth 1 -type f -name "*.${RAZ}" | sort)

[ -z "$FILES" ] && {
    echo -e "${RED}Файлы .${RAZ} не найдены.${NC}"
    exit 1
}

echo -e "${MAGENTA}Найденные файлы .${RAZ}:${NC}"
echo

i=1
for f in $FILES; do
    eval "PKG_$i=\"$f\""
    echo -e "${CYAN}$i${NC} - ${GREEN}$(basename "$f")${NC}"
    i=$((i + 1))
done

echo
printf "${YELLOW}Введите порядок установки (например: 2 1 3): ${NC}"
read ORDER

echo
echo -e "${MAGENTA}Обновляем список пакетов...${NC}"

$UPDATE || {
    echo -e "${RED}Ошибка обновления пакетов.${NC}"
    exit 1
}

echo
echo -e "${MAGENTA}Начинаем установку:${NC}"
echo

for n in $ORDER; do
    eval "FILE=\$PKG_$n"

    if [ -f "$FILE" ]; then
        NAME=$(basename "$FILE")

        echo -e "${GREEN}>>> Устанавливаем:${NC} ${CYAN}$NAME${NC}"

        $INSTALL "$FILE" || {
            echo -e "${RED}Ошибка установки $NAME${NC}"
            exit 1
        }

        echo -e "${GREEN}✓ ${CYAN}$NAME${GREEN} установлен${NC}"
        echo
    else
        echo -e "${RED}Неверный номер: $n${NC}"
    fi
done

echo -e "${MAGENTA}================================${NC}"
echo -e "${GREEN}✓ Установка завершена.${NC}"
echo -e "${MAGENTA}================================${NC}"
