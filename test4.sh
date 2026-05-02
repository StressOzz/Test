#!/bin/sh

### =======================================================================
### АВТООПРЕДЕЛЕНИЕ ТИПА ПАКЕТНОГО МЕНЕДЖЕРА И НАСТРОЙКА РЕПОЗИТОРИЯ
### =======================================================================

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"

# Определяем менеджер
if command -v opkg >/dev/null 2>&1; then
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg remove"
    PKG_TYPE="opkg"
    UPDATE="opkg update"
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
    UPDATE="apk update"
fi

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

if ! command -v curl >/dev/null 2>&1; then clear; echo -e "${MAGENTA}Устанавливаем ${NC}curl"; echo -e "${CYAN}Обновляем список пакетов${NC}"; ok=0; for i in 1 2 3 4 5; do if $UPDATE >/dev/null 2>&1; then ok=1; break; fi
echo -e "${YELLOW}Обновление пакетов попытка $i не удалась${NC}"; sleep 1; done; if [ "$ok" -ne 1 ]; then echo -e "\n${RED}Не удалось обновить пакеты после 5 попыток${NC}"; PAUSE; exit 0; fi
ok=0; echo -e "${CYAN}Устанавливаем ${NC}curl"; for i in 1 2 3 4 5; do if $PKG_INSTALL curl >/dev/null 2>&1; then ok=1; break; fi; echo -e "${YELLOW}Устанавливаем ${NC}curl${YELLOW} попытка ${NC}$i${YELLOW} не удалась!${NC}"; sleep 1; done
if [ "$ok" -ne 1 ]; then echo -e "\n${RED}Не удалось установить ${NC}curl${RED} после 5 попыток${NC}"; PAUSE; exit 0; fi; if ! command -v curl >/dev/null 2>&1; then echo -e "\ncurl${RED} не найден после установки${NC}"; PAUSE; exit 0; fi; fi



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

# Получение имени удаленного файла для APK
get_apk_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем основной пакет
    grep -o "${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени luci-файла для APK
get_apk_luci_file() {
    local pkg_name="$1"
    
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    # Ищем luci пакет для APK
    grep -o "luci-app-${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
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

# Получение версии установленного luci
get_luci_version() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        opkg list-installed 2>/dev/null | grep "luci-app-$pkg_name" | awk '{print $3}'
    else
        apk list --installed 2>/dev/null | grep "luci-app-$pkg_name" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
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
        
        # Для opkg luci версия обычно такая же как у основного пакета
        luci_remote_ver="$remote_ver"
    else
        local main_file="$(get_apk_file "$pkg_name")"
        local luci_file="$(get_apk_luci_file "$pkg_name")"
        
        if [ -n "$main_file" ]; then
            remote_ver="$(get_apk_version "$main_file")"
        else
            remote_ver=""
        fi
        
        if [ -n "$luci_file" ]; then
            luci_remote_ver="$(get_apk_version "$luci_file")"
        else
            luci_remote_ver=""
        fi
    fi
    
    local local_ver="$(get_local_version "$pkg_name")"
    local luci_local_ver="$(get_luci_version "$pkg_name")"
    
    # Сохраняем имена файлов в глобальные переменные для установки
    MAIN_FILE="$main_file"
    LUCI_FILE="$luci_file"
    
    # Отладка
    echo "DEBUG: $pkg_name -> MAIN='$main_file', LUCI='$luci_file', REMOTE='$remote_ver', LOCAL='$local_ver', LUCI_LOCAL='$luci_local_ver'" >&2
    
    if [ -z "$local_ver" ] && [ -n "$remote_ver" ]; then
        echo "install|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    elif [ -n "$local_ver" ] && [ -n "$remote_ver" ] && [ "$local_ver" != "$remote_ver" ]; then
        echo "update|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    elif [ -n "$local_ver" ]; then
        echo "remove|$local_ver|$remote_ver|$luci_local_ver|$luci_remote_ver"
    else
        echo "error||||"
    fi
}

### =======================================================================
### УСТАНОВКА И УДАЛЕНИЕ
### =======================================================================

