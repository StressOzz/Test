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
# Вспомогательные функции
# ==============================

get_latest_tag() {
    # $1 - url вида https://github.com/<owner>/<repo>/releases/latest
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" | sed 's#.*/tag/##'
}

get_installed_version() {
    # $1 - имя пакета, возвращает версию (с release-суффиксом), либо пусто
    apk list -I 2>/dev/null | grep -E "^$1-[0-9]" | head -n1 | sed -E "s/^$1-([^ ]+).*/\1/"
}

is_installed() {
    apk info -e "$1" >/dev/null 2>&1
}

version_matches() {
    # $1 - установленная версия (может быть с суффиксом -N), $2 - версия из тега
    case "$1" in
        "$2"|"$2"-*) return 0 ;;
        *) return 1 ;;
    esac
}

print_status() {
    # $1 - название, $2 - установленная версия, $3 - последняя версия на GitHub
    NAME="$1"; INSTALLED="$2"; LATEST="$3"

    if [ -z "$LATEST" ]; then
        echo -e "  ${YELLOW}${NAME}${NC} не удалось проверить последнюю версию (нет сети/GitHub недоступен)"
        return
    fi

    if [ -z "$INSTALLED" ]; then
        echo -e "  ${YELLOW}${NAME}${NC} ${RED}не установлен${NC}  (доступно: ${GREEN}${LATEST}${NC})"
    elif version_matches "$INSTALLED" "$LATEST"; then
        echo -e "  ${YELLOW}${NAME}${NC} ${GREEN}${INSTALLED}${NC} (последняя версия)"
    else
        echo -e "  ${YELLOW}${NAME}${NC} ${CYAN}${INSTALLED}${NC} → доступно обновление ${GREEN}${LATEST}${NC}"
    fi
}

pause() {
    printf "\n${CYAN}Нажмите Enter для продолжения...${NC}"
    read -r _
}

# ==============================
# Steer
# ==============================

steer_install_or_update() {
    echo -e "\n${MAGENTA}━━━ Steer ━━━${NC}"
    echo -e "${CYAN}Получаем последнюю версию...${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"
    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Steer${NC}"
        return 1
    fi
    VER="${TAG#v}"

    CUR="$(get_installed_version steer)"
    [ -z "$CUR" ] && CUR="$(get_installed_version steer-extended)"

    if [ -n "$CUR" ] && version_matches "$CUR" "$VER"; then
        echo -e "${GREEN}✓ Уже установлена последняя версия ($CUR)${NC}"
        return 0
    fi

    if [ -z "$CUR" ]; then
        echo -e "${CYAN}Устанавливаем Steer${NC}"
    else
        echo -e "${CYAN}Обновляем Steer: ${YELLOW}$CUR${NC} → ${GREEN}$VER${NC}"
    fi

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
    echo -e "${GREEN}✓ Steer успешно установлен/обновлён ($VER)${NC}"
}

steer_cleanup_files() {
    # Дополнительная зачистка остаточных файлов Steer.
    # Ограничено конкретными директориями (как в оригинале), но не трогает
    # произвольные файлы за их пределами.
    for DIR in /etc /usr /www /root /opt /tmp; do
        [ -d "$DIR" ] || continue
        find "$DIR" -depth \( -iname 'steer' -o -iname 'steer-*' \) -print 2>/dev/null |
        while read -r F; do
            echo -e "  ${RED}Удаляем:${NC} $F"
            rm -rf -- "$F"
        done
    done
}

steer_remove() {
    echo -e "\n${MAGENTA}━━━ Steer: удаление ━━━${NC}"

    if ! is_installed steer && ! is_installed steer-extended; then
        echo -e "${YELLOW}Steer не установлен${NC}"
        return 0
    fi

    echo -e "${CYAN}Удаляем...${NC}"
    if apk del steer-extended >/dev/null 2>&1 || apk del steer >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Steer успешно удалён${NC}"
        printf "${CYAN}Также подчистить остаточные файлы (find/rm по /etc /usr /www /root /opt /tmp)? [y/N]:${NC} "
        read -r ANSWER
        case "$ANSWER" in
            y|Y) steer_cleanup_files ;;
        esac
    else
        echo -e "${RED}✗ Ошибка удаления Steer${NC}"
        return 1
    fi
}

# ==============================
# Splify2
# ==============================

