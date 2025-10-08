#!/bin/sh
# ==========================================
# ByeDPI Manager by StressOzz
# Скрипт для установки, обновления и удаления ByeDPI на OpenWRT
# Репозиторий: https://github.com/DPITrickster/ByeDPI-OpenWrt
# ==========================================

# Цвета
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[1;34m"
NC="\033[0m"
GRAY='\033[38;5;239m'
DGRAY='\033[38;5;236m'

WORKDIR="/tmp/byedpi"

# ==========================================
# Определение архитектуры, версии, статуса
# ==========================================
get_versions() {
    INSTALLED_VER=$(opkg list-installed | grep '^byedpi ' | awk '{print $3}')
    [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | tail -n1 | awk '{print $2}')

    command -v curl >/dev/null 2>&1 || {
        echo -e "${CYAN}Устанавливаем curl...${NC}"
        opkg update >/dev/null 2>&1
        opkg install curl >/dev/null 2>&1
    }

    API_URL="https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases"
    RELEASE_DATA=$(curl -s "$API_URL")

    LATEST_URL=$(echo "$RELEASE_DATA" | grep browser_download_url | grep "$LOCAL_ARCH.ipk" | head -n1 | cut -d'"' -f4)
    PREV_URL=$(echo "$RELEASE_DATA" | grep browser_download_url | grep "$LOCAL_ARCH.ipk" | sed -n '2p' | cut -d'"' -f4)

    if [ -n "$LATEST_URL" ]; then
        LATEST_FILE=$(basename "$LATEST_URL")
        LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+-[^_]+)_.*/\1/')
    else
        LATEST_VER="не найдена"
    fi

    if [ -n "$PREV_URL" ]; then
        PREV_FILE=$(basename "$PREV_URL")
        PREV_VER=$(echo "$PREV_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+-[^_]+)_.*/\1/')
    else
        PREV_VER="не найдена"
    fi

    if [ -f /etc/init.d/byedpi ]; then
        if /etc/init.d/byedpi status 2>/dev/null | grep -qi "running"; then
            BYEDPI_STATUS="${GREEN}запущен${NC}"
        else
            BYEDPI_STATUS="${RED}остановлен${NC}"
        fi
    else
        BYEDPI_STATUS="${RED}не установлен${NC}"
    fi
}

# ==========================================
# Установка или обновление ByeDPI
# ==========================================
install_update() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление ByeDPI${NC}\n"
    get_versions

    TARGET_URL="$LATEST_URL"
    TARGET_FILE="$LATEST_FILE"
    TARGET_VER="$LATEST_VER"

    if [ -z "$TARGET_URL" ]; then
        echo -e "${RED}Нет пакета для архитектуры: ${NC}$LOCAL_ARCH\n"
        read -p "Нажмите Enter..." dummy
        return
    fi

    if [ "$INSTALLED_VER" = "$TARGET_VER" ]; then
        echo -e "${YELLOW}Уже установлена последняя версия (${CYAN}$INSTALLED_VER${YELLOW})${NC}\n"
        read -p "Нажмите Enter..." dummy
        return
    fi

    echo -e "${CYAN}Скачиваем пакет: ${NC}$TARGET_FILE"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return
    curl -L -s -o "$TARGET_FILE" "$TARGET_URL" || {
        echo -e "${RED}Ошибка загрузки ${NC}$TARGET_FILE"
        read -p "Enter..." dummy
        return
    }

    echo -e "${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$TARGET_FILE" >/dev/null 2>&1

    echo -e "${CYAN}Очистка временных файлов...${NC}"
    rm -rf "$WORKDIR"

    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi enable >/dev/null 2>&1
        /etc/init.d/byedpi restart >/dev/null 2>&1
    }

    echo -e "\n${GREEN}ByeDPI ${TARGET_VER} успешно установлена!${NC}\n"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Выбор версии (последние 10)
