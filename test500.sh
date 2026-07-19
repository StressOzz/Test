#!/bin/sh
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; NC="\033[0m"
DELETE="opkg remove"; INSTALL="opkg install"; UPDATE="opkg update"; RAZ="ipk"; SUF=""
command -v apk >/dev/null 2>&1 && INSTALL="apk add --allow-untrusted" && UPDATE="apk update" && RAZ="apk" && SUF="r" && DELETE="apk del"
ARCH_MT=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2)
MT_VERSION="0.7.0"
FILE_MT="/tmp/magitrickle.$RAZ"
URL="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-${SUF}1_openwrt_${ARCH_MT}.$RAZ"
clear
echo -e "${YELLOW}Удаляем ${CYAN}MagiTrickle${NC}"; $DELETE magitrickle >/dev/null 2>&1
echo -e "${YELLOW}Скачиваем:\n${CYAN}$URL${NC}"
curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка скачивания${NC}\n"; exit 1; }
echo -e "${YELLOW}Устанавливаем:\n${CYAN}$(basename "$URL")${NC}"
$UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка обновления пакетов${NC}\n"; exit 1; }
$INSTALL "$FILE_MT" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка установки${NC}\n"; exit 1; }
echo -e "\n${GREEN}MagiTrickle установлен (обновлён)${NC}\n"
