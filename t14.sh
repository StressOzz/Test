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
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" 2>/dev/null |
        sed 's#.*/tag/##'
}

# ==============================
# Получение установленной версии
# ==============================

get_version() {
    apk list -I 2>/dev/null |
        grep -E "^$1-[0-9]" |
        head -n1 |
        sed -E "s/^$1-([^ ]+).*/\1/"
}

# ==============================
# Проверка версии
# ==============================

version_match() {
    case "$1" in
        "$2"|"$2"-*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# ==============================
# Очистка
# ==============================

cleanup() {
    for DIR in /etc /usr /www /root /opt /tmp; do
        [ -d "$DIR" ] || continue

        find "$DIR" -depth \
            \( -iname 'steer' -o -iname 'steer-*' \
            -o -iname 'splify2' -o -iname 'splify2-*' \) \
            -print 2>/dev/null |
        while read -r FILE; do
            echo -e "${RED}Удаляем:${NC} $FILE"
            rm -rf -- "$FILE"
        done
    done
}

# ==============================
# Steer
# ==============================

install_steer() {
    echo -e "\n${MAGENTA}━━━ Steer ━━━${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"

    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Steer${NC}"
        return 1
    fi

    VER="${TAG#v}"

    if apk info -e steer >/dev/null 2>&1; then
        CURRENT="$(get_version steer)"
    elif apk info -e steer-extended >/dev/null 2>&1; then
        CURRENT="$(get_version steer-extended)"
    else
        CURRENT=""
    fi

    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${CURRENT:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}$VER${NC}"
    echo -e "${YELLOW}Архитектура:${NC} ${GREEN}$STEER_ARCH${NC}"

    if [ -n "$CURRENT" ] && version_match "$CURRENT" "$VER"; then
        echo -e "${GREEN}✓ Версия актуальна${NC}"
        return 0
    fi

    if [ -n "$CURRENT" ]; then
        echo -e "${CYAN}Обновляем:${NC} ${YELLOW}$CURRENT${NC} → ${GREEN}$VER${NC}"
    else
        echo -e "${CYAN}Steer не установлен — устанавливаем${NC}"
    fi

    FILE="steer-extended-${VER}-1_${STEER_ARCH}.apk"
    URL="https://github.com/xyzmean/steer/releases/download/${TAG}/${FILE}"

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

    echo -e "${GREEN}✓ Steer успешно установлен/обновлён${NC}"
}

# ==============================
# Удаление Steer
# ==============================

remove_steer() {
    echo -e "\n${MAGENTA}━━━ Удаление Steer ━━━${NC}"

    if ! apk info -e steer >/dev/null 2>&1 &&
       ! apk info -e steer-extended >/dev/null 2>&1; then
        echo -e "${YELLOW}Steer не установлен${NC}"
        return
    fi

    echo -e "${CYAN}Удаляем Steer...${NC}"

    if apk del steer-extended >/dev/null 2>&1 ||
       apk del steer >/dev/null 2>&1; then

        cleanup

        echo -e "${GREEN}✓ Steer успешно удалён${NC}"
    else
        echo -e "${RED}✗ Ошибка удаления Steer${NC}"
    fi
}

# ==============================
# Splify2
# ==============================

install_splify() {
    echo -e "\n${MAGENTA}━━━ Splify2 ━━━${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"

    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Splify2${NC}"
        return 1
    fi

    VER="${TAG#v}"

    if apk info -e luci-app-splify2 >/dev/null 2>&1; then
        CURRENT="$(get_version luci-app-splify2)"
    else
        CURRENT=""
    fi

    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${CURRENT:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}$VER${NC}"
    echo -e "${YELLOW}Архитектура:${NC} ${GREEN}noarch${NC}"

    if [ -n "$CURRENT" ] && version_match "$CURRENT" "$VER"; then
        echo -e "${GREEN}✓ Версия актуальна${NC}"
        return 0
    fi

    if [ -n "$CURRENT" ]; then
        echo -e "${CYAN}Обновляем:${NC} ${YELLOW}$CURRENT${NC} → ${GREEN}$VER${NC}"
    else
        echo -e "${CYAN}Splify2 не установлен — устанавливаем${NC}"
    fi

    FILE="luci-app-splify2-${VER}-1_noarch.apk"
    URL="https://github.com/xyzmean/splify2/releases/download/${TAG}/${FILE}"

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

    echo -e "${GREEN}✓ Splify2 успешно установлен/обновлён${NC}"
}

# ==============================
# Удаление Splify2
# ==============================

remove_splify() {
    echo -e "\n${MAGENTA}━━━ Удаление Splify2 ━━━${NC}"

    if ! apk info -e luci-app-splify2 >/dev/null 2>&1; then
        echo -e "${YELLOW}Splify2 не установлен${NC}"
        return
    fi

    echo -e "${CYAN}Удаляем Splify2...${NC}"

    if apk del luci-app-splify2 >/dev/null 2>&1; then

        cleanup

        echo -e "${GREEN}✓ Splify2 успешно удалён${NC}"
    else
        echo -e "${RED}✗ Ошибка удаления Splify2${NC}"
    fi
}

# ==============================
# Меню
# ==============================

MENU() {
    while true; do
clear
        echo -e "${BLUE}Собираем информацию о версиях${NC}"
        STEER_TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"
        STEER_VER="${STEER_TAG#v}"

        if apk info -e steer >/dev/null 2>&1; then
            STEER_CUR="$(get_version steer)"
        elif apk info -e steer-extended >/dev/null 2>&1; then
            STEER_CUR="$(get_version steer-extended)"
        else
            STEER_CUR=""
        fi

        SPLIFY_TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"
        SPLIFY_VER="${SPLIFY_TAG#v}"

        SPLIFY_CUR="$(get_version luci-app-splify2)"
clear
        echo -e "${BLUE}━━━━━━Steer & splify2━━━━━━${NC}"
        
        echo -e   "  ${MAGENTA}Steer${NC}"
        echo -e   "    Установлена: ${GREEN}${STEER_CUR:-нет}${NC}"
        echo -e   "    GitHub:      ${GREEN}${STEER_VER:-ошибка}${NC}"

        if [ -z "$STEER_CUR" ]; then
            echo -e "    Статус:      ${RED}не установлен${NC}"
        elif version_match "$STEER_CUR" "$STEER_VER"; then
            echo -e "    Статус:      ${GREEN}актуален${NC}"
        else
            echo -e "    Статус:      ${YELLOW}доступно обновление${NC}"
        fi

        echo
        echo -e "  ${MAGENTA}Splify2${NC}"
        echo -e "    Установлена: ${GREEN}${SPLIFY_CUR:-нет}${NC}"
        echo -e "    GitHub:      ${GREEN}${SPLIFY_VER:-ошибка}${NC}"

        if [ -z "$SPLIFY_CUR" ]; then
            echo -e "    Статус:      ${RED}не установлен${NC}"
        elif version_match "$SPLIFY_CUR" "$SPLIFY_VER"; then
            echo -e "    Статус:      ${GREEN}актуален${NC}"
        else
            echo -e "    Статус:      ${YELLOW}доступно обновление${NC}"
        fi

        echo

        echo -e "${GREEN}1)${NC} Установить / обновить Steer"
        echo -e "${RED}2)${NC} Удалить Steer"
        echo
        echo -e "${GREEN}3)${NC} Установить / обновить Splify2"
        echo -e "${RED}4)${NC} Удалить Splify2"
        echo
        echo -e "${CYAN}Enter)${NC} Выход"

        echo
echo -en "${YELLOW}Выберите пункт:${NC} "
        read -r CHOICE

        case "$CHOICE" in
            1)
                install_steer
                pause
                ;;
            2)
                remove_steer
                pause
                ;;
            3)
                install_splify
                pause
                ;;
            4)
                remove_splify
                pause
                ;;
            0)
                break
                ;;
            *)
                exit 0
                ;;
        esac
    done
}

# ==============================
# Запуск
# ==============================

trap 'rm -rf "$TMP"' EXIT

MENU