# ==========================================
choose_version() {
    clear
    echo -e "\n${MAGENTA}Выбор версии ByeDPI${NC}\n"

    API_URL="https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases"
    RELEASE_DATA=$(curl -s "$API_URL")
    VERSIONS=$(echo "$RELEASE_DATA" | grep -Eo '"tag_name":\s*"[0-9]+\.[0-9]+\.[0-9]+[^"]*"' | head -n 10 | awk -F'"' '{print $4}')

    i=1
    echo "$VERSIONS" | while read ver; do
        echo -e "${GREEN}$i)${NC} $ver"
        i=$((i+1))
    done

    echo -n "\nВведите номер версии для установки (Enter для выхода): "
    read num
    [ -z "$num" ] && return

    SELECTED=$(echo "$VERSIONS" | sed -n "${num}p")
    [ -z "$SELECTED" ] && { echo -e "${RED}Неверный выбор${NC}"; sleep 2; return; }

    TARGET_URL=$(echo "$RELEASE_DATA" | grep browser_download_url | grep "$SELECTED" | grep "$LOCAL_ARCH.ipk" | cut -d'"' -f4 | head -n1)
    [ -z "$TARGET_URL" ] && { echo -e "${RED}Не найден пакет для вашей архитектуры${NC}"; read -p "Enter..." dummy; return; }

    TARGET_FILE=$(basename "$TARGET_URL")
    TARGET_VER="$SELECTED"

    echo -e "${CYAN}Выбрана версия:${NC} $TARGET_VER"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return

    echo -e "${CYAN}Скачиваем пакет...${NC}"
    curl -L -s -o "$TARGET_FILE" "$TARGET_URL" || {
        echo -e "${RED}Ошибка загрузки ${NC}$TARGET_FILE"
        read -p "Enter..." dummy
        return
    }

    echo -e "${CYAN}Устанавливаем...${NC}"
    opkg install --force-reinstall "$TARGET_FILE" >/dev/null 2>&1

    rm -rf "$WORKDIR"

    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi enable >/dev/null 2>&1
        /etc/init.d/byedpi restart >/dev/null 2>&1
    }

    echo -e "\n${GREEN}ByeDPI ${TARGET_VER} установлена!${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Полное удаление ByeDPI
# ==========================================
uninstall_byedpi() {
    clear
    echo -e "\n${MAGENTA}Удаление ByeDPI${NC}\n"

    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi stop >/dev/null 2>&1
        /etc/init.d/byedpi disable >/dev/null 2>&1
    }

    opkg remove --force-removal-of-dependent-packages byedpi >/dev/null 2>&1

    rm -rf /etc/init.d/byedpi /opt/byedpi /etc/config/byedpi
    echo -e "${GREEN}ByeDPI удалена полностью.${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Меню
# ==========================================
show_menu() {
    get_versions
    clear
echo -e "██████╗  ██████╗ ██████╗ ██╗  ██╗ ██████╗ ██████╗               "
echo -e "██╔══██╗██╔═══██╗██╔══██╗██║ ██╔╝██╔═══██╗██╔══██╗              "
echo -e "██████╔╝██║   ██║██║  ██║█████╔╝ ██║   ██║██████╔╝              "
echo -e "██╔═══╝ ██║   ██║██║  ██║██╔═██╗ ██║   ██║██╔═══╝               "
echo -e "██║     ╚██████╔╝██████╔╝██║  ██╗╚██████╔╝██║                   "
echo -e "╚═╝      ╚═════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝                   "
echo -e "https://github.com/itdoginfo/podkop                                                                "
echo -e "                    ██████╗ ██╗   ██╗███████╗██████╗ ██████╗ ██╗"
echo -e "                    ██╔══██╗╚██╗ ██╔╝██╔════╝██╔══██╗██╔══██╗██║"
echo -e "                    ██████╔╝ ╚████╔╝ █████╗  ██║  ██║██████╔╝██║"
echo -e "                    ██╔══██╗  ╚██╔╝  ██╔══╝  ██║  ██║██╔═══╝ ██║"
echo -e "                    ██████╔╝   ██║   ███████╗██████╔╝██║     ██║"
echo -e "                    ╚═════╝    ╚═╝   ╚══════╝╚═════╝ ╚═╝     ╚═╝"
echo -e "                  https://github.com/DPITrickster/ByeDPI-OpenWrt"
    echo -e "         ${MAGENTA}Manager by StressOzz${NC}"
    echo -e "     ${GRAY}https://github.com/DPITrickster/ByeDPI-OpenWrt${NC}\n"
    echo -e "${YELLOW}Архитектура:${NC} $LOCAL_ARCH"
    echo -e "${YELLOW}Установлена версия:${NC} $INSTALLED_VER"
    echo -e "${YELLOW}Последняя версия:${NC} $LATEST_VER"
    echo -e "${YELLOW}Статус службы:${NC} $BYEDPI_STATUS\n"

    echo -e "${GREEN}1) Установить / обновить ByeDPI${NC}"
    echo -e "${GREEN}2) Установить конкретную версию${NC}"
    echo -e "${GREEN}3) Удалить ByeDPI${NC}"
    echo -e "${GREEN}4) Перезапустить службу${NC}"
    echo -e "${GREEN}5) Выход${NC}"
    echo -ne "\nВыберите пункт: "
    read choice

    case "$choice" in
        1) install_update ;;
        2) choose_version ;;
        3) uninstall_byedpi ;;
        4)
            if [ -f /etc/init.d/byedpi ]; then
                /etc/init.d/byedpi restart
                echo -e "${GREEN}Служба перезапущена.${NC}"
            else
                echo -e "${RED}ByeDPI не установлена.${NC}"
            fi
            sleep 2
            ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
