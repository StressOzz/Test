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
    PKG_REMOVE="opkg --force-removal-of-dependent-packages --autoremove remove"
    PKG_TYPE="opkg"
    UPDATE="opkg update"
    ARCH_SUFFIX="aarch64_cortex-a53"
    CHECK_INSTALLED() { opkg list-installed 2>/dev/null | grep -q "^$1 -"; }
else
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX=""
    ="apk "
    CHECK_INSTALLED() { apk list --installed 2>/dev/null | grep -q "^$1"; }
fi

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }


TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Функция для скачивания (с поддержкой редиректов)
download_file() {
    local url="$1"
    local output="$2"
    curl -L -s --connect-timeout 10 "$url" -o "$output"
}

# Обновление кэша
update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
}

log() { echo -e "${YELLOW}[*]${NC} $1"; }

UPDATE_PACK() { log "${CYAN}Обновляем список пакетов${NC}"
for i in 1 2 3; do if $UPDATE >/dev/null 2>&1; then ok=1; break; fi
log "${YELLOW}Обновление пакетов попытка $i не удалась${NC}"; done; }

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
    
    # Очищаем временную директорию перед установкой
    rm -f "$TMP_DIR"/*.${PKG_EXT}

    echo
    
    log "${MAGENTA}=== Установка $pkg_name ===${NC}"

    UPDATE_PACK

    # Получаем состояние (это заполнит MAIN_FILE и LUCI_FILE)
    get_package_state "$pkg_name" > /dev/null
    
    if [ -z "$MAIN_FILE" ]; then
        log "${RED}ОШИБКА: Не найден пакет${NC} $pkg_name"
        return 1
    fi
    
    # Скачиваем основной пакет
    local main_url="${BASE_URL}${MAIN_FILE}"
    log "${CYAN}Скачивание:${NC} $MAIN_FILE"
    download_file "$main_url" "$TMP_DIR/$MAIN_FILE"
    
    if [ ! -f "$TMP_DIR/$MAIN_FILE" ]; then
        log "${RED}ОШИБКА: Не удалось скачать $MAIN_FILE${NC}"
        return 1
    fi
    
    # Скачиваем luci если есть
    if [ -n "$LUCI_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_FILE}"
        log "${CYAN}Скачивание:${NC} $LUCI_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_FILE"
    fi
    
    # Установка
    log "${CYAN}Установка пакетов...${NC}"
    local packages_to_install=$(ls "$TMP_DIR"/*.$PKG_EXT 2>/dev/null)
    
    if [ -n "$packages_to_install" ]; then
        $PKG_INSTALL $packages_to_install
		$PKG_INSTALL sing-box
        sleep 2
        if [ $? -eq 0 ]; then
            # Перезапускаем веб-интерфейс если установлен luci
            if [ -n "$LUCI_FILE" ]; then
                log "${GREEN}✓ Установка завершена${NC}"
            fi
        else
            log "${RED}✗ Ошибка при установке${NC}"
        fi
    fi
    
    # Очистка
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

remove_zapret2() {

    echo
    
    log "${MAGENTA}=== Удаление zapret2 ===${NC}"

    # Удаляем основной пакет
    log "${CYAN}Удаление zapret2...${NC}"
    $PKG_REMOVE "zapret2" 2>/dev/null
    
    # Удаляем luci если он установлен
    if is_luci_installed "zapret2"; then
        log "${CYAN}Удаление luci-app-zapret2...${NC}"
        $PKG_REMOVE "luci-app-zapret2" 2>/dev/null
    fi
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    log "${GREEN}✓ Удаление zapret2 завершено${NC}"
}





run_action zapret2
wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt
sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2 >/dev/null 2>&1
/etc/init.d/zapret2 restart >/dev/null 2>&1 
PAUSE 
