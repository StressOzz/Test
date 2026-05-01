#!/bin/sh

ARCH="$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -n1)"
[ -z "$ARCH" ] && ARCH="$(apk --print-arch 2>/dev/null)"

if command -v opkg >/dev/null 2>&1; then
    BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    EXT="ipk"
    INSTALL="opkg install"
    REMOVE="opkg remove"
    LIST="opkg list-installed"
else
    BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    EXT="apk"
    INSTALL="apk add --allow-untrusted"
    REMOVE="apk del"
    LIST="apk info -e"
fi

TMP="/tmp/routerich"
mkdir -p "$TMP"

log() {
    echo "[*] $1"
}

fetch() {
    NAME="$1"
    echo "[*] Поиск пакета: $NAME" >&2

    FILE="$(curl -s "$BASE" | grep -o "$NAME[^\" ]*\.$EXT" | head -n1)"

    if [ -n "$FILE" ]; then
        echo "[*] Найден: $FILE" >&2
        echo "$FILE"
    else
        echo "[*] Не найден" >&2
        echo ""
    fi
}

is_installed() {
    PKG="$1"
    if echo "$LIST" | grep -q "opkg"; then
        $LIST | grep -q "^$PKG "
    else
        $LIST "$PKG" >/dev/null 2>&1
    fi
}

download_pkg() {
    FILE="$1"
    URL="$BASE$FILE"
    log "Скачивание: $URL"
    wget "$URL" -O "$TMP/$FILE"
}

install_pkg() {
    NAME="$1"

    log "=== Установка $NAME ==="

    PKG="$(fetch $NAME)"
    LUCI="$(fetch luci-app-$NAME)"

    [ -n "$PKG" ] && download_pkg "$PKG"
    [ -n "$LUCI" ] && download_pkg "$LUCI"

    if ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка пакетов..."
        $INSTALL $TMP/*.$EXT
        log "Установка завершена"
    else
        log "Нечего устанавливать"
    fi

    rm -f $TMP/*.$EXT
}

remove_pkg() {
    NAME="$1"

    log "=== Удаление $NAME ==="
    log "Удаляем luci-app-$NAME"
    $REMOVE luci-app-$NAME

    log "Удаляем $NAME"
    $REMOVE $NAME

    log "Удаление завершено"
}

toggle_pkg() {
    NAME="$1"

    if is_installed "$NAME"; then
        log "$NAME уже установлен → удаляем"
        remove_pkg "$NAME"
    else
        log "$NAME не установлен → ставим"
        install_pkg "$NAME"
    fi
}

get_label() {
    NAME="$1"
    if is_installed "$NAME"; then
        echo "Удалить $NAME"
    else
        echo "Установить $NAME"
    fi
}

menu() {
    while true; do
        clear
        echo "====== Routerich Manager ======"
        echo "1) $(get_label zapret2)"
        echo "2) $(get_label zeroblock)"
        echo "0) Выход"
        echo "==============================="
        printf "Выбор: "
        read -r opt

        case "$opt" in
            1) toggle_pkg zapret2; read -p "Enter..." ;;
            2) toggle_pkg zeroblock; read -p "Enter..." ;;
            0) exit 0 ;;
            *) echo "Неверный выбор"; sleep 1 ;;
        esac
    done
}

menu
