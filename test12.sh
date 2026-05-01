#!/bin/sh

### =======================
### BASE SETTINGS
### =======================

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
### GET REMOTE FILE + VERSION
### =======================

get_remote_file() {
    NAME="$1"

    curl -s "$BASE" \
        | grep -o "href=\"[^\"]*${NAME}[^\" ]*\\.${EXT}\"" \
        | head -n1 \
        | sed -E 's/.*href="([^"]+)".*/\1/'
}

get_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

get_remote_ver() {
    FILE="$1"
    get_version "$FILE"
}

### =======================
### LOCAL VERSION
### =======================

get_local_ver() {
    NAME="$1"

    if command -v opkg >/dev/null 2>&1; then
        opkg list-installed 2>/dev/null | awk -v n="$NAME" '$1==n {print $3}'
    else
        apk info "$NAME" 2>/dev/null | head -n1 | sed -E "s/^$NAME-//"
    fi
}

### =======================
### STATE
### =======================

get_state() {
    NAME="$1"

    FILE="$(get_remote_file "$NAME")"

    REMOTE_VER="$(get_remote_ver "$FILE")"
    LOCAL_VER="$(get_local_ver "$NAME")"

    [ -z "$REMOTE_VER" ] && REMOTE_VER="0.0.0"

    if [ -z "$LOCAL_VER" ]; then
        echo "install|$LOCAL_VER|$REMOTE_VER"
    elif [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
        echo "update|$LOCAL_VER|$REMOTE_VER"
    else
        echo "remove|$LOCAL_VER|$REMOTE_VER"
    fi
}

### =======================
### LABEL
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

    FILE="$(get_remote_file "$NAME")"
    LUCI="$(get_remote_file "luci-app-$NAME")"

    for f in "$FILE" "$LUCI"; do
        [ -z "$f" ] && continue

        URL="$BASE$f"

        log "Скачивание: $URL"

        wget -q --timeout=15 --tries=2 "$URL" -O "$TMP/$f"
    done

    if ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка..."
        $INSTALL $TMP/*.$EXT
        log "Готово"
    else
        log "Нечего устанавливать"
    fi

    rm -f "$TMP"/*.$EXT
}

### =======================
### REMOVE
### =======================

remove_pkg() {
    NAME="$1"

    log "=== Удаление $NAME ==="
    $REMOVE luci-app-$NAME 2>/dev/null
    $REMOVE $NAME 2>/dev/null
}

### =======================
### ACTION
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
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

menu
