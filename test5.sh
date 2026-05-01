#!/bin/sh

### =======================
### BASE SETTINGS
### =======================

ARCH="$(opkg print-architecture 2>/dev/null | awk '{print $2}' | tail -n1)"
[ -z "$ARCH" ] && ARCH="$(apk --print-arch 2>/dev/null)"

if command -v opkg >/dev/null 2>&1; then
    BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    EXT="ipk"
    INSTALL="opkg install"
    REMOVE="opkg remove"
else
    BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    EXT="apk"
    INSTALL="apk add --allow-untrusted"
    REMOVE="apk del"
fi

TMP="/tmp/routerich"
mkdir -p "$TMP"

### =======================
### LOG
### =======================

log() { echo "[*] $1"; }

### =======================
### FETCH PACKAGE NAME
### =======================

fetch() {
    NAME="$1"

    echo "[*] Поиск пакета: $NAME" >&2

    FILE="$(curl -s "$BASE" | grep -o "$NAME[^\" ]*\.$EXT" | head -n1)"

    if [ -n "$FILE" ]; then
        echo "[*] Найден: $FILE" >&2
        printf "%s" "$FILE"
    else
        echo "[*] Не найден" >&2
        printf ""
    fi
}

### =======================
### VERSION PARSER
### =======================

get_ver_remote() {
    FILE="$1"
    echo "$FILE" | sed -E 's/.*_([0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+)\..*/\1/'
}

get_local_ver() {
    NAME="$1"

    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | awk -v n="$NAME" '$1==n {print $3}'
    else
        apk info "$NAME" 2>/dev/null | head -n1 | sed -E "s/^$NAME-//"
    fi
}

### =======================
### STATE ENGINE
### =======================

get_state() {
    NAME="$1"

    FILE="$(fetch "$NAME")"

    REMOTE_VER="$(echo "$FILE" | sed -E 's/.*([0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+).*/\1/')"
    LOCAL_VER="$(get_local_ver "$NAME")"

    if [ -z "$LOCAL_VER" ]; then
        echo "install|$LOCAL_VER|$REMOTE_VER"
    elif [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
        echo "update|$LOCAL_VER|$REMOTE_VER"
    else
        echo "remove|$LOCAL_VER|$REMOTE_VER"
    fi
}

### =======================
### MENU LABEL
### =======================

get_label() {
    NAME="$1"

    DATA="$(get_state "$NAME")"
    STATE="$(echo "$DATA" | cut -d'|' -f1)"
    LVER="$(echo "$DATA" | cut -d'|' -f2)"
    RVER="$(echo "$DATA" | cut -d'|' -f3)"

    case "$STATE" in
        install)
            echo "$NAME (нет / $RVER) → Установить"
            ;;
        update)
            echo "$NAME ($LVER → $RVER) → Обновить"
            ;;
        remove)
            echo "$NAME ($LVER) → Удалить"
            ;;
    esac
}

### =======================
### INSTALL / UPDATE
### =======================

install_pkg() {
    NAME="$1"

    log "=== Установка/обновление $NAME ==="

    PKG="$(fetch $NAME)"
    LUCI="$(fetch luci-app-$NAME)"

    for f in "$PKG" "$LUCI"; do
        [ -n "$f" ] && {
            URL="$BASE$f"
            log "Скачивание: $URL"
            wget -q "$URL" -O "$TMP/$f"
        }
    done

    if ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка..."
        $INSTALL $TMP/*.$EXT
        log "Готово"
    else
        log "Нечего устанавливать"
    fi

    rm -f $TMP/*.$EXT
}

### =======================
### REMOVE
### =======================

remove_pkg() {
    NAME="$1"

    log "=== Удаление $NAME ==="
    $REMOVE luci-app-$NAME 2>/dev/null
    $REMOVE $NAME 2>/dev/null
    log "Удалено"
}

### =======================
### ACTION ROUTER
### =======================

action_pkg() {
    NAME="$1"

    STATE="$(get_state "$NAME" | cut -d'|' -f1)"

    case "$STATE" in
        install|update) install_pkg "$NAME" ;;
        remove) remove_pkg "$NAME" ;;
    esac
}

### =======================
### MENU
### =======================

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
