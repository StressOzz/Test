#!/bin/sh

### =======================
### BASE SETTINGS
### =======================

if command -v opkg >/dev/null 2>&1; then
    BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    EXT="ipk"
    INSTALL="opkg install"
    REMOVE="opkg remove"
    PKG_TYPE="opkg"
else
    BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    EXT="apk"
    INSTALL="apk add --allow-untrusted"
    REMOVE="apk del"
    PKG_TYPE="apk"
fi

TMP="/tmp/routerich"
mkdir -p "$TMP"

CACHE="$TMP/index.html"

update_cache() {
    curl -s "$BASE" > "$CACHE"
}

log() { echo "[*] $1"; }

### =======================
### GET REMOTE FILE + VERSION
### =======================

get_remote_file() {
    NAME="$1"

    [ ! -f "$CACHE" ] && update_cache

    # Простой поиск по имени файла
    cat "$CACHE" | grep -o "${NAME}-[^\"]*\.${EXT}" | head -n1
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

    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | awk -v n="$NAME" '$1==n {print $3}'
    else
        apk list --installed 2>/dev/null | grep "^$NAME" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
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

    # Отладка
    echo "DEBUG: $NAME -> LOCAL: '$LOCAL_VER', REMOTE: '$REMOTE_VER', FILE: '$FILE'" >&2

    if [ -z "$LOCAL_VER" ] && [ -n "$REMOTE_VER" ]; then
        echo "install|$LOCAL_VER|$REMOTE_VER"
    elif [ -n "$LOCAL_VER" ] && [ -n "$REMOTE_VER" ] && [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
        echo "update|$LOCAL_VER|$REMOTE_VER"
    elif [ -n "$LOCAL_VER" ]; then
        echo "remove|$LOCAL_VER|$REMOTE_VER"
    else
        echo "error||"
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
        *)
            echo "$NAME → Недоступно"
            ;;
    esac
}

### =======================
### INSTALL / UPDATE
### =======================

install_pkg() {
    NAME="$1"

    log "=== Установка/обновление $NAME ==="

    # Обновляем кэш
    update_cache

    FILE="$(get_remote_file "$NAME")"
    LUCI="$(get_remote_file "luci-app-$NAME")"

    log "Найден файл: $FILE"

    for f in "$FILE" "$LUCI"; do
        [ -z "$f" ] && continue

        URL="$BASE$f"

        log "Скачивание: $URL"

        wget -q "$URL" -O "$TMP/$f" 2>/dev/null
        
        if [ -f "$TMP/$f" ]; then
            log "OK: $f скачан"
        fi
    done

    # Проверяем, есть ли файлы для установки
    if ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка..."
        $INSTALL $TMP/*.$EXT
        log "Готово"
    else
        log "Ошибка: нет файлов для установки"
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
    log "Готово"
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
        *) log "Ошибка: пакет $NAME недоступен" ;;
    esac
}

### =======================
### MENU
### =======================

menu() {
    while true; do
        clear
        update_cache
        echo "====== Routerich Manager ======"
        echo "Пакетный менеджер: $PKG_TYPE"
        echo "==============================="
        echo "1) $(get_label zapret2)"
        echo "2) $(get_label zeroblock)"
        echo "0) Выход"
        echo "==============================="

        printf "Выбор: "
        read -r opt

        case "$opt" in
            1) action_pkg zapret2; read -p "Нажмите Enter..." ;;
            2) action_pkg zeroblock; read -p "Нажмите Enter..." ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

menu
