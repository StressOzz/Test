#!/bin/sh

### =======================================================================
### АВТООПРЕДЕЛЕНИЕ ТИПА ПАКЕТНОГО МЕНЕДЖЕРА И НАСТРОЙКА РЕПОЗИТОРИЯ
### =======================================================================

# Определяем менеджер и архитектуру
if command -v opkg >/dev/null 2>&1; then
    # OpenWrt 23.05 и старше (opkg)
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg remove"
    PKG_TYPE="opkg"
    
    # Определяем архитектуру устройства для поиска правильного пакета
    if [ -f "/etc/openwrt_release" ]; then
        . /etc/openwrt_release
        ARCH="${DISTRIB_TARGET%-*}"
        ARCH="${ARCH##*/}"
        # Для mediatek/filogic это будет "cortex-a53"
        case "$ARCH" in
            *cortex-a53*) ARCH_SUFFIX="aarch64_cortex-a53" ;;
            *) ARCH_SUFFIX="all" ;; # fallback
        esac
    else
        ARCH_SUFFIX="aarch64_cortex-a53" # значение по умолчанию
    fi
else
    # OpenWrt 24.10+ (apk)
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX="" # Для apk суффикс архитектуры не нужен
fi

# Временная директория
TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Функция для скачивания (работает и с curl, и с wget)
download_file() {
    local url="$1"
    local output="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 20 --max-time 60 "$url" -o "$output"
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 "$url" -O "$output" 2>/dev/null
        return $?
    else
        return 1
    fi
}

# Обновление кэша списка пакетов
update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
    return $?
}

# Функция логирования
log() { echo "[*] $1"; }

### =======================================================================
### ФУНКЦИИ ДЛЯ РАБОТЫ С ВЕРСИЯМИ ПАКЕТОВ
### =======================================================================

# Получение имени удаленного файла пакета
get_remote_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache || return 1
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        # Для opkg: ищем zapret2_0.9.5-r2_aarch64_cortex-a53.ipk
        grep -oE "${pkg_name}_[0-9][^\"]+${ARCH_SUFFIX:+_$ARCH_SUFFIX}\.${PKG_EXT}" "$CACHE_FILE" | head -n1
    else
        # Для apk: ищем zapret2-0.9.4.7-r4.apk
        grep -oE "${pkg_name}-[0-9][^\"]+\.${PKG_EXT}" "$CACHE_FILE" | head -n1
    fi
}

# Извлечение версии из имени файла
get_version_from_filename() {
    local filename="$1"
    if [ "$PKG_TYPE" = "opkg" ]; then
        # Из zapret2_0.9.5-r2_aarch64_cortex-a53.ipk -> 0.9.5-r2
        echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
    else
        # Из zapret2-0.9.4.7-r4.apk -> 0.9.4.7-r4
        echo "$filename" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
    fi
}

# Получение установленной версии пакета
get_local_version() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "^$pkg_name -" | awk '{print $3}'
    else
        apk list --installed 2>/dev/null | grep "^$pkg_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
    fi
}

### =======================================================================
### ОПРЕДЕЛЕНИЕ СОСТОЯНИЯ ПАКЕТА
### =======================================================================

get_package_state() {
    local pkg_name="$1"
    
    # Получаем информацию о версиях
    local remote_file="$(get_remote_file "$pkg_name")"
    local remote_ver="$(get_version_from_filename "$remote_file")"
    local local_ver="$(get_local_version "$pkg_name")"
    
    # Принимаем решение о действии
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
### ФУНКЦИИ УСТАНОВКИ/УДАЛЕНИЯ
### =======================================================================

install_package() {
    local pkg_name="$1"
    
    log "=== Установка/обновление $pkg_name ==="
    
    # Обновляем кэш
    update_cache
    
    # Ищем основной пакет и luci-интерфейс
    local main_file="$(get_remote_file "$pkg_name")"
    local luci_file="$(get_remote_file "luci-app-$pkg_name")"
    
    if [ -z "$main_file" ]; then
        log "ОШИБКА: Не найден пакет $pkg_name в репозитории"
        return 1
    fi
    
    # Скачиваем основной пакет
    local main_url="${BASE_URL}${main_file}"
    log "Скачивание: $main_file"
    download_file "$main_url" "$TMP_DIR/$main_file"
    
    if [ ! -f "$TMP_DIR/$main_file" ] || [ ! -s "$TMP_DIR/$main_file" ]; then
        log "ОШИБКА: Не удалось скачать $main_file"
        rm -f "$TMP_DIR/$main_file"
        return 1
    fi
    
    # Скачиваем luci-пакет, если он существует
    if [ -n "$luci_file" ]; then
        local luci_url="${BASE_URL}${luci_file}"
        log "Скачивание: $luci_file"
        download_file "$luci_url" "$TMP_DIR/$luci_file"
        
        # Если скачивание не удалось, просто игнорируем (это опционально)
        if [ ! -f "$TMP_DIR/$luci_file" ] || [ ! -s "$TMP_DIR/$luci_file" ]; then
            log "Предупреждение: Luci-интерфейс не найден (необязательный пакет)"
            rm -f "$TMP_DIR/$luci_file"
        fi
    fi
    
    # Установка скачанных пакетов
    log "Установка пакетов..."
    $PKG_INSTALL $TMP_DIR/*.$PKG_EXT
    
    if [ $? -eq 0 ]; then
        log "✓ Установка/обновление завершено успешно"
    else
        log "✗ Ошибка при установке"
    fi
    
    # Очистка временных файлов
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

remove_package() {
    local pkg_name="$1"
    
    log "=== Удаление $pkg_name ==="
    $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
    $PKG_REMOVE "$pkg_name" 2>/dev/null
    log "✓ Удаление завершено"
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
        install)
            echo "$pkg_name (не установлен / $remote_ver) → Установить"
            ;;
        update)
            echo "$pkg_name ($local_ver → $remote_ver) → Обновить"
            ;;
        remove)
            echo "$pkg_name ($local_ver) → Удалить"
            ;;
        *)
            echo "$pkg_name → Ошибка получения версии"
            ;;
    esac
}

run_action() {
    local pkg_name="$1"
    local action="$(get_package_state "$pkg_name" | cut -d'|' -f1)"
    
    case "$action" in
        install|update) install_package "$pkg_name" ;;
        remove) remove_package "$pkg_name" ;;
        *) log "Ошибка: Действие для пакета $pkg_name не определено" ;;
    esac
}

# Меню
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
            1) run_action zapret2; read -p "  Нажмите Enter для продолжения..." ;;
            2) run_action zeroblock; read -p "  Нажмите Enter для продолжения..." ;;
            0) echo "  До свидания!"; exit 0 ;;
            *) echo "  Неверный выбор"; sleep 1 ;;
        esac
    done
}

# Запуск
menu
