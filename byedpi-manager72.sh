#!/bin/sh
# ==========================================
# ByeDPI & Podkop Manager by StressOzz
# ==========================================

# Цвета
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
WHITE="\033[1;37m"
BLUE="\033[0;34m"
GRAY='\033[38;5;239m'
DGRAY='\033[38;5;236m'

WORKDIR="/tmp/byedpi"

# ==========================================
# Проверка и установка curl
# ==========================================
curl_install() {
    if ! command -v curl >/dev/null 2>&1; then
        clear
        echo -e "\n${CYAN}Устанавливаем${NC} curl ${CYAN}для загрузки информации с GitHub${NC}\n"
        opkg update >/dev/null 2>&1 || echo -e "${RED}Ошибка обновления списка пакетов${NC}"
        opkg install curl >/dev/null 2>&1 || echo -e "${RED}Ошибка установки curl${NC}"
    fi
}

# ==========================================
# Безопасное скачивание файла
# ==========================================
download_file() {
    local url="$1"
    local output="$2"
    curl -fLsS -o "$output" "$url" || {
        echo -e "${RED}Ошибка загрузки файла:${NC} $url"
        return 1
    }
    return 0
}

# ==========================================
# Получение версий ByeDPI и Podkop
# ==========================================
get_versions() {
    # --- ByeDPI ---
    BYEDPI_VER=$(opkg list-installed | awk '/^byedpi / {print $3}' | sed 's/-r[0-9]\+$//')
    [ -z "$BYEDPI_VER" ] && BYEDPI_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | tail -n1 | awk '{print $2}')

    curl_install

    BYEDPI_API_URL="https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases"
    RELEASE_DATA=$(curl -s "$BYEDPI_API_URL")
    BYEDPI_URL=$(echo "$RELEASE_DATA" | grep browser_download_url | grep "$LOCAL_ARCH.ipk" | head -n1 | cut -d'"' -f4)

    if [ -n "$BYEDPI_URL" ]; then
        BYEDPI_FILE=$(basename "$BYEDPI_URL")
        BYEDPI_LATEST_VER=$(echo "$BYEDPI_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+).*/\1/')
        LATEST_VER="$BYEDPI_LATEST_VER"
        LATEST_URL="$BYEDPI_URL"
        LATEST_FILE="$BYEDPI_FILE"
    else
        BYEDPI_LATEST_VER="не найдена"
        LATEST_VER=""
        LATEST_URL=""
        LATEST_FILE=""
    fi

    # --- Podkop ---
    if command -v podkop >/dev/null 2>&1; then
        PODKOP_VER=$(podkop show_version 2>/dev/null | sed 's/-r[0-9]\+$//')
        [ -z "$PODKOP_VER" ] && PODKOP_VER="не найдена"
    else
        PODKOP_VER="не установлен"
    fi

    PODKOP_API_URL="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    PODKOP_LATEST_VER=$(curl -s "$PODKOP_API_URL" | grep '"tag_name"' | head -n1 | cut -d'"' -f4 | sed 's/-r[0-9]\+$//')
    [ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"

    # --- Нормализация версий ---
    BYEDPI_VER=$(echo "$BYEDPI_VER" | sed 's/^v//')
    BYEDPI_LATEST_VER=$(echo "$BYEDPI_LATEST_VER" | sed 's/^v//')
    PODKOP_VER=$(echo "$PODKOP_VER" | sed 's/^v//')
    PODKOP_LATEST_VER=$(echo "$PODKOP_LATEST_VER" | sed 's/^v//')
}

# ==========================================
# Проверка статуса версий
# ==========================================
check_byedpi_status() {
    if [ "$BYEDPI_VER" = "не найдена" ] || [ "$BYEDPI_VER" = "не установлен" ]; then
        BYEDPI_STATUS="${RED}$BYEDPI_VER${NC}"
    elif [ "$BYEDPI_LATEST_VER" != "не найдена" ] && [ "$BYEDPI_VER" != "$BYEDPI_LATEST_VER" ]; then
        BYEDPI_STATUS="${RED}$BYEDPI_VER${NC}"
    else
        BYEDPI_STATUS="${GREEN}$BYEDPI_VER${NC}"
    fi
}

check_podkop_status() {
    if [ "$PODKOP_VER" = "не найдена" ] || [ "$PODKOP_VER" = "не установлен" ]; then
        PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
    elif [ "$PODKOP_LATEST_VER" != "не найдена" ] && [ "$PODKOP_VER" != "$PODKOP_LATEST_VER" ]; then
        PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
    else
        PODKOP_STATUS="${GREEN}$PODKOP_VER${NC}"
    fi
}

# ==========================================
# Запуск сервисов
# ==========================================
start_byedpi() {
    echo -e "\nЗапуск ByeDPI...\n"
    /etc/init.d/byedpi enable
    /etc/init.d/byedpi start
}

start_podkop_full() {
    echo -e "\nЗапуск Podkop...\n"
    podkop enable >/dev/null 2>&1
    podkop reload >/dev/null 2>&1
    podkop restart >/dev/null 2>&1
    podkop list_update >/dev/null 2>&1
    echo -e "\n${GREEN}Podkop готов к работе.${NC}"
}

# ==========================================
# Установка / обновление ByeDPI
# ==========================================
install_update() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление ByeDPI${NC}"
    get_versions

    [ -z "$LATEST_URL" ] && {
        echo -e "\n${RED}Последняя версия ByeDPI не найдена. Установка пропущена.${NC}"
        read -p "Нажмите Enter..." dummy
        return
    }

    if [ "$BYEDPI_VER" = "$LATEST_VER" ]; then
        echo -e "\n${YELLOW}Уже установлена последняя версия (${CYAN}$BYEDPI_VER${YELLOW})${NC}"
        read -p "Нажмите Enter..." dummy
        return
    fi

    WORKDIR=$(mktemp -d)
    cd "$WORKDIR" || return

    echo -e "\n${CYAN}Скачиваем пакет: ${NC}$LATEST_FILE"
    download_file "$LATEST_URL" "$LATEST_FILE" || { read -p "Нажмите Enter..." dummy; return; }

    echo -e "\n${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$LATEST_FILE" >/dev/null 2>&1 || echo -e "${RED}Ошибка установки пакета${NC}"

    cd /
    rm -rf "$WORKDIR"

    echo -e "\n${GREEN}ByeDPI успешно установлен!${NC}"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Удаление ByeDPI
# ==========================================
uninstall_byedpi() {
    clear
    echo -e "\n${MAGENTA}Удаление ByeDPI${NC}"
    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi stop >/dev/null 2>&1
        /etc/init.d/byedpi disable >/dev/null 2>&1
    }
    opkg remove --force-removal-of-dependent-packages byedpi >/dev/null 2>&1
    rm -rf /etc/init.d/byedpi /opt/byedpi /etc/config/byedpi
    echo -e "\n${GREEN}ByeDPI удалён полностью.${NC}"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Установка / обновление Podkop
# ==========================================
install_podkop() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление Podkop${NC}"
    get_versions

    if [ "$PODKOP_LATEST_VER" = "не найдена" ]; then
        echo -e "\n${RED}Последняя версия Podkop не найдена. Установка пропущена.${NC}"
        read -p "Нажмите Enter..." dummy
        return
    fi

    if [ "$PODKOP_VER" = "$PODKOP_LATEST_VER" ]; then
        echo -e "\n${YELLOW}Уже установлена последняя версия Podkop (${CYAN}$PODKOP_VER${YELLOW}).${NC}"
        read -p "Нажмите Enter..." dummy
        return
    fi

    TMPDIR=$(mktemp -d)
    cd "$TMPDIR" || return

    echo -e "\n${CYAN}Скачиваем и запускаем официальный инсталлятор Podkop...${NC}"
    if download_file "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh" "install.sh"; then
        chmod +x install.sh
        sh install.sh
        echo -e "\n${GREEN}Podkop установлен / обновлён.${NC}"
    else
        echo -e "\n${RED}Ошибка загрузки установочного скрипта Podkop.${NC}"
    fi

    cd /
    rm -rf "$TMPDIR"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Интеграция ByeDPI в Podkop
# ==========================================
integration_byedpi_podkop() {
    clear
    echo -e "\n${MAGENTA}Интеграция ByeDPI в Podkop${NC}\n"

    if ! command -v byedpi >/dev/null 2>&1 && [ ! -f /etc/init.d/byedpi ]; then
        echo -e "${YELLOW}ByeDPI не установлен.${NC}"
        read -p "Нажмите Enter..." dummy
        return
    fi

    echo -e "Отключаем локальный DNS и перезапускаем dnsmasq..."
    uci set dhcp.@dnsmasq[0].localuse='0'
    uci commit dhcp
    /etc/init.d/dnsmasq restart >/dev/null 2>&1

    if [ -f /etc/config/byedpi ]; then
        sed -i "s|option cmd_opts .*| option cmd_opts '-o2 --auto=t,r,a,s -d2'|" /etc/config/byedpi
    fi

    cat <<EOF >/etc/config/podkop
config main 'main'
	option mode 'proxy'
	option proxy_config_type 'outbound'
	option community_lists_enabled '1'
	option user_domain_list_type 'disabled'
	option local_domain_lists_enabled '0'
	option remote_domain_lists_enabled '0'
	option all_traffic_from_ip_enabled '0'
	option exclude_from_ip_enabled '0'
	option dns_type 'udp'
	option dns_server '8.8.8.8'
	option config_path '/etc/sing-box/config.json'
	option cache_path '/tmp/sing-box/cache.db'
	list iface 'br-lan'
	option outbound_json '{
  "type": "socks",
  "server": "127.0.0.1",
  "server_port": 1080
}'
	list community_lists 'russia_inside'
	list community_lists 'hodca'
EOF

    start_byedpi
    start_podkop_full

    echo -e "\n${GREEN}ByeDPI интегрирован в Podkop.${NC}"
    echo -ne "Нужно ${RED}обязательно${NC} перезагрузить роутер. Перезагрузить сейчас? [y/N]: "
    read REBOOT_CHOICE
    case "$REBOOT_CHOICE" in
        y|Y) echo -e "\n${GREEN}Перезагрузка роутера...${NC}"; reboot ;;
        *) echo -e "${YELLOW}Необходимость перезагрузки отложена.${NC}" ;;
    esac
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Изменение стратегии ByeDPI
# ==========================================
fix_strategy() {
    clear
    echo -e "\n${MAGENTA}Изменение стратегии ByeDPI${NC}"

    if [ -f /etc/config/byedpi ]; then
        CURRENT_STRATEGY=$(grep "option cmd_opts" /etc/config/byedpi | sed -E "s/.*'(.+)'/\1/")
        [ -z "$CURRENT_STRATEGY" ] && CURRENT_STRATEGY="(не задана)"
        echo -e "\n${CYAN}Текущая стратегия:${NC} ${WHITE}$CURRENT_STRATEGY${NC}\n"
        read -p "Введите новую стратегию (Enter — оставить текущую): " NEW_STRATEGY
        if [ -n "$NEW_STRATEGY" ]; then
            sed -i "s|option cmd_opts .*| option cmd_opts '$NEW_STRATEGY'|" /etc/config/byedpi
            start_byedpi
            echo -e "${GREEN}Стратегия изменена на:${NC} ${WHITE}$NEW_STRATEGY${NC}"
        else
            echo -e "${YELLOW}Стратегия не изменена. Оставлена текущая:${NC} ${WHITE}$CURRENT_STRATEGY${NC}"
        fi
    else
        echo -e "\n${YELLOW}ByeDPI не установлен.${NC}"
    fi
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Удаление Podkop
# ==========================================
uninstall_podkop() {
    clear
    echo -e "\n${MAGENTA}Удаление Podkop${NC}"
    opkg remove luci-i18n-podkop-ru luci-app-podkop podkop --autoremove >/dev/null 2>&1 || true
    rm -rf /etc/config/podkop /tmp/podkop_installer
    echo -e "\n${GREEN}Podkop удалён полностью.${NC}"
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Полная установка и интеграция
# ==========================================
full_install_integration() {
    install_update
    install_podkop
    integration_byedpi_podkop
}

# ==========================================
# Меню
# ==========================================
show_menu() {
    get_versions

    if [ -f /etc/config/byedpi ]; then
        CURRENT_STRATEGY=$(grep "option cmd_opts" /etc/config/byedpi | sed -E "s/.*'(.+)'/\1/")
        [ -z "$CURRENT_STRATEGY" ] && CURRENT_STRATEGY="(не задана)"
    else
        CURRENT_STRATEGY="не найдена"
    fi

    clear
    echo -e ""
    echo -e "╔═══════════════════════════════╗"
    echo -e "║     ${BLUE}Podkop+ByeDPI Manager${NC}     ║"
    echo -e "╚═══════════════════════════════╝"
    echo -e "                             ${DGRAY}v1.7${NC}"

    check_podkop_status
    check_byedpi_status

    echo -e "${MAGENTA}--- ByeDPI ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $BYEDPI_STATUS"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$BYEDPI_LATEST_VER${NC}"
    echo -e "${YELLOW}Текущая стратегия:${NC} ${WHITE}$CURRENT_STRATEGY${NC}\n"
    echo -e "${MAGENTA}--- Podkop ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_STATUS"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$PODKOP_LATEST_VER${NC}\n"
    echo -e "${YELLOW}Архитектура устройства:${NC} $LOCAL_ARCH\n"
    echo -e "${GREEN}1) Установить / обновить ByeDPI${NC}"
    echo -e "${GREEN}2) Удалить ByeDPI${NC}"
    echo -e "${GREEN}3) Интеграция ByeDPI в Podkop${NC}"
    echo -e "${GREEN}4) Изменить стратегию ByeDPI${NC}"
    echo -e "${GREEN}5) Установить / обновить Podkop${NC}"
    echo -e "${GREEN}6) Удалить Podkop${NC}"
    echo -e "${GREEN}7) Установить ByeDPI + Podkop + Интеграция${NC}"
    echo -e "${GREEN}8) Выход (Enter)${NC}\n"
    echo -ne "Выберите пункт: "
    read choice

    case "$choice" in
        1) install_update ;;
        2) uninstall_byedpi ;;
        3) integration_byedpi_podkop ;;
        4) fix_strategy ;;
        5) install_podkop ;;
        6) uninstall_podkop ;;
        7) full_install_integration ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
