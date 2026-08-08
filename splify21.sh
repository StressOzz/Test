#!/bin/sh

# ==============================
# Цвета
# ==============================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BLUE='\033[0;34m'
NC='\033[0m'

TMP="/tmp/release_install"
mkdir -p "$TMP"

. /etc/openwrt_release

ARCH="$DISTRIB_ARCH"

# ==============================
# Архитектура Steer
# ==============================

case "$ARCH" in
    aarch64_cortex-a53)
        STEER_ARCH="aarch64_cortex-a53"
        ;;
    aarch64_generic)
        STEER_ARCH="aarch64_generic"
        ;;
    arm_cortex-a7_neon-vfpv4)
        STEER_ARCH="arm_cortex-a7_neon-vfpv4"
        ;;
    mipsel_24kc)
        STEER_ARCH="mipsel_24kc"
        ;;
    mips_24kc)
        STEER_ARCH="mips_24kc"
        ;;
    x86_64)
        STEER_ARCH="x86_64"
        ;;
    *)
        echo -e "${RED}✗ Неподдерживаемая архитектура:${NC} ${YELLOW}$ARCH${NC}"
        rm -rf "$TMP"
        exit 1
        ;;
esac

# ==============================
# Получение последнего tag
# ==============================

get_latest_tag() {
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" |
        sed 's#.*/tag/##'
}

# ==============================
# Steer
# ==============================

install_steer() {
    echo -e "\n${MAGENTA}━━━ Steer ━━━${NC}"

    if apk info -e steer >/dev/null 2>&1 || \
       apk info -e steer-extended >/dev/null 2>&1; then

        echo -e "${YELLOW}Steer уже установлен${NC}"
        echo -e "${CYAN}Удаляем...${NC}"

        if apk del steer-extended >/dev/null 2>&1 || apk del steer >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Steer успешно удалён${NC}"
        else
            echo -e "${RED}✗ Ошибка удаления Steer${NC}"
            return 1
        fi

        return 0
    fi

    echo -e "${CYAN}Steer не установлен — устанавливаем${NC}"
    echo -e "${CYAN}Получаем последнюю версию...${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"

    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Steer${NC}"
        return 1
    fi

    VER="${TAG#v}"

    FILE="steer-extended-${VER}-1_${STEER_ARCH}.apk"
    URL="https://github.com/xyzmean/steer/releases/download/${TAG}/${FILE}"

    echo -e "${YELLOW}Версия:${NC}       ${GREEN}$VER${NC}"
    echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$STEER_ARCH${NC}"
    echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"

    echo -e "${CYAN}Скачиваем...${NC}"

    if ! curl -fL "$URL" -o "$TMP/$FILE"; then
        echo -e "${RED}✗ Ошибка скачивания Steer${NC}"
        rm -f "$TMP/$FILE"
        return 1
    fi

    echo -e "${CYAN}Устанавливаем...${NC}"

    if ! apk add --allow-untrusted "$TMP/$FILE"; then
        echo -e "${RED}✗ Ошибка установки Steer${NC}"
        rm -f "$TMP/$FILE"
        return 1
    fi

    rm -f "$TMP/$FILE"

    echo -e "${GREEN}✓ Steer успешно установлен${NC}"
}

# ==============================
# Splify2
# ==============================

install_splify() {
    echo -e "\n${MAGENTA}━━━ Splify2 ━━━${NC}"

    if apk info -e luci-app-splify2 >/dev/null 2>&1; then

        echo -e "${YELLOW}Splify2 уже установлен${NC}"
        echo -e "${CYAN}Удаляем...${NC}"

        if apk del luci-app-splify2 >/dev/null 2>&1; then
            echo -e "${GREEN}✓ Splify2 успешно удалён${NC}"
        else
            echo -e "${RED}✗ Ошибка удаления Splify2${NC}"
            return 1
        fi

        return 0
    fi

    echo -e "${CYAN}Splify2 не установлен — устанавливаем${NC}"
    echo -e "${CYAN}Получаем последнюю версию...${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"

    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Splify2${NC}"
        return 1
    fi

    VER="${TAG#v}"

    FILE="luci-app-splify2-${VER}-1_noarch.apk"
    URL="https://github.com/xyzmean/splify2/releases/download/${TAG}/${FILE}"

    echo -e "${YELLOW}Версия:${NC}       ${GREEN}$VER${NC}"
    echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}noarch${NC}"
    echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"

    echo -e "${CYAN}Скачиваем...${NC}"

    if ! curl -fL "$URL" -o "$TMP/$FILE"; then
        echo -e "${RED}✗ Ошибка скачивания Splify2${NC}"
        rm -f "$TMP/$FILE"
        return 1
    fi

    echo -e "${CYAN}Устанавливаем...${NC}"

    if ! apk add --allow-untrusted "$TMP/$FILE"; then
        echo -e "${RED}✗ Ошибка установки Splify2${NC}"
        rm -f "$TMP/$FILE"
        return 1
    fi

    rm -f "$TMP/$FILE"

    echo -e "${GREEN}✓ Splify2 успешно установлен${NC}"
}

# ==============================
# Запуск
# ==============================

clear

echo -e "${MAGENTA}╔══════════════════════════════════════╗${NC}"
echo -e "${MAGENTA}║${NC}      ${CYAN}Установка / удаление релизов${NC}     ${MAGENTA}║${NC}"
echo -e "${MAGENTA}╚══════════════════════════════════════╝${NC}"

echo -e "\n${YELLOW}Архитектура OpenWrt:${NC} ${GREEN}$ARCH${NC}"

install_steer
install_splify

rm -rf "$TMP"

echo -e "\n${MAGENTA}════════════════════════════════════════${NC}"
echo -e "${GREEN}✓ Операции завершены${NC}"
echo -e "${MAGENTA}════════════════════════════════════════${NC}"
