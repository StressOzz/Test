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

# ============================================================
# Получение последнего tag GitHub
# ============================================================

get_latest_tag() {
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" 2>/dev/null |
        sed 's#.*/tag/##'
}

# ============================================================
# Получение установленной версии
# ============================================================

get_installed_version() {
    PKG="$1"

    apk list --installed "$PKG" 2>/dev/null |
        sed -n "s/^${PKG}-\([^ ]*\).*/\1/p" |
        head -n1
}

# ============================================================
# Нормализация версии
#
# Например:
# 0.7.5-r1 -> 0.7.5
# ============================================================

normalize_version() {
    echo "$1" | sed 's/-r[0-9][0-9]*$//'
}

# ============================================================
# Сравнение версий
# 0 = одинаковые
# 1 = новая версия
# ============================================================

version_is_newer() {
    OLD="$(normalize_version "$1")"
    NEW="$(normalize_version "$2")"

    [ "$OLD" = "$NEW" ] && return 1

    if [ "$OLD" = "$NEW" ]; then
        return 1
    fi

    if [ "$(printf '%s\n%s\n' "$OLD" "$NEW" | sort -V | tail -n1)" = "$NEW" ] &&
       [ "$OLD" != "$NEW" ]; then
        return 0
    fi

    return 1
}

# ============================================================
# Очистка хвостов
# ============================================================

