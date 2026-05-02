#!/bin/sh

### =======================================================================
### ЦВЕТА ДЛЯ ВЫВОДА
### =======================================================================

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
BLUE="\033[0;34m"
DGRAY="\033[38;5;244m"

### =======================================================================
### АВТООПРЕДЕЛЕНИЕ ТИПА ПАКЕТНОГО МЕНЕДЖЕРА
### =======================================================================

if command -v opkg >/dev/null 2>&1; then
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg remove --force-depends"
    PKG_TYPE="opkg"
    ARCH_SUFFIX="aarch64_cortex-a53"
    PKG_IS_APK=0
else
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_TYPE="apk"
    ARCH_SUFFIX=""
    PKG_IS_APK=1
fi

### =======================================================================
### ОБЩИЕ НАСТРОЙКИ
### =======================================================================

TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Функция для скачивания
download_file() {
    local url="$1"
    local output="$2"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s --connect-timeout 20 --max-time 60 "$url" -o "$output"
        return $?
    elif command -v wget >/dev/null 2>&1; then
        wget -q --timeout=20 -O "$output" "$url" 2>/dev/null
        return $?
    fi
    return 1
}

# Обновление кэша
update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
}

log() { echo -e "[*] $1"; }
pause() { echo -ne "\n${CYAN}Нажмите Enter...${NC}"; read dummy; }

### =======================================================================
### ФУНКЦИИ ДЛЯ РАБОТЫ С ПАКЕТАМИ (ZAPRET2, ZEROBLOCK)
### =======================================================================

