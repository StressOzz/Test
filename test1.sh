#!/bin/sh

### =======================================================================
### АВТООПРЕДЕЛЕНИЕ ТИПА ПАКЕТНОГО МЕНЕДЖЕРА И НАСТРОЙКА РЕПОЗИТОРИЯ
### =======================================================================

# Определяем менеджер
if command -v opkg >/dev/null 2>&1; then
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg remove"
    PKG_TYPE="opkg"
    
    # Определяем архитектуру устройства
    # Для mediatek/filogic это всегда aarch64_cortex-a53
    ARCH_SUFFIX="aarch64_cortex-a53"
    
else
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX=""
fi

TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Функция для скачивания
download_file() {
    local url="$1"
    local output="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 20 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 "$url" -O "$output" 2>/dev/null
    fi
}

# Обновление кэша
update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
}

log() { echo "[*] $1"; }

### =======================================================================
### ФУНКЦИИ ДЛЯ РАБОТЫ С ПАКЕТАМИ
### =======================================================================

# Получение имени удаленного файла пакета (ТОЛЬКО ДЛЯ OPKG)
get_opkg_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем файл с правильной архитектурой
    grep -o "${pkg_name}_[0-9][^\"]*_${ARCH_SUFFIX}\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени luci-файла (ТОЛЬКО ДЛЯ OPKG)
get_opkg_luci_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Luci интерфейс всегда с архитектурой _all
    grep -o "luci-app-${pkg_name}_[0-9][^\"]*_all\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени удаленного файла для APK (включая luci если он отдельный)
get_apk_file() {
    local pkg_name="$1"
    local include_luci="$2"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    if [ "$include_luci" = "luci" ]; then
        grep -o "luci-app-${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
    else
        grep -o "${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
    fi
}

# Извлечение версии из имени файла для OPKG
get_opkg_version() {
    local filename="$1"
    echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

# Извлечение версии из имени файла для APK
get_apk_version() {
    local filename="$1"
    echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

# Получение установленной версии
get_local_version() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "^$pkg_name -" | awk '{print $3}'
    else
        apk list --installed 2>/dev/null | grep "^$pkg_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
    fi
}

# Проверка установлен ли luci интерфейс
is_luci_installed() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep -q "luci-app-$pkg_name"
    else
        apk list --installed 2>/dev/null | grep -q "luci-app-$pkg_name"
    fi
}

### =======================================================================
### ОПРЕДЕЛЕНИЕ СОСТОЯНИЯ ПАКЕТА
### =======================================================================

get_package_state() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        local main_file="$(get_opkg_file "$pkg_name")"
        local luci_file="$(get_opkg_luci_file "$pkg_name")"
        
        if [ -n "$main_file" ]; then
            remote_ver="$(get_opkg_version "$main_file")"
        else
            remote_ver=""
        fi
    else
        local main_file="$(get_apk_file "$pkg_name" "")"
        local luci_file=""
        
        # Для APK проверяем есть ли отдельный luci пакет
        local luci_remote_file="$(get_apk_file "$pkg_name" "luci")"
        
        if [ -n "$main_file" ]; then
            remote_ver="$(get_apk_version "$main_file")"
        else
            remote_ver=""
        fi
    fi
    
    local local_ver="$(get_local_version "$pkg_name")"
    
    # Сохраняем имена файлов в глобальные переменные для установки
    MAIN_FILE="$main_file"
    LUCI_FILE="$luci_file"
    LUCI_REMOTE_FILE="$luci_remote_file"
    
    # Отладка
    echo "DEBUG: $pkg_name -> MAIN='$main_file', LUCI='$luci_file', REMOTE='$remote_ver', LOCAL='$local_ver'" >&2
    
    if [ -z "$local_ver" ] && [ -n "$remote_ver" ]; then
        echo "install|$local_ver|$remote_ver"
    elif [ -n "$local_ver" ] && [ -n "$remote_ver" ] && [ "$local_ver" != "$remote_ver" ]; then
        echo "update|$local_ver|$remote_ver"
    elif [ -n "$local_ver" ]; then
        echo "remove|$local_ver|$remote_ver"
    else
        echo "error||"
    fi
}

### =======================================================================
### УСТАНОВКА И УДАЛЕНИЕ
### =======================================================================

