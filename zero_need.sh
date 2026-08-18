#!/bin/sh
clear

echo -e "\n${CYAN}╭──────────────────────────────────────────────────────╮${NC}"

echo -e "${CYAN}│${NC}                  ${GREEN}ZeroBlock${NC}                          ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}              ${YELLOW}Dependencies Installer${NC}              ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}                                                      ${CYAN}│${NC}"
echo -e "${CYAN}╰──────────────────────────────────────────────────────╯${NC}\n"



# ==========================================
# ZeroBlock — зависимости
# ==========================================

BASE_URL="https://downloads.openwrt.org/snapshots/packages/aarch64_cortex-a53"
TMP_DIR="/tmp/zb-libs"

PACKAGES="
libubox20260721-2026.07.21~e7608b69-r1.apk|base
libblobmsg-json20260721-2026.07.21~e7608b69-r1.apk|base
libubus20260628-2026.06.28~24864e78-r1.apk|base
libyaml-0.2.5-r2.apk|packages
"

# Проверка apk
if ! command -v apk >/dev/null 2>&1; then
    echo "Ошибка: apk не найден"
    exit 1
fi

# Проверка архитектуры
ARCH="$(awk -F= '/^DISTRIB_ARCH=/{gsub(/'\''/, "", $2); print $2}' /etc/openwrt_release)"

if [ "$ARCH" != "aarch64_cortex-a53" ]; then
    echo "Ошибка: неподдерживаемая архитектура: $ARCH"
    exit 1
fi

echo "Архитектура: $ARCH"

# Создаём временный каталог
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" || {
    echo "Ошибка создания $TMP_DIR"
    exit 1
}

# Загрузка пакетов
for ITEM in $PACKAGES; do
    FILE="${ITEM%%|*}"
    REPO="${ITEM#*|}"
    URL="$BASE_URL/$REPO/$FILE"

    echo "Скачиваем: $FILE"

    wget -q "$URL" -O "$TMP_DIR/$FILE" || {
        echo "Ошибка загрузки: $FILE"
        rm -rf "$TMP_DIR"
        exit 1
    }

    [ -s "$TMP_DIR/$FILE" ] || {
        echo "Ошибка: файл пустой: $FILE"
        rm -rf "$TMP_DIR"
        exit 1
    }
done

echo
echo "Устанавливаем зависимости..."

apk add --allow-untrusted \
    "$TMP_DIR/libubox20260721-2026.07.21~e7608b69-r1.apk" \
    "$TMP_DIR/libblobmsg-json20260721-2026.07.21~e7608b69-r1.apk" \
    "$TMP_DIR/libubus20260628-2026.06.28~24864e78-r1.apk" \
    "$TMP_DIR/libyaml-0.2.5-r2.apk" || {
    echo
    echo "Ошибка установки зависимостей"
    rm -rf "$TMP_DIR"
    exit 1
}

echo
echo "Проверяем установленные пакеты..."

if apk list --installed | grep -q '^libubox20260721-'; then
    echo "[ OK ] libubox20260721"
else
    echo "[FAIL] libubox20260721"
    exit 1
fi

if apk list --installed | grep -q '^libblobmsg-json20260721-'; then
    echo "[ OK ] libblobmsg-json20260721"
else
    echo "[FAIL] libblobmsg-json20260721"
    exit 1
fi

if apk list --installed | grep -q '^libubus20260628-'; then
    echo "[ OK ] libubus20260628"
else
    echo "[FAIL] libubus20260628"
    exit 1
fi

if apk list --installed | grep -q '^libyaml-0.2.5-'; then
    echo "[ OK ] libyaml-0.2.5"
else
    echo "[FAIL] libyaml-0.2.5"
    exit 1
fi

rm -rf "$TMP_DIR"

echo
echo "Все зависимости успешно установлены!"