# Получение имени удаленного файла пакета для OPKG
get_opkg_file() {
    local pkg_name="$1"
    [ ! -f "$CACHE_FILE" ] && update_cache
    grep -o "${pkg_name}_[0-9][^\"]*_${ARCH_SUFFIX}\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени luci-файла для OPKG
get_opkg_luci_file() {
    local pkg_name="$1"
    [ ! -f "$CACHE_FILE" ] && update_cache
    grep -o "luci-app-${pkg_name}_[0-9][^\"]*_all\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Получение имени удаленного файла для APK
get_apk_file() {
    local pkg_name="$1"
    [ ! -f "$CACHE_FILE" ] && update_cache
    grep -o "${pkg_name}-[0-9][^\"]*\.${PKG_EXT}" "$CACHE_FILE" | head -n1
}

# Извлечение версии
get_version_from_filename() {
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

# Определение состояния пакета
MAIN_FILE=""
LUCI_FILE=""

get_package_state() {
    local pkg_name="$1"
    
    if [ "$PKG_TYPE" = "opkg" ]; then
        MAIN_FILE="$(get_opkg_file "$pkg_name")"
        LUCI_FILE="$(get_opkg_luci_file "$pkg_name")"
        remote_ver="$(get_version_from_filename "$MAIN_FILE")"
    else
        MAIN_FILE="$(get_apk_file "$pkg_name")"
        LUCI_FILE=""
        remote_ver="$(get_version_from_filename "$MAIN_FILE")"
    fi
    
    local local_ver="$(get_local_version "$pkg_name")"
    
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

# Установка пакета
install_package() {
    local pkg_name="$1"
    
    echo -e "\n${MAGENTA}=== Установка/обновление $pkg_name ===${NC}"
    
    get_package_state "$pkg_name" > /dev/null
    
    if [ -z "$MAIN_FILE" ]; then
        echo -e "${RED}ОШИБКА: Не найден пакет $pkg_name${NC}"
        return 1
    fi
    
    # Скачиваем основной пакет
    local main_url="${BASE_URL}${MAIN_FILE}"
    echo -e "${CYAN}Скачивание:${NC} $MAIN_FILE"
    download_file "$main_url" "$TMP_DIR/$MAIN_FILE"
    
    if [ ! -f "$TMP_DIR/$MAIN_FILE" ]; then
        echo -e "${RED}ОШИБКА: Не удалось скачать $MAIN_FILE${NC}"
        return 1
    fi
    
    # Скачиваем luci если есть
    if [ -n "$LUCI_FILE" ]; then
        local luci_url="${BASE_URL}${LUCI_FILE}"
        echo -e "${CYAN}Скачивание:${NC} $LUCI_FILE"
        download_file "$luci_url" "$TMP_DIR/$LUCI_FILE"
    fi
    
    # Установка
    echo -e "${CYAN}Установка пакетов...${NC}"
    if ls "$TMP_DIR"/*.$PKG_EXT >/dev/null 2>&1; then
        $PKG_INSTALL $TMP_DIR/*.$PKG_EXT
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✓ $pkg_name установлен/обновлен${NC}"
        else
            echo -e "${RED}✗ Ошибка при установке${NC}"
        fi
    fi
    
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

# Удаление пакета
remove_package() {
    local pkg_name="$1"
    
    echo -e "\n${MAGENTA}=== Удаление $pkg_name ===${NC}"
    $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
    $PKG_REMOVE "$pkg_name" 2>/dev/null
    echo -e "${GREEN}✓ $pkg_name удален${NC}"
}

### =======================================================================
### ФУНКЦИИ ДЛЯ AWG
### =======================================================================

AWG_BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
AWG_IF_NAME="AWG"
AWG_PROTO="amneziawg"
AWG_DEV_NAME="amneziawg0"

# Получение информации о системе
get_system_info() {
    VERSION=$(ubus call system board | jsonfilter -e '@.release.version' 2>/dev/null | tr -d '\n')
    MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f1)
    TARGET=$(ubus call system board | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f1)
    SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f2)
    
    if [ -z "$VERSION" ]; then
        echo -e "${RED}Не удалось определить версию OpenWrt!${NC}"
        return 1
    fi
    
    # Определяем архитектуру для AWG
    if [ "$PKG_IS_APK" -eq 1 ]; then
        AWG_PKGARCH=$(cat /etc/apk/arch 2>/dev/null)
        AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.apk"
        AWG_INSTALL_CMD="apk add --allow-untrusted"
    else
        opkg update >/dev/null 2>&1
        AWG_PKGARCH=$(opkg print-architecture 2>/dev/null | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
        AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
        AWG_INSTALL_CMD="opkg install"
    fi
    
    return 0
}

# Установка одного пакета AWG
install_awg_pkg() {
    local pkgname=$1
    local filename="${pkgname}${AWG_POSTFIX}"
    local url="${AWG_BASE_URL}v${VERSION}/${filename}"
    
    echo -e "${CYAN}Скачиваем:${NC} $filename"
    
    if download_file "$url" "$TMP_DIR/$filename"; then
        echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
        if ! $AWG_INSTALL_CMD "$TMP_DIR/$filename" >/dev/null 2>&1; then
            echo -e "${RED}Ошибка установки $pkgname!${NC}"
            return 1
        fi
    else
        echo -e "${RED}Ошибка! Не удалось скачать $filename${NC}"
        return 1
    fi
    return 0
}

# Установка AWG
install_awg() {
    echo -e "\n${MAGENTA}=== Установка AWG и интерфейса ===${NC}"
    
    get_system_info || { pause; return; }
    
    # Устанавливаем пакеты
    for pkg in kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru; do
        install_awg_pkg "$pkg" || { pause; return; }
    done
    
    # Создаем интерфейс
    echo -e "${CYAN}Создаем интерфейс AWG${NC}"
    
    if uci show network.$AWG_IF_NAME >/dev/null 2>&1; then
        echo -e "${YELLOW}Интерфейс уже существует!${NC}"
    else
        uci set network.$AWG_IF_NAME=interface
        uci set network.$AWG_IF_NAME.proto=$AWG_PROTO
        uci set network.$AWG_IF_NAME.device=$AWG_DEV_NAME
        uci commit network
        echo -e "${GREEN}Интерфейс создан${NC}"
    fi
    
    echo -e "${YELLOW}Перезапускаем сеть...${NC}"
    /etc/init.d/network restart >/dev/null 2>&1
    
    echo -e "\n${GREEN}✓ AWG и интерфейс успешно установлены!${NC}"
    echo -e "${YELLOW}Далее в LuCI:${NC}"
    echo -e "  Network ${GREEN}→${NC} Interfaces ${GREEN}→${NC} AWG ${GREEN}→${NC} Edit"
    echo -e "  ${GREEN}→${NC} Load configuration… (загрузите конфиг)"
    pause
}

# Удаление AWG
remove_awg() {
    echo -e "\n${MAGENTA}=== Удаление AWG и интерфейса ===${NC}"
    
    echo -e "${CYAN}Удаляем пакеты AWG${NC}"
    for pkg in luci-i18n-amneziawg-ru luci-proto-amneziawg amneziawg-tools kmod-amneziawg; do
        $PKG_REMOVE "$pkg" 2>/dev/null
    done
    
    echo -e "${CYAN}Удаляем интерфейс${NC}"
    uci delete network.$AWG_IF_NAME 2>/dev/null
    uci commit network 2>/dev/null
    
    # Удаляем пиров
    for peer in $(uci show network 2>/dev/null | grep "interface='$AWG_IF_NAME'" | cut -d. -f2); do
        uci delete network.$peer 2>/dev/null
    done
    uci commit network 2>/dev/null
    
    echo -e "${YELLOW}Перезапускаем сеть...${NC}"
    /etc/init.d/network restart >/dev/null 2>&1
    
    echo -e "${GREEN}✓ AWG удален${NC}"
    pause
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
        install) echo "$pkg_name (нет / $remote_ver) → Установить" ;;
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
        *)              echo -e "${RED}Ошибка: пакет $pkg_name недоступен${NC}" ;;
    esac
}

### =======================================================================
### ГЛАВНОЕ МЕНЮ
### =======================================================================

menu() {
    while true; do
        clear
        update_cache >/dev/null 2>&1
        echo -e "${MAGENTA}======================================${NC}"
        echo -e "${MAGENTA}       RouterICH Package Manager       ${NC}"
        echo -e "${MAGENTA}======================================${NC}"
        echo -e "  ${CYAN}Пакетный менеджер:${NC} $PKG_TYPE"
        [ "$PKG_TYPE" = "opkg" ] && echo -e "  ${CYAN}Архитектура:${NC} $ARCH_SUFFIX"
        echo -e "${MAGENTA}======================================${NC}"
        echo -e "  ${GREEN}1)${NC} $(get_menu_label zapret2)"
        echo -e "  ${GREEN}2)${NC} $(get_menu_label zeroblock)"
        echo -e "  ${GREEN}3)${NC} AWG (AmneziaWG) → Установить/Удалить"
        echo -e "  ${RED}0)${NC} Выход"
        echo -e "${MAGENTA}======================================${NC}"
        
        printf "  ${CYAN}Выбор:${NC} "
        read -r user_choice
        
        case "$user_choice" in
            1) run_action zapret2; pause ;;
            2) run_action zeroblock; pause ;;
            3) awg_submenu ;;
            0) echo -e "${GREEN}До свидания!${NC}"; exit 0 ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

### =======================================================================
### ПОДМЕНЮ AWG
### =======================================================================

awg_submenu() {
    while true; do
        clear
        echo -e "${MAGENTA}======================================${NC}"
        echo -e "${MAGENTA}            AWG (AmneziaWG)           ${NC}"
        echo -e "${MAGENTA}======================================${NC}"
        echo -e "  ${GREEN}1)${NC} Установить AWG + интерфейс"
        echo -e "  ${RED}2)${NC} Удалить AWG + интерфейс"
        echo -e "  ${CYAN}0)${NC} Назад"
        echo -e "${MAGENTA}======================================${NC}"
        
        printf "  ${CYAN}Выбор:${NC} "
        read -r user_choice
        
        case "$user_choice" in
            1) install_awg; break ;;
            2) remove_awg; break ;;
            0) break ;;
            *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
        esac
    done
}

### =======================================================================
### ЗАПУСК
### =======================================================================

# Проверяем наличие jsonfilter для AWG
if ! command -v jsonfilter >/dev/null 2>&1; then
    echo -e "${YELLOW}Устанавливаем jsonfilter...${NC}"
    opkg update >/dev/null 2>&1
    opkg install jsonfilter >/dev/null 2>&1
fi

menu
