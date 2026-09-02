#!/bin/sh
# =========================================
# OpenWRT Mirror Manager
# Проверка / автоподбор / ручной выбор зеркала репозитория
# Поддержка: OpenWRT 24.x (opkg) и 25.x (apk)
# =========================================

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"
YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; DGRAY="\033[38;5;244m"; NC="\033[0m"

PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }

# =========================================
# Определение пакетного менеджера
# =========================================
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    CONFZ="/etc/opkg/distfeeds.conf"
    UPDATE="opkg update"
elif command -v apk >/dev/null 2>&1; then
    PKG="apk"
    CONFZ="/etc/apk/repositories.d/distfeeds.list"
    UPDATE="apk update"
else
    echo -e "${RED}Не найден ни opkg, ни apk. Скрипт предназначен для OpenWRT.${NC}"
    exit 1
fi

if [ ! -f "$CONFZ" ]; then
    echo -e "${RED}Файл конфигурации репозитория не найден:${NC} $CONFZ"
    exit 1
fi

# =========================================
# Бэкап оригинального конфига (один раз, при первом запуске)
# Все дальнейшие замены зеркала всегда идут ОТ ЭТОГО бэкапа,
# а не от уже изменённого файла — иначе при переборе нескольких
# зеркал подряд правки накапливаются друг на друге и портят файл.
# =========================================
CONFZ_BACKUP="${CONFZ}.zapret-orig"

backup_confz() {
    if [ ! -f "$CONFZ_BACKUP" ]; then
        cp "$CONFZ" "$CONFZ_BACKUP"
    fi
}

apply_mirror() {
    HOST="$1"
    backup_confz
    cp "$CONFZ_BACKUP" "$CONFZ"
    sed -i "s|https://.*/releases/|https://$HOST/releases/|g" "$CONFZ"
}

restore_confz() {
    [ -f "$CONFZ_BACKUP" ] && cp "$CONFZ_BACKUP" "$CONFZ"
}

# =========================================
# Список зеркал: host|Название
# Пункты меню 1-9 генерируются из этого списка автоматически.
# =========================================
MIRRORS="mirror-03.infra.openwrt.org|infra.openwrt.org
mirror.sjtu.edu.cn/openwrt|China
mirror.berlin.freifunk.net/downloads.openwrt.org|Germany
mirror.tiguinet.net/openwrt|Belgium
mirror.ps.kz/openwrt|Kazakhstan
ftp.snt.utwente.nl/pub/software/openwrt|Netherlands
ftp.halifax.rwth-aachen.de/openwrt|Germany (RWTH Aachen)
mirror.accum.se/mirror/openwrt.org|Sweden
downloads.openwrt.org|default / OpenWrt"

DEFAULT_MIRROR="downloads.openwrt.org"
MIRROR_TIMEOUT=5

reset_to_default() {
    apply_mirror "$DEFAULT_MIRROR"
}

# =========================================
# Проверка одного зеркала: доступность -> применить -> update
# Возвращает 0 если зеркало рабочее, 1 если нет
# =========================================
try_mirror() {
    HOST="$1"; NAME="${2:-$1}"

    echo -e "${CYAN}Проверяем зеркало:${NC} $NAME ${DGRAY}($HOST)${NC}"
    echo -ne "  доступность ... "
    if ! wget -q --spider --timeout="$MIRROR_TIMEOUT" "https://$HOST/releases/" >/dev/null 2>&1; then
        echo -e "${RED}недоступно${NC}"
        return 1
    fi
    echo -e "${GREEN}OK${NC}"

    apply_mirror "$HOST"

    echo -ne "  обновление списка пакетов ... "
    UPDATE_LOG="$($UPDATE 2>&1)"
    UPDATE_RC=$?
    if [ "$UPDATE_RC" -eq 0 ]; then
        echo -e "${GREEN}успешно${NC}"
        return 0
    else
        echo -e "${RED}ошибка!${NC}"
        echo -e "${DGRAY}$(echo "$UPDATE_LOG" | tail -n 5)${NC}"
        return 1
    fi
}

