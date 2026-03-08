#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo -e "${YELLOW}Проверяем пакетный менеджер...${NC}"

if command -v apk >/dev/null 2>&1; then
    PKG="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
else
    echo -e "${RED}Не найден пакетный менеджер!${NC}"
    exit 1
fi

echo -e "${GREEN}Используется:${NC} $PKG"

echo -e "${YELLOW}Обновляем пакеты...${NC}"

if [ "$PKG" = "apk" ]; then
    apk update >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка обновления пакетов!${NC}"
        exit 1
    }
else
    opkg update >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка обновления пакетов!${NC}"
        exit 1
    }
fi

install_pkg() {
    pkg="$1"

    if [ "$PKG" = "apk" ]; then
        apk info -e "$pkg" >/dev/null 2>&1 && return
        echo -e "${GREEN}Устанавливаем:${NC} $pkg"
        apk add "$pkg" >/dev/null 2>&1 || {
            echo -e "\n${RED}Ошибка установки${NC} $pkg"
            exit 1
        }
    else
        opkg list-installed 2>/dev/null | grep -qF "^$pkg " && return
        echo -e "${GREEN}Устанавливаем:${NC} $pkg"
        opkg install "$pkg" >/dev/null 2>&1 || {
            echo -e "\n${RED}Ошибка установки${NC} $pkg"
            exit 1
        }
    fi
}

echo -e "${YELLOW}Проверяем зависимости...${NC}"

for pkg in wireguard-tools curl jq coreutils-base64; do
    install_pkg "$pkg"
done