install_package() {
    local pkg_name="$1"
    
    log "=== Установка/обновление $pkg_name ==="
    
    # Получаем состояние (это заполнит MAIN_FILE и LUCI_FILE)
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
    
    # Скачиваем luci если есть
    if [ -n "$LUCI_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_FILE}"
        log "Скачивание: $LUCI_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_FILE"
    fi
    
    # Установка
    log "Установка пакетов..."
    local packages_to_install=$(ls "$TMP_DIR"/*.$PKG_EXT 2>/dev/null)
    
    if [ -n "$packages_to_install" ]; then
        $PKG_INSTALL $packages_to_install
        if [ $? -eq 0 ]; then
            log "✓ Установка/обновление завершено"
            
            # Перезапускаем веб-интерфейс если установлен luci
            if [ -n "$LUCI_FILE" ]; then
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
    
    # Удаляем luci если он установлен
    if is_luci_installed "$pkg_name"; then
        log "Удаление luci-app-$pkg_name..."
        $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
    fi
    
    # Удаляем основной пакет
    log "Удаление $pkg_name..."
    $PKG_REMOVE "$pkg_name" 2>/dev/null
    
    log "✓ Удаление завершено"
    
    # Перезапускаем веб-интерфейс
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/rpcd restart 2>/dev/null
}

### =======================================================================
### ФУНКЦИИ ДЛЯ AWG
### =======================================================================

check_awg_installed() {
    if opkg list-installed 2>/dev/null | grep -q "kmod-amneziawg" && \
       opkg list-installed 2>/dev/null | grep -q "amneziawg-tools"; then
        return 0
    fi
    return 1
}

get_awg_state() {
    if check_awg_installed; then
        echo "remove|Установлен → Удалить"
    else
        echo "install|Не установлен → Установить"
    fi
}

install_awg() {
    log "=== Установка AmneziaWG ==="
    
    # Определяем архитектуру и версию
    ARCH_AWG="$(uname -m)_cortex-a53_$(cat /etc/openwrt_release | grep DISTRIB_TARGET | cut -d'=' -f2 | tr -d "'" | tr '/' '_')"
    OWRT="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)"
    
    log "Архитектура: $ARCH_AWG"
    log "Версия OpenWrt: $OWRT"
    
    # Список пакетов для скачивания
    AWG_PACKAGES="kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru"
    
    # Скачиваем каждый пакет
    for pkg in $AWG_PACKAGES; do
        PKG_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v$OWRT/${pkg}_v${OWRT}_${ARCH_AWG}.${PKG_EXT}"
        log "Скачивание: ${pkg}_v${OWRT}_${ARCH_AWG}.${PKG_EXT}"
        download_file "$PKG_URL" "$TMP_DIR/${pkg}_v${OWRT}_${ARCH_AWG}.${PKG_EXT}"
        
        if [ ! -f "$TMP_DIR/${pkg}_v${OWRT}_${ARCH_AWG}.${PKG_EXT}" ]; then
            log "ОШИБКА: Не удалось скачать $pkg"
            return 1
        fi
    done
    
    # Установка
    log "Установка пакетов AWG..."
    local packages_to_install=$(ls "$TMP_DIR"/*${ARCH_AWG}.${PKG_EXT} 2>/dev/null)
    
    if [ -n "$packages_to_install" ]; then
        $PKG_INSTALL $packages_to_install --force-depends 2>/dev/null || \
        $PKG_INSTALL $packages_to_install
        
        if [ $? -eq 0 ]; then
            log "✓ Установка AWG завершена"
            
            # Перезапускаем веб-интерфейс
            log "Перезапуск веб-интерфейса..."
            /etc/init.d/uhttpd restart 2>/dev/null
            /etc/init.d/rpcd restart 2>/dev/null
        else
            log "✗ Ошибка при установке AWG"
            return 1
        fi
    fi
    
    # Очистка
    rm -f "$TMP_DIR"/*${ARCH_AWG}.${PKG_EXT}
}

remove_awg() {
    log "=== Удаление AmneziaWG ==="
    
    # Удаляем пакеты в правильном порядке
    $PKG_REMOVE luci-i18n-amneziawg-ru 2>/dev/null
    $PKG_REMOVE luci-proto-amneziawg 2>/dev/null
    $PKG_REMOVE amneziawg-tools 2>/dev/null
    $PKG_REMOVE kmod-amneziawg 2>/dev/null
    
    log "✓ Удаление AWG завершено"
    
    # Перезапускаем веб-интерфейс
    /etc/init.d/uhttpd restart 2>/dev/null
    /etc/init.d/rpcd restart 2>/dev/null
}

run_awg_action() {
    if check_awg_installed; then
        remove_awg
    else
        install_awg
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
    local luci_local_ver="$(echo "$state_data" | cut -d'|' -f4)"
    local luci_remote_ver="$(echo "$state_data" | cut -d'|' -f5)"
    
    case "$action" in
        install) 
            if [ -n "$luci_remote_ver" ]; then
                echo "$pkg_name (осн:не уст / $remote_ver, luci:$luci_remote_ver) → Установить"
            else
                echo "$pkg_name (не установлен / $remote_ver) → Установить"
            fi
            ;;
        update)
            if [ -n "$luci_remote_ver" ]; then
                echo "$pkg_name (осн:$local_ver → $remote_ver, luci:$luci_local_ver → $luci_remote_ver) → Обновить"
            else
                echo "$pkg_name ($local_ver → $remote_ver) → Обновить"
            fi
            ;;
        remove)
            if [ -n "$luci_local_ver" ]; then
                echo "$pkg_name (осн:$local_ver, luci:$luci_local_ver) → Удалить"
            else
                echo "$pkg_name ($local_ver) → Удалить"
            fi
            ;;
        *)       echo "$pkg_name → Недоступно" ;;
    esac
}

get_awg_menu_label() {
    local state_data="$(get_awg_state)"
    local action="$(echo "$state_data" | cut -d'|' -f1)"
    local label="$(echo "$state_data" | cut -d'|' -f2)"
    
    case "$action" in
        install) echo "AmneziaWG (Не установлен) → Установить" ;;
        remove)  echo "AmneziaWG (Установлен) → Удалить" ;;
        *)       echo "AmneziaWG → Недоступно" ;;
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
        echo "  1) $(get_menu_label zapret2)"
        echo "  2) $(get_menu_label zeroblock)"
        echo "  3) $(get_awg_menu_label)"
        echo "  Enter) Выход"
        echo "======================================"
        
        printf "  Выбор: "
        read -r user_choice
        
        case "$user_choice" in
            1) run_action zapret2; PAUSE ;;
            2) run_action zeroblock; PAUSE ;;
            3) run_awg_action; PAUSE ;;
            *) exit 0 ;;
        esac
    done
}

# Запуск
menu
