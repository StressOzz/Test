```sh
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
# Получить последнюю версию GitHub
# ============================================================

get_latest() {
    curl -Ls \
        --connect-timeout 5 \
        --max-time 10 \
        -o /dev/null \
        -w '%{url_effective}' "$1" 2>/dev/null |
        sed 's#.*/tag/##' |
        sed 's/^v//'
}

# ============================================================
# Получить установленную версию
# ============================================================

get_version() {
    apk list -I 2>/dev/null |
        grep -E "^$1-[0-9]" |
        head -n1 |
        sed -E "s/^$1-([^ ]+).*/\1/"
}

# ============================================================
# Сравнение версии
#
# Учитываем:
# 0.7.5
# 0.7.5-r1
# 0.7.5-r2
# ============================================================

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

# ============================================================
# Очистка файлов
# ============================================================

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

# ============================================================
# Пауза
# ============================================================

pause() {
    echo
    printf "${CYAN}Нажмите Enter для продолжения...${NC}"
    read -r _
}

# ============================================================
# Steer
# ============================================================

STEER() {
    while true; do
        clear

        TAG="$(get_latest "https://github.com/xyzmean/steer/releases/latest")"
        LATEST="$TAG"

        INSTALLED="$(get_version steer)"
        [ -z "$INSTALLED" ] && INSTALLED="$(get_version steer-extended)"

        echo -e "${MAGENTA}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${NC}                  ${CYAN}Steer${NC}                  ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}Установлена:${NC} ${GREEN}${INSTALLED:-нет}${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}GitHub:${NC}      ${GREEN}${LATEST:-ошибка}${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}Архитектура:${NC} ${GREEN}${STEER_ARCH}${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════╝${NC}"

        echo

        if [ -z "$LATEST" ]; then
            echo -e "${RED}✗ Не удалось получить версию GitHub${NC}"
            pause
            return
        fi

        if [ -z "$INSTALLED" ]; then
            ACTION="Установить"
            echo -e "${CYAN}Статус:${NC} ${RED}не установлен${NC}"
        elif version_match "$INSTALLED" "$LATEST"; then
            ACTION="Переустановить"
            echo -e "${CYAN}Статус:${NC} ${GREEN}актуальная версия${NC}"
        else
            ACTION="Обновить"
            echo -e "${CYAN}Статус:${NC} ${YELLOW}доступно обновление${NC}"
            echo -e "${CYAN}        ${YELLOW}$INSTALLED${NC} → ${GREEN}$LATEST${NC}"
        fi

        echo
        echo -e "${GREEN}1)${NC} $ACTION Steer"
        echo -e "${RED}2)${NC} Удалить Steer"
        echo -e "${YELLOW}0)${NC} Назад"

        echo
        printf "${MAGENTA}➜ ${NC}"
        read -r CHOICE

        case "$CHOICE" in
            1)
                if [ "$ACTION" = "Переустановить" ]; then
                    echo -e "\n${YELLOW}Steer уже имеет последнюю версию.${NC}"
                    echo -e "${CYAN}Переустанавливаем...${NC}"
                elif [ -z "$INSTALLED" ]; then
                    echo -e "\n${CYAN}Устанавливаем Steer...${NC}"
                else
                    echo -e "\n${CYAN}Обновляем Steer:${NC} ${YELLOW}$INSTALLED${NC} → ${GREEN}$LATEST${NC}"
                fi

                FILE="steer-extended-${LATEST}-1_${STEER_ARCH}.apk"
                URL="https://github.com/xyzmean/steer/releases/download/v${LATEST}/${FILE}"

                echo -e "${YELLOW}Версия:${NC}       ${GREEN}$LATEST${NC}"
                echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$STEER_ARCH${NC}"
                echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"
                echo -e "${CYAN}Скачиваем...${NC}"

                if ! curl -fL "$URL" -o "$TMP/$FILE"; then
                    echo -e "${RED}✗ Ошибка скачивания Steer${NC}"
                    rm -f "$TMP/$FILE"
                    pause
                    continue
                fi

                echo -e "${CYAN}Устанавливаем...${NC}"

                if apk add --allow-untrusted "$TMP/$FILE"; then
                    echo -e "${GREEN}✓ Steer успешно установлен${NC}"
                else
                    echo -e "${RED}✗ Ошибка установки Steer${NC}"
                fi

                rm -f "$TMP/$FILE"
                pause
                ;;

            2)
                echo -e "\n${CYAN}Удаляем Steer...${NC}"

                if apk info -e steer-extended >/dev/null 2>&1 ||
                   apk info -e steer >/dev/null 2>&1; then

                    if apk del steer-extended >/dev/null 2>&1 ||
                       apk del steer >/dev/null 2>&1; then

                        echo -e "${GREEN}✓ Steer успешно удалён${NC}"
                        cleanup

                    else
                        echo -e "${RED}✗ Ошибка удаления Steer${NC}"
                    fi
                else
                    echo -e "${YELLOW}Steer не установлен${NC}"
                fi

                pause
                ;;

            0)
                return
                ;;

            *)
                echo -e "${RED}✗ Неверный выбор${NC}"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# Splify2
# ============================================================

SPLIFY() {
    while true; do
        clear

        TAG="$(get_latest "https://github.com/xyzmean/splify2/releases/latest")"
        LATEST="$TAG"

        INSTALLED="$(get_version luci-app-splify2)"

        echo -e "${MAGENTA}╔══════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${NC}                 ${CYAN}Splify2${NC}                ${MAGENTA}║${NC}"
        echo -e "${MAGENTA}╠══════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}Установлена:${NC} ${GREEN}${INSTALLED:-нет}${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}GitHub:${NC}      ${GREEN}${LATEST:-ошибка}${NC}"
        echo -e "${MAGENTA}║${NC} ${YELLOW}Архитектура:${NC} ${GREEN}noarch${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════╝${NC}"

        echo

        if [ -z "$LATEST" ]; then
            echo -e "${RED}✗ Не удалось получить версию GitHub${NC}"
            pause
            return
        fi

        if [ -z "$INSTALLED" ]; then
            ACTION="Установить"
            echo -e "${CYAN}Статус:${NC} ${RED}не установлен${NC}"
        elif version_match "$INSTALLED" "$LATEST"; then
            ACTION="Переустановить"
            echo -e "${CYAN}Статус:${NC} ${GREEN}актуальная версия${NC}"
        else
            ACTION="Обновить"
            echo -e "${CYAN}Статус:${NC} ${YELLOW}доступно обновление${NC}"
            echo -e "${CYAN}        ${YELLOW}$INSTALLED${NC} → ${GREEN}$LATEST${NC}"
        fi

        echo
        echo -e "${GREEN}1)${NC} $ACTION Splify2"
        echo -e "${RED}2)${NC} Удалить Splify2"
        echo -e "${YELLOW}0)${NC} Назад"

        echo
        printf "${MAGENTA}➜ ${NC}"
        read -r CHOICE

        case "$CHOICE" in
            1)
                if [ "$ACTION" = "Переустановить" ]; then
                    echo -e "\n${YELLOW}Splify2 уже имеет последнюю версию.${NC}"
                    echo -e "${CYAN}Переустанавливаем...${NC}"
                elif [ -z "$INSTALLED" ]; then
                    echo -e "\n${CYAN}Устанавливаем Splify2...${NC}"
                else
                    echo -e "\n${CYAN}Обновляем Splify2:${NC} ${YELLOW}$INSTALLED${NC} → ${GREEN}$LATEST${NC}"
                fi

                FILE="luci-app-splify2-${LATEST}-1_noarch.apk"
                URL="https://github.com/xyzmean/splify2/releases/download/v${LATEST}/${FILE}"

                echo -e "${YELLOW}Версия:${NC}       ${GREEN}$LATEST${NC}"
                echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}noarch${NC}"
                echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"
                echo -e "${CYAN}Скачиваем...${NC}"

                if ! curl -fL "$URL" -o "$TMP/$FILE"; then
                    echo -e "${RED}✗ Ошибка скачивания Splify2${NC}"
                    rm -f "$TMP/$FILE"
                    pause
                    continue
                fi

                echo -e "${CYAN}Устанавливаем...${NC}"

                if apk add --allow-untrusted "$TMP/$FILE"; then
                    echo -e "${GREEN}✓ Splify2 успешно установлен${NC}"
                else
                    echo -e "${RED}✗ Ошибка установки Splify2${NC}"
                fi

                rm -f "$TMP/$FILE"
                pause
                ;;

            2)
                echo -e "\n${CYAN}Удаляем Splify2...${NC}"

                if apk info -e luci-app-splify2 >/dev/null 2>&1; then

                    if apk del luci-app-splify2 >/dev/null 2>&1; then
                        echo -e "${GREEN}✓ Splify2 успешно удалён${NC}"
                        cleanup
                    else
                        echo -e "${RED}✗ Ошибка удаления Splify2${NC}"
                    fi

                else
                    echo -e "${YELLOW}Splify2 не установлен${NC}"
                fi

                pause
                ;;

            0)
                return
                ;;

            *)
                echo -e "${RED}✗ Неверный выбор${NC}"
                sleep 1
                ;;
        esac
    done
}

# ============================================================
# Главное меню
# ============================================================

trap 'rm -rf "$TMP"' EXIT

while true; do
    clear

    STEER_LATEST="$(get_latest "https://github.com/xyzmean/steer/releases/latest")"
    SPLIFY_LATEST="$(get_latest "https://github.com/xyzmean/splify2/releases/latest")"

    STEER_INSTALLED="$(get_version steer)"
    [ -z "$STEER_INSTALLED" ] && STEER_INSTALLED="$(get_version steer-extended)"

    SPLIFY_INSTALLED="$(get_version luci-app-splify2)"

    echo -e "${MAGENTA}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${NC}          ${CYAN}Steer / Splify2 Manager${NC}             ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${NC} ${YELLOW}OpenWrt:${NC}      ${GREEN}$DISTRIB_RELEASE${NC}"
    echo -e "${MAGENTA}║${NC} ${YELLOW}Архитектура:${NC}  ${GREEN}$ARCH${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════╝${NC}"

    echo
    echo -e "${BLUE}┌──────────────────────────────────────────────────┐${NC}"
    echo -e "${BLUE}│${NC} ${MAGENTA}Steer${NC}"
    echo -e "${BLUE}│${NC}   Установлена: ${GREEN}${STEER_INSTALLED:-нет}${NC}"
    echo -e "${BLUE}│${NC}   GitHub:      ${GREEN}${STEER_LATEST:-ошибка}${NC}"

    if [ -z "$STEER_INSTALLED" ]; then
        echo -e "${BLUE}│${NC}   Статус:      ${RED}не установлен${NC}"
    elif version_match "$STEER_INSTALLED" "$STEER_LATEST"; then
        echo -e "${BLUE}│${NC}   Статус:      ${GREEN}актуален${NC}"
    else
        echo -e "${BLUE}│${NC}   Статус:      ${YELLOW}доступно обновление${NC}"
    fi

    echo -e "${BLUE}├──────────────────────────────────────────────────┤${NC}"
    echo -e "${BLUE}│${NC} ${MAGENTA}Splify2${NC}"
    echo -e "${BLUE}│${NC}   Установлена: ${GREEN}${SPLIFY_INSTALLED:-нет}${NC}"
    echo -e "${BLUE}│${NC}   GitHub:      ${GREEN}${SPLIFY_LATEST:-ошибка}${NC}"

    if [ -z "$SPLIFY_INSTALLED" ]; then
        echo -e "${BLUE}│${NC}   Статус:      ${RED}не установлен${NC}"
    elif version_match "$SPLIFY_INSTALLED" "$SPLIFY_LATEST"; then
        echo -e "${BLUE}│${NC}   Статус:      ${GREEN}актуален${NC}"
    else
        echo -e "${BLUE}│${NC}   Статус:      ${YELLOW}доступно обновление${NC}"
    fi

    echo -e "${BLUE}└──────────────────────────────────────────────────┘${NC}"

    echo
    echo -e "${GREEN}1)${NC} Steer"
    echo -e "${GREEN}2)${NC} Splify2"
    echo -e "${YELLOW}0)${NC} Выход"

    echo
    printf "${MAGENTA}➜ ${NC}"
    read -r CHOICE

    case "$CHOICE" in
        1)
            STEER
            ;;
        2)
            SPLIFY
            ;;
        0)
            clear
            echo -e "${GREEN}✓ Выход${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}✗ Неверный выбор${NC}"
            sleep 1
            ;;
    esac
done
```
