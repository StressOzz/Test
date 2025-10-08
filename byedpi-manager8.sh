#!/bin/sh
# ==========================================
# ByeDPI Manager by StressOzz
# Скрипт для установки, обновления и удаления ByeDPI и Podkop на OpenWRT
# ==========================================

# Цвета
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

WORKDIR="/tmp/byedpi"

# ==========================================
# Установка или обновление ByeDPI
# ==========================================
install_update() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление ByeDPI${NC}\n"
    get_versions

    [ -z "$LATEST_URL" ] && {
        echo -e "${RED}Нет пакета для архитектуры: ${NC}$LOCAL_ARCH\n"
        read -p "Enter..." dummy
        return
    }

    if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e "${YELLOW}Уже установлена последняя версия (${CYAN}$INSTALLED_VER${YELLOW})${NC}\n"
        read -p "Enter..." dummy
        return
    fi

    echo -e "${CYAN}Скачиваем пакет: ${NC}$LATEST_FILE"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return
    curl -L -s -o "$LATEST_FILE" "$LATEST_URL" || {
        echo -e "${RED}Ошибка загрузки ${NC}$LATEST_FILE"
        read -p "Enter..." dummy
        return
    }

    echo -e "${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$LATEST_FILE" >/dev/null 2>&1
    rm -rf "$WORKDIR"

    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi enable >/dev/null 2>&1
        /etc/init.d/byedpi restart >/dev/null 2>&1
    }

    echo -e "\n${GREEN}ByeDPI ${LATEST_VER} успешно установлена!${NC}\n"
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
# Установка Podkop
# ==========================================
install_podkop() {
    clear
    echo -e "\n${MAGENTA}Установка Podkop${NC}\n"
    TMPDIR="/tmp/podkop_installer"
    rm -rf "$TMPDIR"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || return

    echo -e "${CYAN}Скачиваем официальный инсталлятор Podkop...${NC}\n"
    if curl -fsSL -o install.sh "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh"; then
        echo -e "${GREEN}Инсталлятор успешно загружен.${NC}\n"
        chmod +x install.sh
        echo -e "${CYAN}Запуск установки...${NC}\n"
        sh install.sh
        echo -e "\n${GREEN}Установка Podkop завершена.${NC}\n"
    else
        echo -e "${RED}Ошибка загрузки установочного скрипта Podkop.${NC}\n"
    fi
    rm -rf "$TMPDIR"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Определение архитектуры, версии, статуса
# ==========================================
get_versions() {
    # --- ByeDPI ---
    INSTALLED_VER=$(opkg list-installed | grep '^byedpi ' | awk '{print $3}')
    [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | tail -n1 | awk '{print $2}')

    command -v curl >/dev/null 2>&1 || {
        echo -e "${CYAN}Устанавливаем curl...${NC}"
        opkg update >/dev/null 2>&1
        opkg install curl >/dev/null 2>&1
    }

    # --- Получаем версии ByeDPI ---
    API_URL="https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases"
    RELEASE_DATA=$(curl -s "$API_URL")
    LATEST_URL=$(echo "$RELEASE_DATA" | grep browser_download_url | grep "$LOCAL_ARCH.ipk" | head -n1 | cut -d'"' -f4)
    if [ -n "$LATEST_URL" ]; then
        LATEST_FILE=$(basename "$LATEST_URL")
        LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+-[^_]+)_.*/\1/')
    else
        LATEST_VER="не найдена"
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

    # --- Podkop ---
    if command -v podkop >/dev/null 2>&1; then
        PODKOP_VER=$(podkop show_version 2>/dev/null)
        [ -z "$PODKOP_VER" ] && PODKOP_VER="не определена"
        PODKOP_STATUS=$(podkop get_status 2>/dev/null | grep -qi "running" && echo "${GREEN}запущен${NC}" || echo "${RED}остановлен${NC}")
    else
        PODKOP_VER="не установлен"
        PODKOP_STATUS="${RED}отсутствует${NC}"
    fi

    # --- Получаем последнюю версию Podkop с GitHub ---
    PODKOP_API_URL="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    PODKOP_LATEST_VER=$(curl -s "$PODKOP_API_URL" | grep '"tag_name"' | head -n1 | cut -d'"' -f4)
    [ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"
}

# ==========================================
# Меню
# ==========================================
show_menu() {
    get_versions
    clear
    echo -e "██████╗  ██████╗ ██████╗ ██╗  ██╗ ██████╗ ██████╗"
    echo -e "██╔══██╗██╔═══██╗██╔══██╗██║ ██╔╝██╔═══██╗██╔══██╗"
    echo -e "██████╔╝██║   ██║██║  ██║█████╔╝ ██║   ██║██████╔╝"
    echo -e "██╔═══╝ ██║   ██║██║  ██║██╔═██╗ ██║   ██║██╔═══╝ "
    echo -e "██║     ╚██████╔╝██████╔╝██║  ██╗╚██████╔╝██║     "
    echo -e "╚═╝      ╚═════╝ ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚═╝     "
    echo -e "Manager by StressOzz\n"

    echo -e "${YELLOW}Архитектура:${NC} $LOCAL_ARCH\n"

    echo -e "${MAGENTA}--- ByeDPI ---${NC}"
    echo -e "${YELLOW}Установлена версия:${NC} $INSTALLED_VER"
    echo -e "${YELLOW}Последняя версия:${NC} $LATEST_VER"
    echo -e "${YELLOW}Статус службы:${NC} $BYEDPI_STATUS\n"

    echo -e "${MAGENTA}--- Podkop ---${NC}"
    echo -e "${YELLOW}Установлена версия:${NC} $PODKOP_VER"
    echo -e "${YELLOW}Последняя версия:${NC} $PODKOP_LATEST_VER"
    echo -e "${YELLOW}Статус службы:${NC} $PODKOP_STATUS\n"

    echo -e "${GREEN}1) Установить / обновить ByeDPI${NC}"
    echo -e "${GREEN}2) Удалить ByeDPI${NC}"
    echo -e "${GREEN}3) Перезапустить ByeDPI${NC}"
    echo -e "${GREEN}4) Установить / обновить Podkop${NC}"
    echo -e "${GREEN}5) Выход${NC}\n"
    echo -ne "Выберите пункт: "
    read choice

    case "$choice" in
        1) install_update ;;
        2) uninstall_byedpi ;;
        3)
            if [ -f /etc/init.d/byedpi ]; then
                /etc/init.d/byedpi restart
                echo -e "${GREEN}ByeDPI перезапущена.${NC}"
            else
                echo -e "${RED}ByeDPI не установлена.${NC}"
            fi
            sleep 2 ;;
        4) install_podkop ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done

# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
