#!/bin/sh

ARCH="$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -n1)"
[ -z "$ARCH" ] && ARCH="$(apk --print-arch 2>/dev/null)"

if command -v opkg >/dev/null 2>&1; then
    BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    EXT="ipk"
    INSTALL="opkg install"
    REMOVE="opkg remove"
    LIST_INST="opkg list-installed"
    GET_VER_INST() { $LIST_INST | grep "^$1 " | awk '{print $3}' | cut -d'-' -f1; }
else
    BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    EXT="apk"
    INSTALL="apk add --allow-untrusted"
    REMOVE="apk del"
    LIST_INST="apk info"
    GET_VER_INST() { $LIST_INST "$1" 2>/dev/null | head -n1 | awk '{print $1}' | sed "s/^$1-//" | cut -d'-' -f1; }
fi

TMP="/tmp/routerich"
mkdir -p "$TMP"

log() { echo "[*] $1"; }

fetch() {
    NAME="$1"
    echo "[*] Поиск пакета: $NAME" >&2
    FILE="$(curl -s "$BASE" | grep -o "$NAME[^\" ]*\.$EXT" | head -n1)"
    [ -n "$FILE" ] && echo "[*] Найден: $FILE" >&2 || echo "[*] Не найден" >&2
    echo "$FILE"
}

get_ver_remote() {
    FILE="$1"
    echo "$FILE" | sed -E "s/^.*[-_]([0-9.]+)-r?[0-9]+.*$/\1/"
}

is_installed() {
    GET_VER_INST "$1" >/dev/null 2>&1
}

install_pkg() {
    NAME="$1"

    log "=== Установка/обновление $NAME ==="

    PKG="$(fetch $NAME)"
    LUCI="$(fetch luci-app-$NAME)"

    for f in "$PKG" "$LUCI"; do
        [ -n "$f" ] && {
            URL="$BASE$f"
            log "Скачивание: $URL"
            wget "$URL" -O "$TMP/$f"
        }
    done

    if ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка пакетов..."
        $INSTALL $TMP/*.$EXT
        log "Готово"
    else
        log "Нечего устанавливать"
    fi

    rm -f $TMP/*.$EXT
}

remove_pkg() {
    NAME="$1"
    log "Удаление $NAME"
    $REMOVE luci-app-$NAME 2>/dev/null
    $REMOVE $NAME 2>/dev/null
}

get_state() {
    NAME="$1"

    if ! is_installed "$NAME"; then
        echo "install"
        return
    fi

    INST_VER="$(GET_VER_INST "$NAME")"
    FILE="$(fetch $NAME)"
    REMOTE_VER="$(get_ver_remote "$FILE")"

    if [ -n "$REMOTE_VER" ] && [ "$INST_VER" != "$REMOTE_VER" ]; then
        echo "update"
    else
        echo "remove"
    fi
}

get_label() {
    NAME="$1"
    STATE="$(get_state "$NAME")"

    case "$STATE" in
        install) echo "Установить $NAME" ;;
        update)  echo "Обновить $NAME" ;;
        remove)  echo "Удалить $NAME" ;;
    esac
}

action_pkg() {
    NAME="$1"
    STATE="$(get_state "$NAME")"

    case "$STATE" in
        install|update) install_pkg "$NAME" ;;
        remove) remove_pkg "$NAME" ;;
    esac
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
            1) action_pkg zapret2; read -p "Enter..." ;;
            2) action_pkg zeroblock; read -p "Enter..." ;;
            0) exit 0 ;;
            *) echo "Неверный выбор"; sleep 1 ;;
        esac
    done
}

menu