cleanup_files() {
    echo -e "\n${CYAN}Очистка файлов...${NC}"

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
# Steer — информация
# ============================================================

STEER_INSTALLED=""
STEER_LATEST=""

get_steer_info() {
    STEER_INSTALLED=""

    if apk info -e steer-extended >/dev/null 2>&1; then
        STEER_INSTALLED="$(get_installed_version steer-extended)"
    elif apk info -e steer >/dev/null 2>&1; then
        STEER_INSTALLED="$(get_installed_version steer)"
    fi

    STEER_TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"

    if [ -n "$STEER_TAG" ]; then
        STEER_LATEST="${STEER_TAG#v}"
    else
        STEER_LATEST="-"
    fi
}

# ============================================================
# Splify2 — информация
# ============================================================

SPLIFY_INSTALLED=""
SPLIFY_LATEST=""

get_splify_info() {
    SPLIFY_INSTALLED=""

    if apk info -e luci-app-splify2 >/dev/null 2>&1; then
        SPLIFY_INSTALLED="$(get_installed_version luci-app-splify2)"
    fi

    SPLIFY_TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"

    if [ -n "$SPLIFY_TAG" ]; then
        SPLIFY_LATEST="${SPLIFY_TAG#v}"
    else
        SPLIFY_LATEST="-"
    fi
}

# ============================================================
# Статус Steer
# ============================================================

STEER_STATUS() {
    if [ -z "$STEER_INSTALLED" ]; then
        echo -e "${RED}не установлен${NC}"
        return
    fi

    if [ "$STEER_LATEST" = "-" ]; then
        echo -e "${GREEN}установлен${NC}"
        return
    fi

    INST="$(normalize_version "$STEER_INSTALLED")"
    LAST="$(normalize_version "$STEER_LATEST")"

    if [ "$INST" = "$LAST" ]; then
        echo -e "${GREEN}актуален${NC}"
    elif version_is_newer "$INST" "$LAST"; then
        echo -e "${YELLOW}доступно обновление${NC}"
    else
        echo -e "${GREEN}установлен${NC}"
    fi
}

# ============================================================
# Статус Splify2
# ============================================================

SPLIFY_STATUS() {
    if [ -z "$SPLIFY_INSTALLED" ]; then
        echo -e "${RED}не установлен${NC}"
        return
    fi

    if [ "$SPLIFY_LATEST" = "-" ]; then
        echo -e "${GREEN}установлен${NC}"
        return
    fi

    INST="$(normalize_version "$SPLIFY_INSTALLED")"
    LAST="$(normalize_version "$SPLIFY_LATEST")"

    if [ "$INST" = "$LAST" ]; then
        echo -e "${GREEN}актуален${NC}"
    elif version_is_newer "$INST" "$LAST"; then
        echo -e "${YELLOW}доступно обновление${NC}"
    else
        echo -e "${GREEN}установлен${NC}"
    fi
}

# ============================================================
# Установка / обновление Steer
# ============================================================

install_steer() {
    get_steer_info

    echo -e "\n${MAGENTA}━━━ Steer ━━━${NC}"

    if [ -n "$STEER_INSTALLED" ]; then
        echo -e "${YELLOW}Установлена:${NC}  ${GREEN}$STEER_INSTALLED${NC}"
    else
        echo -e "${YELLOW}Установлена:${NC}  ${RED}нет${NC}"
    fi

    echo -e "${YELLOW}GitHub:${NC}        ${GREEN}$STEER_LATEST${NC}"

    if [ -n "$STEER_INSTALLED" ] &&
       [ "$(normalize_version "$STEER_INSTALLED")" = "$(normalize_version "$STEER_LATEST")" ]; then

        echo -e "\n${GREEN}✓ Установлена актуальная версия${NC}"
        return 0
    fi

    if [ -n "$STEER_INSTALLED" ]; then
        echo -e "\n${CYAN}Обновляем Steer...${NC}"
    else
        echo -e "\n${CYAN}Устанавливаем Steer...${NC}"
    fi

    TAG="v${STEER_LATEST}"
    FILE="steer-extended-${STEER_LATEST}-1_${STEER_ARCH}.apk"
    URL="https://github.com/xyzmean/steer/releases/download/${TAG}/${FILE}"

    echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$STEER_ARCH${NC}"
    echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"

    echo -e "${CYAN}Скачиваем...${NC}"

    if ! curl -fLs "$URL" -o "$TMP/$FILE"; then
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

# ============================================================
# Установка / обновление Splify2
# ============================================================

install_splify() {
    get_splify_info

    echo -e "\n${MAGENTA}━━━ Splify2 ━━━${NC}"

    if [ -n "$SPLIFY_INSTALLED" ]; then
        echo -e "${YELLOW}Установлена:${NC}  ${GREEN}$SPLIFY_INSTALLED${NC}"
    else
        echo -e "${YELLOW}Установлена:${NC}  ${RED}нет${NC}"
    fi

    echo -e "${YELLOW}GitHub:${NC}        ${GREEN}$SPLIFY_LATEST${NC}"

    if [ -n "$SPLIFY_INSTALLED" ] &&
       [ "$(normalize_version "$SPLIFY_INSTALLED")" = "$(normalize_version "$SPLIFY_LATEST")" ]; then

        echo -e "\n${GREEN}✓ Установлена актуальная версия${NC}"
        return 0
    fi

    if [ -n "$SPLIFY_INSTALLED" ]; then
        echo -e "\n${CYAN}Обновляем Splify2...${NC}"
    else
        echo -e "\n${CYAN}Устанавливаем Splify2...${NC}"
    fi

    TAG="v${SPLIFY_LATEST}"
    FILE="luci-app-splify2-${SPLIFY_LATEST}-1_noarch.apk"
    URL="https://github.com/xyzmean/splify2/releases/download/${TAG}/${FILE}"

    echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}noarch${NC}"
    echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"

    echo -e "${CYAN}Скачиваем...${NC}"

    if ! curl -fLs "$URL" -o "$TMP/$FILE"; then
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

# ============================================================
# Удаление Steer
# ============================================================

delete_steer() {
    echo -e "\n${MAGENTA}━━━ Удаление Steer ━━━${NC}"

    if ! apk info -e steer-extended >/dev/null 2>&1 &&
       ! apk info -e steer >/dev/null 2>&1; then
        echo -e "${YELLOW}Steer не установлен${NC}"
        return 0
    fi

    echo -e "${CYAN}Удаляем пакет...${NC}"

    apk del steer-extended >/dev/null 2>&1 ||
    apk del steer >/dev/null 2>&1

    cleanup_files

    echo -e "${GREEN}✓ Steer удалён${NC}"
}

# ============================================================
# Удаление Splify2
# ============================================================

delete_splify() {
    echo -e "\n${MAGENTA}━━━ Удаление Splify2 ━━━${NC}"

    if ! apk info -e luci-app-splify2 >/dev/null 2>&1; then
        echo -e "${YELLOW}Splify2 не установлен${NC}"
        return 0
    fi

    echo -e "${CYAN}Удаляем пакет...${NC}"

    if ! apk del luci-app-splify2 >/dev/null 2>&1; then
        echo -e "${RED}✗ Ошибка удаления Splify2${NC}"
        return 1
    fi

    cleanup_files

    echo -e "${GREEN}✓ Splify2 удалён${NC}"
}

# ============================================================
# Главное меню
# ============================================================

MENU() {
    while true; do
        get_steer_info
        get_splify_info

        clear

        echo -e "${MAGENTA}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${NC}        ${CYAN}Steer / Splify2 Manager${NC}         ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════╝${NC}"

        echo -e "\n${YELLOW}OpenWrt:${NC}      ${GREEN}$DISTRIB_RELEASE${NC}"
        echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$ARCH${NC}"

        echo -e "\n${BLUE}┌──────────────────────────────────────────────┐${NC}"
        echo -e "${BLUE}│${NC} ${MAGENTA}Steer${NC}"
        echo -e "${BLUE}│${NC}   Установлена: ${GREEN}${STEER_INSTALLED:-нет}${NC}"
        echo -e "${BLUE}│${NC}   GitHub:      ${GREEN}${STEER_LATEST}${NC}"
        echo -e "${BLUE}│${NC}   Статус:      $(STEER_STATUS)"
        echo -e "${BLUE}├──────────────────────────────────────────────┤${NC}"
        echo -e "${BLUE}│${NC} ${MAGENTA}Splify2${NC}"
        echo -e "${BLUE}│${NC}   Установлена: ${GREEN}${SPLIFY_INSTALLED:-нет}${NC}"
        echo -e "${BLUE}│${NC}   GitHub:      ${GREEN}${SPLIFY_LATEST}${NC}"
        echo -e "${BLUE}│${NC}   Статус:      $(SPLIFY_STATUS)"
        echo -e "${BLUE}└──────────────────────────────────────────────┘${NC}"

        echo -e "\n${CYAN}1${NC}) Установить / обновить Steer"
        echo -e "${CYAN}2${NC}) Установить / обновить Splify2"
        echo -e "${CYAN}3${NC}) Установить / обновить всё"
        echo -e "${RED}4${NC}) Удалить Steer"
        echo -e "${RED}5${NC}) Удалить Splify2"
        echo -e "${RED}6${NC}) Удалить всё"
        echo -e "${YELLOW}0${NC}) Выход"

        echo
        printf "${MAGENTA}➜ ${NC}"
        read -r CHOICE

        case "$CHOICE" in
            1)
                install_steer
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            2)
                install_splify
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            3)
                install_steer
                install_splify
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            4)
                delete_steer
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            5)
                delete_splify
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            6)
                delete_steer
                delete_splify
                printf "\n${CYAN}Нажмите Enter...${NC}"
                read -r
                ;;

            0)
                break
                ;;

            *)
                echo -e "\n${RED}✗ Неверный выбор${NC}"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# Запуск
# ============================================================

trap 'rm -rf "$TMP"' EXIT

MENU