install_package() {
    local pkg_name="$1"
    
    log "=== Установка/обновление $pkg_name ==="
    
    # Получаем состояние (это заполнит MAIN_FILE, LUCI_FILE и LUCI_REMOTE_FILE)
    get_package_state "$pkg_name" > /dev/null
    
    if [ -z "$MAIN_FILE" ]; then
        log "ОШИБКА: Не найден пакет $pkg_name"
        return 1
    fi
    
    # Скачиваем основной пакет
    local main_url="${BASE_URL}${MAIN_FILE}"
    log "Скачивание: $MAIN_FILE"
    download_file "$main_url" "$TMP_DIR/$MAIN_FILE"
    
    if [ ! -f "$TMP_DIR/$MAIN_FILE" ]; then
        log "ОШИБКА: Не удалось скачать $MAIN_FILE"
        return 1
    fi
    
    # Скачиваем luci если есть (для opkg)
    if [ "$PKG_TYPE" = "opkg" ] && [ -n "$LUCI_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_FILE}"
        log "Скачивание: $LUCI_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_FILE"
    fi
    
    # Для APK скачиваем luci если он существует отдельно
    if [ "$PKG_TYPE" = "apk" ] && [ -n "$LUCI_REMOTE_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_REMOTE_FILE}"
        log "Скачивание: $LUCI_REMOTE_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_REMOTE_FILE"
    fi
    
    # Установка
    log "Установка пакетов..."
    local packages_to_install=$(ls "$TMP_DIR"/*.$PKG_EXT 2>/dev/null)
    
    if [ -n "$packages_to_install" ]; then
        $PKG_INSTALL $packages_to_install
        if [ $? -eq 0 ]; then
            log "✓ Установка/обновление завершено"
            
            # Перезапускаем веб-интерфейс если установлен luci
            if [ "$PKG_TYPE" = "opkg" ] && [ -n "$LUCI_FILE" ] || \
               [ "$PKG_TYPE" = "apk" ] && [ -n "$LUCI_REMOTE_FILE" ]; then
                log "Перезапуск веб-интерфейса..."
                /etc/init.d/uhttpd restart 2>/dev/null
                /etc/init.d/rpcd restart 2>/dev/null
            fi
        else
            log "✗ Ошибка при установке"
        fi
    fi
    
    # Очистка
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

remove_package() {
    local pkg_name="$1"
    
    log "=== Удаление $pkg_name ==="
    
    # Удаляем основной пакет и luci если он есть
    if [ "$PKG_TYPE" = "opkg" ]; then
        $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
        $PKG_REMOVE "$pkg_name" 2>/dev/null
    else
        # Для APK сначала пробуем удалить luci если он установлен
        if is_luci_installed "$pkg_name"; then
            $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
        fi
        $PKG_REMOVE "$pkg_name" 2>/dev/null
    fi
    
    log "✓ Удаление завершено"
    
    # Перезапускаем веб-интерфейс если был удален luci
    if is_luci_installed "$pkg_name" 2>/dev/null || [ "$PKG_TYPE" = "opkg" ]; then
        /etc/init.d/uhttpd restart 2>/dev/null
        /etc/init.d/rpcd restart 2>/dev/null
    fi
}

### =======================================================================
### ОТОБРАЖЕНИЕ МЕНЮ
### =======================================================================

get_menu_label() {
    local pkg_name="$1"
    local state_data="$(get_package_state "$pkg_name")"
    
    local action="$(echo "$state_data" | cut -d'|' -f1)"
    local local_ver="$(echo "$state_data" | cut -d'|' -f2)"
    local remote_ver="$(echo "$state_data" | cut -d'|' -f3)"
    
    case "$action" in
        install) echo "$pkg_name (не установлен / $remote_ver) → Установить" ;;
        update)  echo "$pkg_name ($local_ver → $remote_ver) → Обновить" ;;
        remove)  echo "$pkg_name ($local_ver) → Удалить" ;;
        *)       echo "$pkg_name → Недоступно" ;;
    esac
}

run_action() {
    local pkg_name="$1"
    local action="$(get_package_state "$pkg_name" | cut -d'|' -f1)"
    
    case "$action" in
        install|update) install_package "$pkg_name" ;;
        remove)         remove_package "$pkg_name" ;;
        *)              log "Ошибка: пакет $pkg_name недоступен" ;;
    esac
}

### =======================================================================
### МЕНЮ
### =======================================================================

menu() {
    while true; do
        clear
        update_cache >/dev/null 2>&1
        echo "======================================"
        echo "       RouterICH Package Manager       "
        echo "======================================"
        echo "  Package Manager: $PKG_TYPE"
        [ "$PKG_TYPE" = "opkg" ] && echo "  Architecture: $ARCH_SUFFIX"
        echo "======================================"
        echo "  1) $(get_menu_label zapret2)"
        echo "  2) $(get_menu_label zeroblock)"
        echo "  0) Выход"
        echo "======================================"
        
        printf "  Выбор: "
        read -r user_choice
        
        case "$user_choice" in
            1) run_action zapret2; read -p "  Нажмите Enter..." ;;
            2) run_action zeroblock; read -p "  Нажмите Enter..." ;;
            0) echo "  До свидания!"; exit 0 ;;
            *) echo "  Неверный выбор"; sleep 1 ;;
        esac
    done
}

# Запуск
menu
