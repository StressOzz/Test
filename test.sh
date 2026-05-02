#!/bin/sh

### =======================================================================
### ЦВЕТА
### =======================================================================

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

### =======================================================================
### ОПРЕДЕЛЕНИЕ СИСТЕМЫ И ПАКЕТНОГО МЕНЕДЖЕРА
### =======================================================================

# Определяем тип пакетного менеджера и устанавливаем все переменные
if command -v opkg >/dev/null 2>&1; then
    # OpenWrt 23.05 и старше (opkg)
    PKG_TYPE="opkg"
    PKG_EXT="ipk"
    PKG_INSTALL="opkg install"
    PKG_REMOVE="opkg remove --force-depends"
    PKG_IS_APK=0
    
    # Для RouterICH пакетов
    BASE_URL="https://packages.routerich.ru/24.10/mediatek/filogic/routerich/"
    ARCH_SUFFIX="aarch64_cortex-a53"
    
    # Формат имен файлов для RouterICH
    PKG_FILE_PATTERN="${pkg_name}_[0-9][^\"]*_${ARCH_SUFFIX}\\.${PKG_EXT}"
    LUCI_FILE_PATTERN="luci-app-${pkg_name}_[0-9][^\"]*_all\\.${PKG_EXT}"
    
    # Функция получения версии установленного пакета
    GET_LOCAL_VERSION() {
        opkg list-installed 2>/dev/null | grep "^$1 -" | awk '{print $3}'
    }
    
    # Функция проверки установлен ли пакет
    IS_PKG_INSTALLED() {
        opkg list-installed 2>/dev/null | grep -q "^$1"
    }
    
    # Для AWG
    opkg update >/dev/null 2>&1
    AWG_PKGARCH=$(opkg print-architecture 2>/dev/null | awk 'BEGIN {max=0} {if ($3 > max) {max=$3; arch=$2}} END {print arch}')
    AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
    AWG_INSTALL_CMD="opkg install"
    
else
    # OpenWrt 24.10+ (apk)
    PKG_TYPE="apk"
    PKG_EXT="apk"
    PKG_INSTALL="apk add --allow-untrusted"
    PKG_REMOVE="apk del"
    PKG_IS_APK=1
    
    # Для RouterICH пакетов
    BASE_URL="https://packages.routerich.ru/25.12/mediatek/filogic/routerich/"
    ARCH_SUFFIX=""
    
    # Формат имен файлов для RouterICH
    PKG_FILE_PATTERN="${pkg_name}-[0-9][^\"]*\\.${PKG_EXT}"
    LUCI_FILE_PATTERN="luci-app-${pkg_name}-[0-9][^\"]*\\.${PKG_EXT}"
    
    # Функция получения версии установленного пакета
    GET_LOCAL_VERSION() {
        apk list --installed 2>/dev/null | grep "^$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+' | head -n1
    }
    
    # Функция проверки установлен ли пакет
    IS_PKG_INSTALLED() {
        apk list --installed 2>/dev/null | grep -q "^$1"
    }
    
    # Для AWG
    AWG_PKGARCH=$(cat /etc/apk/arch 2>/dev/null)
    AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.apk"
    AWG_INSTALL_CMD="apk add --allow-untrusted"
fi

# Общие настройки
TMP_DIR="/tmp/routerich"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/index.html"

# Определяем версию OpenWrt для AWG
VERSION=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.version' 2>/dev/null | tr -d '\n')
TARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f1)
SUBTARGET=$(ubus call system board 2>/dev/null | jsonfilter -e '@.release.target' 2>/dev/null | cut -d '/' -f2)

# Настройки AWG
AWG_BASE_URL="https://github.com/Slava-Shchipunov/awg-openwrt/releases/download/"
AWG_IF_NAME="AWG"
AWG_PROTO="amneziawg"
AWG_DEV_NAME="amneziawg0"

# Обновляем POSTFIX для AWG с актуальной версией
if [ "$PKG_IS_APK" -eq 1 ]; then
    AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.apk"
else
    AWG_POSTFIX="_v${VERSION}_${AWG_PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
fi

### =======================================================================
### ОБЩИЕ ФУНКЦИИ
### =======================================================================

download_file() {
    curl -s --connect-timeout 20 "$1" -o "$2" 2>/dev/null || \
    wget -q --timeout=20 "$1" -O "$2" 2>/dev/null
}

