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
    curl -s -L "$BASE" > "$CACHE"
}

log() { echo "[*] $1"; }

### =======================
### GET REMOTE FILE + VERSION
### =======================

get_remote_file() {
    NAME="$1"

    [ ! -f "$CACHE" ] && update_cache

    # Универсальный парсер для обоих типов репозиториев
    # Ищем ссылки вида: name-version.ext или name_version.ext
    cat "$CACHE" | \
        grep -oE "(href=[\"']?)?${NAME}[-\_][0-9][^\"]*\.${EXT}" | \
        sed 's/href=//g; s/["'\'']//g' | \
        head -n1
}

get_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*[-_r][0-9]+|[0-9]+\.[0-9]+(\.[0-9]+)*'
}

get_remote_ver() {
    FILE="$1"
    [ -n "$FILE" ] && get_version "$FILE" || echo ""
}

### =======================
### LOCAL VERSION
### =======================

get_local_ver() {
    NAME="$1"

    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "^$NAME -" | awk '{print $3}'
        # Альтернативный метод
        [ -z "$LOCAL_VER" ] && opkg status "$NAME" 2>/dev/null | grep "^Version" | cut -d' ' -f2
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

    # Отладка для opkg
    if [ "$PKG_TYPE" = "opkg" ]; then
        echo "DEBUG: $NAME -> FILE='$FILE', REMOTE='$REMOTE_VER', LOCAL='$LOCAL_VER'" >&2
    fi

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

    log "Найден основной файл: $FILE"
    
    if [ -z "$FILE" ]; then
        log "ОШИБКА: Не найден пакет $NAME в репозитории"
        return 1
    fi

    # Скачиваем основной пакет
    URL="$BASE$FILE"
    log "Скачивание: $URL"
    
    if command -v wget >/dev/null 2>&1; then
        wget -q "$URL" -O "$TMP/$FILE"
    else
        curl -s -o "$TMP/$FILE" "$URL"
    fi
    
    if [ ! -f "$TMP/$FILE" ]; then
        log "ОШИБКА: Не удалось скачать $FILE"
        return 1
    fi
    
    # Скачиваем luci если есть
    if [ -n "$LUCI" ]; then
        URL="$BASE$LUCI"
        log "Скачивание luci: $URL"
        if command -v wget >/dev/null 2>&1; then
            wget -q "$URL" -O "$TMP/$LUCI"
        else
            curl -s -o "$TMP/$LUCI" "$URL"
        fi
    fi

    # Установка
    log "Установка пакетов..."
    $INSTALL $TMP/*.$EXT
    
    if [ $? -eq 0 ]; then
        log "✓ Установка завершена успешно"
    else
        log "✗ Ошибка при установке"
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
    log "✓ Удаление завершено"
}

### =======================
### ACTION
### =======================

action_pkg() {
    NAME="$1"

    STATE="$(get_state "$NAME" | cut -d'|' -f1)"

    case "$STATE" in
        install|update) 
            install_pkg "$NAME" 
            ;;
        remove) 
            remove_pkg "$NAME" 
            ;;
        *) 
            log "Ошибка: пакет $NAME недоступен" 
            ;;
    esac
}

### =======================
### DIAGNOSTICS
### =======================

diagnostic() {
    echo "=== Diagnostic ==="
    echo "PKG_TYPE: $PKG_TYPE"
    echo "BASE: $BASE"
    echo "EXT: $EXT"
    echo ""
    echo "Testing connection..."
    curl -s -I "$BASE" | head -n1
    echo ""
    echo "Looking for zapret2..."
    curl -s "$BASE" | grep -i "zapret" | head -n5
    echo ""
    echo "=== End Diagnostic ==="
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
        echo "3) Диагностика"
        echo "0) Выход"
        echo "==============================="

        printf "Выбор: "
        read -r opt

        case "$opt" in
            1) action_pkg zapret2; read -p "Нажмите Enter..." ;;
            2) action_pkg zeroblock; read -p "Нажмите Enter..." ;;
            3) diagnostic; read -p "Нажмите Enter..." ;;
            0) exit 0 ;;
            *) echo "Неверно"; sleep 1 ;;
        esac
    done
}

menu
