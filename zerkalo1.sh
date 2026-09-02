#!/bin/sh
# =========================================
# OpenWRT Mirror Checker & Switcher
# Тестирование и автоподбор зеркала репозитория
# Поддержка: OpenWRT 24.x (opkg) и 25.x (apk)
# =========================================

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; NC="\033[0m"

TIMEOUT=3

# Резервные зеркала в порядке приоритета (без протокола и /releases/)
FALLBACK_MIRRORS="mirror-03.infra.openwrt.org ftp.halifax.rwth-aachen.de/openwrt mirror.accum.se/mirror/openwrt.org ftp.snt.utwente.nl/pub/software/openwrt mirror.berlin.freifunk.net/downloads.openwrt mirror.sjtu.edu.cn/openwrt downloads.openwrt.org"

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

echo -e "${CYAN}Пакетный менеджер:${NC} $PKG"

# =========================================
# Проверка доступности зеркала (https://<mirror>/releases/)
# =========================================
check_mirror() {
    wget -q --spider --timeout="$TIMEOUT" "https://$1/releases/" >/dev/null 2>&1
}

# =========================================
# Определяем текущее зеркало из конфига
# =========================================
CURRENT_MIRROR=$(head -n1 "$CONFZ" | awk '{print $NF}' | sed 's|https://||; s|/releases/.*||')

if [ -z "$CURRENT_MIRROR" ]; then
    echo -e "${RED}Не удалось определить текущее зеркало из${NC} $CONFZ"
    exit 1
fi

echo -e "${CYAN}Текущее зеркало:${NC} $CURRENT_MIRROR"

# Применяем зеркало в конфиге
apply_mirror() {
    sed -i "s|https://.*/releases/|https://$1/releases/|g" "$CONFZ"
}

# =========================================
# Формируем список кандидатов: текущее зеркало + резервные,
# без повторов, в порядке приоритета
# =========================================
CANDIDATES="$CURRENT_MIRROR"
for m in $FALLBACK_MIRRORS; do
    dup=0
    for c in $CANDIDATES; do
        [ "$c" = "$m" ] && dup=1 && break
    done
    [ "$dup" = "0" ] && CANDIDATES="$CANDIDATES $m"
done

# =========================================
# Перебор кандидатов: доступность -> update -> либо готово, либо следующий
# =========================================
FOUND=""

for m in $CANDIDATES; do
    echo -e "${CYAN}Проверяем зеркало:${NC} $m"

    echo -ne "  доступность ... "
    if ! check_mirror "$m"; then
        echo -e "${RED}недоступно${NC}"
        echo -e "  ${YELLOW}пропускаем, пробуем следующее зеркало${NC}"
        continue
    fi
    echo -e "${GREEN}OK${NC}"

    if [ "$m" != "$CURRENT_MIRROR" ]; then
        echo -e "  ${CYAN}переключаемся на:${NC} $m"
    fi
    apply_mirror "$m"

    echo -ne "  обновление списка пакетов (${UPDATE}) ... "
    if $UPDATE >/dev/null 2>&1; then
        echo -e "${GREEN}успешно${NC}"
        FOUND="$m"
        break
    else
        echo -e "${RED}ошибка обновления списка пакетов!${NC}"
        echo -e "  ${YELLOW}зеркало не подходит, пробуем следующее${NC}"
    fi
done

echo ""
if [ -n "$FOUND" ]; then
    echo -e "${GREEN}Рабочее зеркало найдено и применено:${NC} $FOUND"
    exit 0
else
    echo -e "${RED}Ни одно зеркало (текущее и резервные) не прошло проверку!${NC}"
    exit 1
fi