update_cache() {
    download_file "$BASE_URL" "$CACHE_FILE"
}

pause() {
    echo -ne "\n${CYAN}Нажмите Enter...${NC}"
    read dummy
}

### =======================================================================
### ФУНКЦИИ ДЛЯ ROUTERICH ПАКЕТОВ (zapret2, zeroblock)
### =======================================================================

get_remote_file() {
    local pkg_name="$1"
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    local pattern=$(echo "$PKG_FILE_PATTERN" | sed "s/\${pkg_name}/$pkg_name/g")
    grep -o "$pattern" "$CACHE_FILE" | head -n1
}

get_luci_file() {
    local pkg_name="$1"
    [ ! -f "$CACHE_FILE" ] && update_cache
    
    local pattern=$(echo "$LUCI_FILE_PATTERN" | sed "s/\${pkg_name}/$pkg_name/g")
    grep -o "$pattern" "$CACHE_FILE" | head -n1
}

get_version_from_filename() {
    echo "$1" | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)*-r[0-9]+'
}

install_routerich_pkg() {
    local pkg_name="$1"
    
    echo -e "\n${MAGENTA}=== Установка/обновление $pkg_name ===${NC}"
    
    local main_file="$(get_remote_file "$pkg_name")"
    local luci_file="$(get_luci_file "$pkg_name")"
    
    if [ -z "$main_file" ]; then
        echo -e "${RED}ОШИБКА: Не найден пакет $pkg_name${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Скачивание:${NC} $main_file"
    download_file "${BASE_URL}${main_file}" "$TMP_DIR/$main_file"
    
    if [ -n "$luci_file" ]; then
        echo -e "${CYAN}Скачивание:${NC} $luci_file"
        download_file "${BASE_URL}${luci_file}" "$TMP_DIR/$luci_file"
    fi
    
    echo -e "${CYAN}Установка...${NC}"
    $PKG_INSTALL $TMP_DIR/*.$PKG_EXT 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ $pkg_name установлен/обновлен${NC}"
    else
        echo -e "${RED}✗ Ошибка установки${NC}"
    fi
    
    rm -f "$TMP_DIR"/*.$PKG_EXT
}

remove_routerich_pkg() {
    local pkg_name="$1"
    echo -e "\n${MAGENTA}=== Удаление $pkg_name ===${NC}"
    $PKG_REMOVE "luci-app-$pkg_name" 2>/dev/null
    $PKG_REMOVE "$pkg_name" 2>/dev/null
    echo -e "${GREEN}✓ $pkg_name удален${NC}"
}

### =======================================================================
### ФУНКЦИИ ДЛЯ AWG
### =======================================================================

install_awg_pkg() {
    local pkgname="$1"
    local filename="${pkgname}${AWG_POSTFIX}"
    local url="${AWG_BASE_URL}v${VERSION}/${filename}"
    
    echo -e "${CYAN}Скачиваем:${NC} $filename"
    
    if download_file "$url" "$TMP_DIR/$filename"; then
        echo -e "${CYAN}Устанавливаем:${NC} $pkgname"
        $AWG_INSTALL_CMD "$TMP_DIR/$filename" >/dev/null 2>&1
        return $?
    else
        echo -e "${RED}Ошибка скачивания $filename${NC}"
        return 1
    fi
}

install_awg() {
    echo -e "\n${MAGENTA}=== Установка AWG ===${NC}"
    
    for pkg in kmod-amneziawg amneziawg-tools luci-proto-amneziawg luci-i18n-amneziawg-ru; do
        install_awg_pkg "$pkg" || { echo -e "${RED}Ошибка установки${NC}"; pause; return; }
    done
    
    if ! uci show network.$AWG_IF_NAME >/dev/null 2>&1; then
        echo -e "${CYAN}Создаем интерфейс AWG${NC}"
        uci set network.$AWG_IF_NAME=interface
        uci set network.$AWG_IF_NAME.proto=$AWG_PROTO
        uci set network.$AWG_IF_NAME.device=$AWG_DEV_NAME
        uci commit network
    fi
    
    echo -e "${YELLOW}Перезапуск сети...${NC}"
    /etc/init.d/network restart >/dev/null 2>&1
    
    echo -e "\n${GREEN}✓ AWG установлен!${NC}"
    echo -e "${YELLOW}В LuCI: Network → Interfaces → AWG → Edit → Load configuration${NC}"
    pause
}

remove_awg() {
    echo -e "\n${MAGENTA}=== Удаление AWG ===${NC}"
    
    for pkg in luci-i18n-amneziawg-ru luci-proto-amneziawg amneziawg-tools kmod-amneziawg; do
        $PKG_REMOVE "$pkg" 2>/dev/null
    done
    
    uci delete network.$AWG_IF_NAME 2>/dev/null
    for peer in $(uci show network 2>/dev/null | grep "interface='$AWG_IF_NAME'" | cut -d. -f2); do
        uci delete network.$peer 2>/dev/null
    done
    uci commit network 2>/dev/null
    
    /etc/init.d/network restart >/dev/null 2>&1
    echo -e "${GREEN}✓ AWG удален${NC}"
    pause
}

### =======================================================================
### МЕНЮ
### =======================================================================

get_routerich_label() {
    local pkg_name="$1"
    local main_file="$(get_remote_file "$pkg_name")"
    local remote_ver="$(get_version_from_filename "$main_file")"
    local local_ver="$(GET_LOCAL_VERSION "$pkg_name")"
    
    if [ -z "$local_ver" ] && [ -n "$remote_ver" ]; then
        echo "$pkg_name (нет / $remote_ver) → Установить"
    elif [ -n "$local_ver" ] && [ -n "$remote_ver" ] && [ "$local_ver" != "$remote_ver" ]; then
        echo "$pkg_name ($local_ver → $remote_ver) → Обновить"
    elif [ -n "$local_ver" ]; then
        echo "$pkg_name ($local_ver) → Удалить"
    else
        echo "$pkg_name → Недоступно"
    fi
}

run_routerich_action() {
    local pkg_name="$1"
    local main_file="$(get_remote_file "$pkg_name")"
    local remote_ver="$(get_version_from_filename "$main_file")"
    local local_ver="$(GET_LOCAL_VERSION "$pkg_name")"
    
    if [ -z "$local_ver" ] && [ -n "$remote_ver" ]; then
        install_routerich_pkg "$pkg_name"
    elif [ -n "$local_ver" ] && [ -n "$remote_ver" ] && [ "$local_ver" != "$remote_ver" ]; then
        install_routerich_pkg "$pkg_name"
    elif [ -n "$local_ver" ]; then
        remove_routerich_pkg "$pkg_name"
    else
        echo -e "${RED}Ошибка: пакет $pkg_name недоступен${NC}"
        pause
    fi
}

### =======================================================================
### ГЛАВНОЕ МЕНЮ
### =======================================================================

while true; do
    clear
    update_cache >/dev/null 2>&1
    
    # Определяем текст для AWG пункта
    if IS_PKG_INSTALLED "kmod-amneziawg"; then
        AWG_LABEL="AWG (AmneziaWG) → Удалить"
    else
        AWG_LABEL="AWG (AmneziaWG) → Установить"
    fi
    
    echo -e "${MAGENTA}======================================${NC}"
    echo -e "${MAGENTA}       RouterICH Package Manager       ${NC}"
    echo -e "${MAGENTA}======================================${NC}"
    echo -e "  ${CYAN}Пакетный менеджер:${NC} $PKG_TYPE"
    [ "$PKG_TYPE" = "opkg" ] && echo -e "  ${CYAN}Архитектура:${NC} $ARCH_SUFFIX"
    echo -e "${MAGENTA}======================================${NC}"
    echo -e "  ${GREEN}1)${NC} $(get_routerich_label zapret2)"
    echo -e "  ${GREEN}2)${NC} $(get_routerich_label zeroblock)"
    echo -e "  ${GREEN}3)${NC} $AWG_LABEL"
    echo -e "  ${RED}0)${NC} Выход"
    echo -e "${MAGENTA}======================================${NC}"
    
    printf "  ${CYAN}Выбор:${NC} "
    read -r choice
    
    case "$choice" in
        1) run_routerich_action zapret2 ;;
        2) run_routerich_action zeroblock ;;
        3) 
            if IS_PKG_INSTALLED "kmod-amneziawg"; then
                remove_awg
            else
                install_awg
            fi
            ;;
        0) echo -e "${GREEN}До свидания!${NC}"; exit 0 ;;
        *) echo -e "${RED}Неверный выбор${NC}"; sleep 1 ;;
    esac
done
