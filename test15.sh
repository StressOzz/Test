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
    ARCH_SUFFIX="aarch64_cortex-a53"
    CHECK_INSTALLED() { opkg list-installed 2>/dev/null | grep -q "^$1 -"; }
else
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX=""
    UPDATE="apk update"
    CHECK_INSTALLED() { apk list --installed 2>/dev/null | grep -q "^$1"; }
fi

PAUSE() { echo -ne "\nНажмите Enter..."; read dummy; }

if ! command -v curl >/dev/null 2>&1; then clear; echo -e "${MAGENTA}Устанавливаем ${NC}curl"; echo -e "${CYAN}Обновляем список пакетов${NC}"; ok=0; for i in 1 2 3 4 5; do if $UPDATE >/dev/null 2>&1; then ok=1; break; fi
echo -e "${YELLOW}Обновление пакетов попытка $i не удалась${NC}"; sleep 1; done; if [ "$ok" -ne 1 ]; then echo -e "\n${RED}Не удалось обновить пакеты после 5 попыток${NC}"; PAUSE; exit 0; fi
ok=0; echo -e "${CYAN}Устанавливаем ${NC}curl"; for i in 1 2 3 4 5; do if $PKG_INSTALL curl >/dev/null 2>&1; then ok=1; break; fi; echo -e "${YELLOW}Устанавливаем ${NC}curl${YELLOW} попытка ${NC}$i${YELLOW} не удалась!${NC}"; sleep 1; done
if [ "$ok" -ne 1 ]; then echo -e "\n${RED}Не удалось установить ${NC}curl${RED} после 5 попыток${NC}"; PAUSE; exit 0; fi; if ! command -v curl >/dev/null 2>&1; then echo -e "\ncurl${RED} не найден после установки${NC}"; PAUSE; exit 0; fi; fi

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
    
    log "${MAGENTA}=== Установка $pkg_name ===${NC}"
    
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

remove_package() {
    local pkg_name="$1"
    
    log "${MAGENTA}=== Удаление $pkg_name ===${NC}"
    
    # Удаляем luci если он установлен
    if is_luci_installed "$pkg_name"; then
        log "${CYAN}Удаление luci-app-$pkg_name...${NC}"
        $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
    fi
    
    # Удаляем основной пакет
    log "${CYAN}Удаление $pkg_name...${NC}"
    $PKG_REMOVE "$pkg_name" 2>/dev/null
    log "${GREEN}✓ Удаление завершено${NC}"
}

### =======================================================================
### ФУНКЦИИ ДЛЯ AWG
### =======================================================================

# Определение архитектуры через get_pkgarch (как в оригинальном скрипте)
get_pkgarch() {
    # Пытаемся получить через ubus
    PKGARCH_UBUS=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.arch' 2>/dev/null)
    if [ -n "$PKGARCH_UBUS" ]; then
        echo "$PKGARCH_UBUS"
        return
    fi
    
    # Если ubus не доступен, пробуем opkg
    if command -v opkg >/dev/null 2>&1; then
        opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}'
        return
    fi
    
    # Fallback на /etc/openwrt_release
    if [ -f /etc/openwrt_release ]; then
        PKGARCH_RELEASE=$(grep "^DISTRIB_ARCH='" /etc/openwrt_release | cut -d"'" -f2)
        if [ -n "$PKGARCH_RELEASE" ]; then
            echo "$PKGARCH_RELEASE"
            return
        fi
    fi
    
    # Последний шанс - apk или uname
    if command -v apk >/dev/null 2>&1; then
        apk --print-arch
    else
        uname -m
    fi
}

# Получаем параметры для AWG
PKGARCH=$(get_pkgarch)
TARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' | cut -d '/' -f 1)
SUBTARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' | cut -d '/' -f 2)
VERSION=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.version')

# Если ubus не работает, берем из файла
if [ -z "$TARGET" ] && [ -f /etc/openwrt_release ]; then
    TARGET=$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | cut -d '/' -f 1)
    SUBTARGET=$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | cut -d '/' -f 2)
    VERSION=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2)
fi

# Формируем постфикс для имени файла
PKGPOSTFIX_BASE="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}"
AWG_BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/v${VERSION}/"

AWG_PKGS="kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru"

is_awg_installed() {
    for p in $AWG_PKGS; do
        CHECK_INSTALLED "$p" || return 1
    done
    return 0
}