# =========================================
# Ручной выбор одного зеркала (из меню)
# =========================================
set_mirror() {
    HOST="$1"; NAME="$2"
    echo ""
    if try_mirror "$HOST" "$NAME"; then
        echo -e "${GREEN}Пакеты обновлены! Зеркало работает!${NC}\n"
    else
        echo -e "\n${RED}Зеркало не подходит!${NC}\n${GREEN}Зеркало сброшено на ${NC}default ${GREEN}/${NC} OpenWrt${GREEN}!${NC}\n"
        reset_to_default
    fi
    PAUSE
}

# =========================================
# Текущее зеркало по конфигу (сверяется со списком MIRRORS)
# =========================================
curr_MIR() {
    [ -f "$CONFZ" ] || { echo "файл не найден"; return; }
    URL=$(head -n1 "$CONFZ")
    OLDIFS="$IFS"; IFS='
'
    for line in $MIRRORS; do
        HOST="${line%%|*}"; NAME="${line#*|}"
        case "$URL" in
            *"$HOST"*) IFS="$OLDIFS"; echo "$NAME"; return ;;
        esac
    done
    IFS="$OLDIFS"
    echo "неизвестное"
}

# =========================================
# Автоподбор: перебор по MIRRORS, доступность -> update,
# провал -> следующее зеркало, повторов нет
# =========================================
auto_MIR() {
    echo -e "\n${MAGENTA}Автоматический подбор рабочего зеркала${NC}\n"
    FOUND=""
    OLDIFS="$IFS"; IFS='
'
    for line in $MIRRORS; do
        HOST="${line%%|*}"; NAME="${line#*|}"
        if try_mirror "$HOST" "$NAME"; then
            FOUND="$NAME"
            break
        fi
        echo -e "  ${YELLOW}пропускаем, пробуем следующее зеркало${NC}"
    done
    IFS="$OLDIFS"

    echo ""
    if [ -n "$FOUND" ]; then
        echo -e "${GREEN}Рабочее зеркало найдено и применено:${NC} $FOUND\n"
    else
        echo -e "${RED}Ни одно зеркало не прошло проверку!${NC}\n${GREEN}Зеркало сброшено на ${NC}default ${GREEN}/${NC} OpenWrt${GREEN}!${NC}\n"
        reset_to_default
    fi
    PAUSE
}

# =========================================
# Меню: 1-9 выбор зеркала, 0 автотест, любой другой ввод — выход
# =========================================
menu_MIR() {
    while true; do
        clear
        CURR=$(curr_MIR)
        echo -e "${MAGENTA}Меню выбора зеркала OpenWrt${NC}\n"
        echo -e "${YELLOW}Используется зеркало: ${GREEN}$CURR${NC}\n"
        echo -e "${CYAN}0)${NC} Автоподбор рабочего зеркала ${DGRAY}(рекомендуется)${NC}\n"

        i=1
        OLDIFS="$IFS"; IFS='
'
        for line in $MIRRORS; do
            NAME="${line#*|}"
            echo -e "${CYAN}$i)${NC} $NAME"
            i=$((i+1))
        done
        IFS="$OLDIFS"

        echo -e "\n${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n"
        echo -en "${YELLOW}Выберите зеркало: ${NC}"
        read -r z

        case "$z" in
            0)
                auto_MIR
                ;;
            1|2|3|4|5|6|7|8|9)
                i=1
                OLDIFS="$IFS"; IFS='
'
                MATCH=""
                for line in $MIRRORS; do
                    [ "$i" = "$z" ] && MATCH="$line" && break
                    i=$((i+1))
                done
                IFS="$OLDIFS"
                [ -n "$MATCH" ] && set_mirror "${MATCH%%|*}" "${MATCH#*|}"
                ;;
            *)
                break
                ;;
        esac
    done
}

# =========================================
# Точка входа
# =========================================
menu_MIR