splify_install_or_update() {
    echo -e "\n${MAGENTA}━━━ Splify2 ━━━${NC}"
    echo -e "${CYAN}Получаем последнюю версию...${NC}"

    TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"
    if [ -z "$TAG" ]; then
        echo -e "${RED}✗ Не удалось определить версию Splify2${NC}"
        return 1
    fi
    VER="${TAG#v}"

    CUR="$(get_installed_version luci-app-splify2)"

    if [ -n "$CUR" ] && version_matches "$CUR" "$VER"; then
        echo -e "${GREEN}✓ Уже установлена последняя версия ($CUR)${NC}"
        return 0
    fi

    if [ -z "$CUR" ]; then
        echo -e "${CYAN}Устанавливаем Splify2${NC}"
    else
        echo -e "${CYAN}Обновляем Splify2: ${YELLOW}$CUR${NC} → ${GREEN}$VER${NC}"
    fi

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
    echo -e "${GREEN}✓ Splify2 успешно установлен/обновлён ($VER)${NC}"
}

splify_cleanup_files() {
    for DIR in /etc /usr /www /root /opt /tmp; do
        [ -d "$DIR" ] || continue
        find "$DIR" -depth \( -iname 'splify2' -o -iname 'splify2-*' \) -print 2>/dev/null |
        while read -r F; do
            echo -e "  ${RED}Удаляем:${NC} $F"
            rm -rf -- "$F"
        done
    done
}

splify_remove() {
    echo -e "\n${MAGENTA}━━━ Splify2: удаление ━━━${NC}"

    if ! is_installed luci-app-splify2; then
        echo -e "${YELLOW}Splify2 не установлен${NC}"
        return 0
    fi

    echo -e "${CYAN}Удаляем...${NC}"
    if apk del luci-app-splify2 >/dev/null 2>&1; then
        echo -e "${GREEN}✓ Splify2 успешно удалён${NC}"
        printf "${CYAN}Также подчистить остаточные файлы (find/rm по /etc /usr /www /root /opt /tmp)? [y/N]:${NC} "
        read -r ANSWER
        case "$ANSWER" in
            y|Y) splify_cleanup_files ;;
        esac
    else
        echo -e "${RED}✗ Ошибка удаления Splify2${NC}"
        return 1
    fi
}

# ==============================
# Меню
# ==============================

show_menu() {
    clear
    echo -e "${MAGENTA}╔══════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}     ${CYAN}Steer / Splify2 — менеджер${NC}       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════╝${NC}"
    echo -e "\n${YELLOW}Архитектура OpenWrt:${NC} ${GREEN}$ARCH${NC}\n"

    echo -e "${CYAN}Проверка версий...${NC}"

    STEER_CUR="$(get_installed_version steer)"
    [ -z "$STEER_CUR" ] && STEER_CUR="$(get_installed_version steer-extended)"
    STEER_TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"
    STEER_LATEST="${STEER_TAG#v}"

    SPLIFY_CUR="$(get_installed_version luci-app-splify2)"
    SPLIFY_TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"
    SPLIFY_LATEST="${SPLIFY_TAG#v}"

    echo ""
    print_status "Steer:  " "$STEER_CUR" "$STEER_LATEST"
    print_status "Splify2:" "$SPLIFY_CUR" "$SPLIFY_LATEST"
    echo ""
    echo -e "${BLUE}────────────────────────────────────────${NC}"

    if [ -z "$STEER_CUR" ]; then
        echo -e " ${GREEN}1)${NC} Установить Steer"
    elif [ -n "$STEER_LATEST" ] && ! version_matches "$STEER_CUR" "$STEER_LATEST"; then
        echo -e " ${GREEN}1)${NC} Обновить Steer"
    else
        echo -e " ${GREEN}1)${NC} Переустановить Steer"
    fi
    echo -e " ${RED}2)${NC} Удалить Steer"

    if [ -z "$SPLIFY_CUR" ]; then
        echo -e " ${GREEN}3)${NC} Установить Splify2"
    elif [ -n "$SPLIFY_LATEST" ] && ! version_matches "$SPLIFY_CUR" "$SPLIFY_LATEST"; then
        echo -e " ${GREEN}3)${NC} Обновить Splify2"
    else
        echo -e " ${GREEN}3)${NC} Переустановить Splify2"
    fi
    echo -e " ${RED}4)${NC} Удалить Splify2"

    echo -e " ${CYAN}5)${NC} Установить/обновить всё"
    echo -e " ${CYAN}6)${NC} Удалить всё"
    echo -e " ${YELLOW}0)${NC} Выход"
    echo -e "${BLUE}────────────────────────────────────────${NC}"
}

trap 'rm -rf "$TMP"' EXIT

while true; do
    show_menu
    printf "\n${YELLOW}Выберите действие:${NC} "
    read -r CHOICE

    case "$CHOICE" in
        1) steer_install_or_update; pause ;;
        2) steer_remove; pause ;;
        3) splify_install_or_update; pause ;;
        4) splify_remove; pause ;;
        5) steer_install_or_update; splify_install_or_update; pause ;;
        6) steer_remove; splify_remove; pause ;;
        0)
            echo -e "${GREEN}Выход.${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}Неверный выбор${NC}"
            pause
            ;;
    esac
done