install_awg() {
    local temp_dir="/tmp/amneziawg"
    mkdir -p "$temp_dir"
    
    log "${MAGENTA}=== Установка AmneziaWG ===${NC}"
    log "${CYAN}Архитектура:${NC} $PKGARCH"
    log "${CYAN}Таргет:${NC} $TARGET/$SUBTARGET"
    log "${CYAN}Версия:${NC} $VERSION"
    
    for pkg in $AWG_PKGS; do
        if CHECK_INSTALLED "$pkg"; then
            log "${GREEN}✓ $pkg уже установлен${NC}"
            continue
        fi
        
        local filename="${pkg}${PKGPOSTFIX_BASE}.${PKG_EXT}"
        local url="${AWG_BASE_URL}${filename}"
        
        log "${CYAN}Скачивание:${NC} $filename"
        if curl -fsL -o "$temp_dir/$filename" "$url"; then
            log "${CYAN}Установка:${NC} $pkg"
            if $PKG_INSTALL "$temp_dir/$filename" 2>/dev/null; then
                log "${GREEN}✓ $pkg установлен${NC}"
            else
                log "${RED}✗ Ошибка установки $pkg${NC}"
                rm -rf "$temp_dir"
                return 1
            fi
        else
            log "${RED}✗ Не удалось скачать $pkg${NC}"
            rm -rf "$temp_dir"
            return 1
        fi
    done
    
    rm -rf "$temp_dir"
    log "${CYAN}Перезапускаем сеть! Подождите...${NC}"
    /etc/init.d/network restart 2>/dev/null
    log "${GREEN}✓ Установка AWG завершена${NC}"
}

remove_awg() {
    log "${MAGENTA}=== Удаление AmneziaWG ===${NC}"
    
    log "${CYAN}Удаление:${NC} luci-i18n-amneziawg-ru"
    $PKG_REMOVE luci-i18n-amneziawg-ru 2>/dev/null
    
    log "${CYAN}Удаление:${NC} luci-proto-amneziawg"
    $PKG_REMOVE luci-proto-amneziawg 2>/dev/null
    
    log "${CYAN}Удаление:${NC} amneziawg-tools"
    $PKG_REMOVE amneziawg-tools 2>/dev/null
    
    log "${CYAN}Удаление:${NC} kmod-amneziawg"
    $PKG_REMOVE kmod-amneziawg 2>/dev/null
    
    log "${CYAN}Перезапускаем сеть! Подождите...${NC}"
    /etc/init.d/network restart 2>/dev/null
    log "${GREEN}✓ Удаление AWG завершено${NC}"
}

run_awg_action() {
    if is_awg_installed; then
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
            echo -e "${GREEN}Установить${NC} $pkg_name"
            ;;
        update)
            echo -e "${GREEN}Обновить${NC} $pkg_name"
            ;;
        remove)
            echo -e "${GREEN}Удалить${NC} $pkg_name"
            ;;
        *)       echo "$pkg_name → Недоступно" ;;
    esac
}

get_awg_menu_label() {
    if is_awg_installed; then
        echo -e "${GREEN}Удалить${NC} AmneziaWG"
    else
        echo -e "${GREEN}Установить${NC} AmneziaWG"
    fi
}

run_action() {
    local pkg_name="$1"
    local action="$(get_package_state "$pkg_name" | cut -d'|' -f1)"
    
    case "$action" in
        install|update) install_package "$pkg_name" ;;
        remove)         remove_package "$pkg_name" ;;
        *)              log "${RED}Ошибка: пакет $pkg_name недоступен${NC}" ;;
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
        echo "       Routerich Package Manager       "
        echo "======================================"
        echo -e "${CYAN}1)${NC} $(get_menu_label zapret2)"
        echo -e "${CYAN}2)${NC} $(get_menu_label zeroblock)"
        echo -e "${CYAN}3)${NC} $(get_awg_menu_label)"
        echo -e "${CYAN}Enter) ${GREEN}Выход${NC}"
        echo "======================================"
        
        echo -en "${YELLOW}Выберите пункт:${NC} "
        read -r user_choice
        
        case "$user_choice" in
            1) run_action zapret2; sleep 2; PAUSE ;;
            2) run_action zeroblock; sleep 2; PAUSE ;;
            3) run_awg_action; sleep 2; PAUSE ;;
            *) exit 0 ;;
        esac
    done
}

# Запуск
menu
