#!/bin/sh

# ============================================================
# Цвета
# ============================================================

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

# ============================================================
# Архитектура Steer
# ============================================================

case "$ARCH" in
    aarch64_cortex-a53|aarch64_generic|arm_cortex-a7_neon-vfpv4|mipsel_24kc|mips_24kc|x86_64)
        STEER_ARCH="$ARCH"
        ;;
    *)
        echo -e "${RED}✗ Неподдерживаемая архитектура:${NC} $ARCH"
        exit 1
        ;;
esac

# ============================================================
# Последний tag GitHub
# ============================================================

get_latest_tag() {
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" 2>/dev/null |
        sed 's#.*/tag/##'
}

# ============================================================
# Версия установленного пакета
# ============================================================

get_version() {
    apk list --installed "$1" 2>/dev/null |
        sed -n "s/^$1-\([^ ]*\).*/\1/p" |
        head -n1 |
        sed 's/-r[0-9]*$//'
}

# ============================================================
# Очистка файлов
# ============================================================

cleanup_files() {
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

# ============================================================
# Установка / обновление Steer
# ============================================================

STEER() {
    clear

    TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"
    GITHUB="${TAG#v}"

    if apk info -e steer-extended >/dev/null 2>&1; then
        INSTALLED="$(get_version steer-extended)"
    elif apk info -e steer >/dev/null 2>&1; then
        INSTALLED="$(get_version steer)"
    else
        INSTALLED=""
    fi

    echo -e "${MAGENTA}╔════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}          ${CYAN}Steer${NC}                 ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════╝${NC}"

    echo
    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${INSTALLED:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}${GITHUB:-ошибка}${NC}"
    echo -e "${YELLOW}Архитектура:${NC} ${GREEN}$STEER_ARCH${NC}"

    echo
    if [ -n "$INSTALLED" ] && [ "$INSTALLED" = "$GITHUB" ]; then
        echo -e "${GREEN}✓ Версия актуальна${NC}"
    elif [ -n "$INSTALLED" ]; then
        echo -e "${YELLOW}→ Доступно обновление${NC}"
    else
        echo -e "${CYAN}→ Steer не установлен${NC}"
    fi

    echo
    echo -e "${CYAN}1${NC}) $([ -n "$INSTALLED" ] && echo "Обновить" || echo "Установить")"
    echo -e "${RED}2${NC}) Удалить"
    echo -e "${YELLOW}0${NC}) Назад"

    echo
    printf "${MAGENTA}➜ ${NC}"
    read -r CHOICE

    case "$CHOICE" in
        1)
            if [ -n "$INSTALLED" ] && [ "$INSTALLED" = "$GITHUB" ]; then
                echo -e "\n${GREEN}✓ Уже установлена актуальная версия${NC}"
                sleep 2
                return
            fi

            FILE="steer-extended-${GITHUB}-1_${STEER_ARCH}.apk"
            URL="https://github.com/xyzmean/steer/releases/download/${TAG}/${FILE}"

            echo -e "\n${CYAN}Скачиваем:${NC} $FILE"

            if ! curl -fLs "$URL" -o "$TMP/$FILE"; then
                echo -e "${RED}✗ Ошибка скачивания${NC}"
                rm -f "$TMP/$FILE"
                sleep 2
                return
            fi

            echo -e "${CYAN}Устанавливаем...${NC}"

            if apk add --allow-untrusted "$TMP/$FILE"; then
                echo -e "${GREEN}✓ Steer установлен/обновлён${NC}"
            else
                echo -e "${RED}✗ Ошибка установки${NC}"
            fi

            rm -f "$TMP/$FILE"
            sleep 2
            ;;

        2)
            echo -e "\n${CYAN}Удаляем Steer...${NC}"

            apk del steer-extended >/dev/null 2>&1 ||
            apk del steer >/dev/null 2>&1

            cleanup_files

            echo -e "${GREEN}✓ Steer удалён${NC}"
            sleep 2
            ;;

        0)
            return
            ;;

        *)
            echo -e "${RED}✗ Неверный выбор${NC}"
            sleep 1
            ;;
    esac
}

# ============================================================
# Установка / обновление Splify2
# ============================================================

