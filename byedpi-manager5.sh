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
    if [ -f /etc/init.d/podkop ]; then
        PODKOP_VER=$(/etc/init.d/podkop version 2>/dev/null | grep -Eo '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        [ -z "$PODKOP_VER" ] && PODKOP_VER="установлен (версия не определена)"
        PODKOP_STATUS=$(/etc/init.d/podkop status 2>/dev/null | grep -qi "running" && echo "${GREEN}запущен${NC}" || echo "${RED}остановлен${NC}")
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
echo -e "Manager by StressOzz\n"

echo -e ""
    echo -e "${YELLOW}Архитектура:${NC} $LOCAL_ARCH\n"
echo -e ""
    echo -e "${MAGENTA}--- ByeDPI ---${NC}"
    echo -e "${YELLOW}Установлена версия:${NC} $INSTALLED_VER"
    echo -e "${YELLOW}Последняя версия:${NC} $LATEST_VER"
    echo -e "${YELLOW}Статус службы:${NC} $BYEDPI_STATUS\n"
echo -e ""
    echo -e "${MAGENTA}--- Podkop ---${NC}"
    echo -e "${YELLOW}Установлена версия:${NC} $PODKOP_VER"
    echo -e "${YELLOW}Последняя версия:${NC} $PODKOP_LATEST_VER"
    echo -e "${YELLOW}Статус службы:${NC} $PODKOP_STATUS\n"
echo -e ""
    echo -e "${GREEN}1) Установить / обновить ByeDPI${NC}"
    echo -e "${GREEN}2) Удалить ByeDPI${NC}"
    echo -e "${GREEN}3) Перезапустить ByeDPI${NC}"
    echo -e "${GREEN}4) Установить / обновить Podkop${NC}"
    echo -e "${GREEN}5) Выход${NC}\n"
echo -e ""
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
