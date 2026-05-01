#!/bin/sh

### =======================
### BASE SETTINGS
### =======================

# Определяем тип пакетного менеджера
if command -v opkg >/dev/null 2>&1; then
    # OpenWrt 23.05 и старше (opkg)
    BASE="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    EXT="ipk"
    INSTALL="opkg install"
    REMOVE="opkg remove"
    PKG_TYPE="opkg"
elif command -v apk >/dev/null 2>&1; then
    # OpenWrt 24.10+ (apk)
    BASE="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    EXT="apk"
    INSTALL="apk add --allow-untrusted"
    REMOVE="apk del"
    PKG_TYPE="apk"
else
    echo "Ошибка: не найден ни opkg, ни apk"
    exit 1
fi

TMP="/tmp/routerich"
mkdir -p "$TMP"

CACHE="$TMP/index.html"

# Функция для безопасного скачивания
download_file() {
    url="$1"
    output="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 15 --max-time 30 "$url" -o "$output"
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=15 "$url" -O "$output" 2>/dev/null
        return $?
    else
        log "Ошибка: не найден ни curl, ни wget"
        return 1
    fi
}

update_cache() {
    download_file "$BASE" "$CACHE"
    if [ $? -ne 0 ]; then
        log "Ошибка: не удалось получить список пакетов"
        return 1
    fi
    return 0
}

### =======================
### LOG
### =======================

log() { echo "[*] $1"; }

### =======================
### GET REMOTE FILE + VERSION
### =======================

get_remote_file() {
    NAME="$1"
    
    if [ ! -f "$CACHE" ]; then
        update_cache || return 1
    fi

    # Парсим HTML и ищем файлы пакетов
    cat "$CACHE" \
        | grep -oE "href=\"${NAME}-[0-9][^\"]+\.${EXT}\"" \
        | sed 's/href="//;s/"//' \
        | sort -V \
        | tail -n1
}

get_version() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*[-_r][0-9]+' | head -n1
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
        # Для opkg
        opkg list-installed 2>/dev/null | awk -v n="$NAME" '$1==n {print $3}'
    else
        # Для apk
        if apk info 2>/dev/null | grep -q "^$NAME$"; then
            apk info "$NAME" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*[-_r][0-9]+' | head -n1
        fi
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
    
    # Отладка (можно убрать)
    # echo "DEBUG: $NAME -> LOCAL: '$LOCAL_VER', REMOTE: '$REMOTE_VER'" >&2
    
    if [ -z "$LOCAL_VER" ] && [ -n "$REMOTE_VER" ]; then
        echo "install|$LOCAL_VER|$REMOTE_VER"
        return
    fi
    
    if [ -n "$LOCAL_VER" ] && [ -n "$REMOTE_VER" ] && [ "$LOCAL_VER" != "$REMOTE_VER" ]; then
        echo "update|$LOCAL_VER|$REMOTE_VER"
        return
    fi
    
    if [ -n "$LOCAL_VER" ]; then
        echo "remove|$LOCAL_VER|$REMOTE_VER"
        return
    fi
    
    echo "error||"
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
            echo "$NAME (не установлен / $RVER) → Установить"
            ;;
        update)
            echo "$NAME ($LVER → $RVER) → Обновить"
            ;;
        remove)
            echo "$NAME ($LVER) → Удалить"
            ;;
        *)
            echo "$NAME (?) → Недоступно"
            ;;
    esac
}

### =======================
### INSTALL / UPDATE
### =======================

install_pkg() {
    NAME="$1"
    
    log "=== Установка/обновление $NAME ==="
    
    # Обновляем кэш перед установкой
    update_cache
    
    FILE="$(get_remote_file "$NAME")"
    LUCI="$(get_remote_file "luci-app-$NAME")"
    
    [ -z "$FILE" ] && log "Ошибка: не найден пакет $NAME" && return 1
    
    DOWNLOADED=0
    
    # Скачиваем основной пакет
    if [ -n "$FILE" ]; then
        URL="$BASE$FILE"
        log "Скачивание: $FILE"
        if download_file "$URL" "$TMP/$FILE"; then
            DOWNLOADED=1
            log "✓ $FILE"
        else
            log "✗ Ошибка скачивания $FILE"
        fi
    fi
    
    # Скачиваем Luci интерфейс (если есть)
    if [ -n "$LUCI" ]; then
        URL="$BASE$LUCI"
        log "Скачивание: $LUCI"
        if download_file "$URL" "$TMP/$LUCI"; then
            DOWNLOADED=1
            log "✓ $LUCI"
        else
            log "✗ Luci интерфейс не найден (опционально)"
        fi
    fi
    
    # Устанавливаем скачанные пакеты
    if [ $DOWNLOADED -eq 1 ] && ls "$TMP"/*.$EXT >/dev/null 2>&1; then
        log "Установка пакетов..."
        
        # Получаем список файлов для установки
        PACKAGES=""
        for pkg_file in "$TMP"/*.$EXT; do
            [ -f "$pkg_file" ] && PACKAGES="$PACKAGES $pkg_file"
        done
        
        if [ -n "$PACKAGES" ]; then
            $INSTALL $PACKAGES
            
            if [ $? -eq 0 ]; then
                log "✓ Установка завершена успешно"
            else
                log "✗ Ошибка при установке"
            fi
        fi
    else
        log "✗ Нет файлов для установки"
    fi
    
    # Очистка
    rm -f "$TMP"/*.$EXT
    
    return 0
}

### =======================
### REMOVE
### =======================

remove_pkg() {
    NAME="$1"
    
    log "=== Удаление $NAME ==="
    
    # Удаляем luci интерфейс если есть
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed | grep -q "luci-app-$NAME" && $REMOVE "luci-app-$NAME"
    else
        apk info 2>/dev/null | grep -q "^luci-app-$NAME$" && $REMOVE "luci-app-$NAME"
    fi
    
    # Удаляем основной пакет
    $REMOVE "$NAME"
    
    if [ $? -eq 0 ]; then
        log "✓ Удаление завершено"
    else
        log "✗ Ошибка при удалении"
    fi
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
### MENU
### =======================

menu() {
    while true; do
        clear
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
            1) 
                action_pkg zapret2
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            2) 
                action_pkg zeroblock
                echo ""
                read -p "Нажмите Enter для продолжения..."
                ;;
            0) 
                echo "До свидания!"
                exit 0 
                ;;
            *) 
                echo "Неверный выбор"
                sleep 1 
                ;;
        esac
    done
}

# Проверяем наличие необходимых утилит
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Ошибка: нужен curl или wget"
    exit 1
fi

# Запускаем меню
menu