SPLIFY() {
    clear

    TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"
    GITHUB="${TAG#v}"

    if apk info -e luci-app-splify2 >/dev/null 2>&1; then
        INSTALLED="$(get_version luci-app-splify2)"
    else
        INSTALLED=""
    fi

    echo -e "${MAGENTA}╔════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}         ${CYAN}Splify2${NC}                ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚════════════════════════════════════╝${NC}"

    echo
    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${INSTALLED:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}${GITHUB:-ошибка}${NC}"
    echo -e "${YELLOW}Архитектура:${NC} ${GREEN}noarch${NC}"

    echo
    if [ -n "$INSTALLED" ] && [ "$INSTALLED" = "$GITHUB" ]; then
        echo -e "${GREEN}✓ Версия актуальна${NC}"
    elif [ -n "$INSTALLED" ]; then
        echo -e "${YELLOW}→ Доступно обновление${NC}"
    else
        echo -e "${CYAN}→ Splify2 не установлен${NC}"
    fi

    echo
    echo -e "${CYAN}1${NC}) $([ -n "$INSTALLED" ] && echo "Обновить" || echo "Установить")"
    echo -e "${RED}2${NC}) Удалить"
    echo -e "${YELLOW}0${NC}) Назад"

    echo
    printf "${MAGENTA}➜ ${NC}"
    read -r CHOICE

    case "$CHOICE" in
        1)
            if [ -n "$INSTALLED" ] && [ "$INSTALLED" = "$GITHUB" ]; then
                echo -e "\n${GREEN}✓ Уже установлена актуальная версия${NC}"
                sleep 2
                return
            fi

            FILE="luci-app-splify2-${GITHUB}-1_noarch.apk"
            URL="https://github.com/xyzmean/splify2/releases/download/${TAG}/${FILE}"

            echo -e "\n${CYAN}Скачиваем:${NC} $FILE"

            if ! curl -fLs "$URL" -o "$TMP/$FILE"; then
                echo -e "${RED}✗ Ошибка скачивания${NC}"
                rm -f "$TMP/$FILE"
                sleep 2
                return
            fi

            echo -e "${CYAN}Устанавливаем...${NC}"

            if apk add --allow-untrusted "$TMP/$FILE"; then
                echo -e "${GREEN}✓ Splify2 установлен/обновлён${NC}"
            else
                echo -e "${RED}✗ Ошибка установки${NC}"
            fi

            rm -f "$TMP/$FILE"
            sleep 2
            ;;

        2)
            echo -e "\n${CYAN}Удаляем Splify2...${NC}"

            apk del luci-app-splify2 >/dev/null 2>&1

            cleanup_files

            echo -e "${GREEN}✓ Splify2 удалён${NC}"
            sleep 2
            ;;

        0)
            return
            ;;

        *)
            echo -e "${RED}✗ Неверный выбор${NC}"
            sleep 1
            ;;
    esac
}

# ============================================================
# Главное меню
# ============================================================

while true; do
    STEER_TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"
    STEER_GITHUB="${STEER_TAG#v}"

    if apk info -e steer-extended >/dev/null 2>&1; then
        STEER_INSTALLED="$(get_version steer-extended)"
    elif apk info -e steer >/dev/null 2>&1; then
        STEER_INSTALLED="$(get_version steer)"
    else
        STEER_INSTALLED=""
    fi

    SPLIFY_TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"
    SPLIFY_GITHUB="${SPLIFY_TAG#v}"

    if apk info -e luci-app-splify2 >/dev/null 2>&1; then
        SPLIFY_INSTALLED="$(get_version luci-app-splify2)"
    else
        SPLIFY_INSTALLED=""
    fi

    clear

    echo -e "${MAGENTA}╔══════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}       ${CYAN}Steer / Splify2 Manager${NC}           ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════╝${NC}"

    echo -e "\n${YELLOW}OpenWrt:${NC}      ${GREEN}$DISTRIB_RELEASE${NC}"
    echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$ARCH${NC}"

    echo -e "\n${BLUE}━━━ Steer ━━━${NC}"
    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${STEER_INSTALLED:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}${STEER_GITHUB:-ошибка}${NC}"

    if [ -n "$STEER_INSTALLED" ] && [ "$STEER_INSTALLED" = "$STEER_GITHUB" ]; then
        echo -e "${GREEN}Статус:        актуальна${NC}"
    elif [ -n "$STEER_INSTALLED" ]; then
        echo -e "${YELLOW}Статус:        доступно обновление${NC}"
    else
        echo -e "${RED}Статус:        не установлена${NC}"
    fi

    echo -e "\n${BLUE}━━━ Splify2 ━━━${NC}"
    echo -e "${YELLOW}Установлена:${NC} ${GREEN}${SPLIFY_INSTALLED:-нет}${NC}"
    echo -e "${YELLOW}GitHub:${NC}      ${GREEN}${SPLIFY_GITHUB:-ошибка}${NC}"

    if [ -n "$SPLIFY_INSTALLED" ] && [ "$SPLIFY_INSTALLED" = "$SPLIFY_GITHUB" ]; then
        echo -e "${GREEN}Статус:        актуальна${NC}"
    elif [ -n "$SPLIFY_INSTALLED" ]; then
        echo -e "${YELLOW}Статус:        доступно обновление${NC}"
    else
        echo -e "${RED}Статус:        не установлена${NC}"
    fi

    echo -e "\n${CYAN}1${NC}) Steer"
    echo -e "${CYAN}2${NC}) Splify2"
    echo -e "${YELLOW}0${NC}) Выход"

    echo
    printf "${MAGENTA}➜ ${NC}"
    read -r CHOICE

    case "$CHOICE" in
        1) STEER ;;
        2) SPLIFY ;;
        0) break ;;
        *) echo -e "${RED}✗ Неверный выбор${NC}"; sleep 1 ;;
    esac
done

rm -rf "$TMP"
