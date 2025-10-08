#!/bin/sh
# ==========================================
# ByeDPI & Podkop Manager by StressOzz
# Скрипт для OpenWRT
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
# Определение версий и статусов
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

    # --- ByeDPI ---
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
    if [ -f /usr/bin/podkop ]; then
        PODKOP_VER=$(podkop show_version 2>/dev/null | head -n1)
        [ -z "$PODKOP_VER" ] && PODKOP_VER="установлен (версия не определена)"
        PODKOP_STATUS=$(podkop get_status 2>/dev/null | grep -qi "running" && echo "${GREEN}запущен${NC}" || echo "${RED}остановлен${NC}")
    else
        PODKOP_VER="не установлен"
        PODKOP_STATUS="${RED}отсутствует${NC}"
    fi

    PODKOP_API_URL="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    PODKOP_LATEST_VER=$(curl -s "$PODKOP_API_URL" | grep '"tag_name"' | head -n1 | cut -d'"' -f4)
    [ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"
}

# ==========================================
# Установка / обновление ByeDPI
# ==========================================
install_update() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление ByeDPI${NC}\n"
    get_versions

    [ -z "$LATEST_URL" ] && { echo -e "${RED}Нет пакета для архитектуры: ${NC}$LOCAL_ARCH"; read -p "Enter..." dummy; return; }
    if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e "${YELLOW}Уже установлена последняя версия (${CYAN}$INSTALLED_VER${YELLOW})${NC}"
        read -p "Enter..." dummy
        return
    fi

    echo -e "${CYAN}Скачиваем пакет: ${NC}$LATEST_FILE"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return
    curl -L -s -o "$LATEST_FILE" "$LATEST_URL" || { echo -e "${RED}Ошибка загрузки ${NC}$LATEST_FILE"; read -p "Enter..." dummy; return; }

    echo -e "${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$LATEST_FILE" >/dev/null 2>&1
    rm -rf "$WORKDIR"

    [ -f /etc/init.d/byedpi ] && { /etc/init.d/byedpi enable >/dev/null 2>&1; /etc/init.d/byedpi restart >/dev/null 2>&1; }

    echo -e "\n${GREEN}ByeDPI ${LATEST_VER} успешно установлена!${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Удаление ByeDPI
# ==========================================
uninstall_byedpi() {
    clear
    echo -e "\n${MAGENTA}Удаление ByeDPI${NC}\n"
    [ -f /etc/init.d/byedpi ] && { /etc/init.d/byedpi stop >/dev/null 2>&1; /etc/init.d/byedpi disable >/dev/null 2>&1; }
    opkg remove --force-removal-of-dependent-packages byedpi >/dev/null 2>&1
    rm -rf /etc/init.d/byedpi /opt/byedpi /etc/config/byedpi
    echo -e "${GREEN}ByeDPI удалена полностью.${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Установка / обновление Podkop
# ==========================================
install_podkop() {
    clear
    echo -e "\n${MAGENTA}Установка / обновление Podkop${NC}\n"
    TMPDIR="/tmp/podkop_installer"
    rm -rf "$TMPDIR"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || return

    echo -e "${CYAN}Скачиваем официальный инсталлятор Podkop...${NC}"
    if curl -fsSL -o install.sh "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh"; then
        echo -e "${GREEN}Инсталлятор успешно загружен.${NC}"
        chmod +x install.sh
        echo -e "${CYAN}Запуск установки...${NC}"
        sh install.sh
        echo -e "${GREEN}Установка Podkop завершена.${NC}"
    else
        echo -e "${RED}Ошибка загрузки установочного скрипта Podkop.${NC}"
    fi
    rm -rf "$TMPDIR"
    read -p "Enter..." dummy
}

# ==========================================
# Интеграция ByeDPI в Podkop
# ==========================================
integrate_byedpi_podkop() {
    clear
    echo -e "\n${MAGENTA}Интеграция ByeDPI в Podkop${NC}\n"

    echo -e "${CYAN}Настройка dnsmasq...${NC}"
    uci set dhcp.@dnsmasq[0].localuse='0'
    uci commit dhcp
    echo -e "${GREEN}Настройки dnsmasq применены.${NC}\n"

    BYEDPI_CONFIG="/etc/config/byedpi"
    if [ -f "$BYEDPI_CONFIG" ]; then
        echo -e "${CYAN}Обновляем cmd_opts в $BYEDPI_CONFIG...${NC}"
        sed -i "s|option cmd_opts .*|    option cmd_opts '-o 2 --auto=t,r,a,s -d 2'|" "$BYEDPI_CONFIG"
        echo -e "${GREEN}Опции cmd_opts обновлены.${NC}\n"
    else
        echo -e "${RED}$BYEDPI_CONFIG не найден.${NC}\n"
    fi

    PODKOP_CONFIG="/etc/config/podkop"
    echo -e "${CYAN}Обновляем конфигурацию Podkop...${NC}"
    cat > "$PODKOP_CONFIG" <<'EOF'
config main 'main'
	option mode 'proxy'
	option proxy_config_type 'outbound'
	option community_lists_enabled '1'
	list community_lists 'russia_inside'
	option user_domain_list_type 'disabled'
	option local_domain_lists_enabled '0'
	option remote_domain_lists_enabled '0'
	option user_subnet_list_type 'disabled'
	option local_subnet_lists_enabled '0'
	option remote_subnet_lists_enabled '0'
	option all_traffic_from_ip_enabled '0'
	option exclude_from_ip_enabled '0'
	option yacd '0'
	option socks5 '0'
	option exclude_ntp '0'
	option quic_disable '0'
	option dont_touch_dhcp '0'
	option update_interval '1d'
	option dns_type 'udp'
	option dns_server '8.8.8.8'
	option split_dns_enabled '1'
	option split_dns_type 'udp'
	option split_dns_server '1.1.1.1'
	option dns_rewrite_ttl '60'
	option config_path '/etc/sing-box/config.json'
	option cache_path '/tmp/sing-box/cache.db'
	list iface 'br-lan'
	option mon_restart_ifaces '0'
	option ss_uot '0'
	option detour '0'
	option shutdown_correctly '0'
	option outbound_json '{
  "type": "socks",
  "server": "127.0.0.1",
  "server_port": 1080
}'
	option bootstrap_dns_server '77.88.8.8'
EOF
    echo -e "${GREEN}Конфигурация Podkop обновлена.${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Исправить стратегию ByeDPI
# ==========================================
fix_byedpi_strategy() {
    clear
    BYEDPI_CONFIG="/etc/config/byedpi"
    if [ ! -f "$BYEDPI_CONFIG" ]; then
        echo -e "${RED}$BYEDPI_CONFIG не найден.${NC}\n"
        read -p "Enter..." dummy
        return
    fi

    echo -e "\n${MAGENTA}Исправление стратегии ByeDPI${NC}\n"
    echo -e "${CYAN}Введите новую стратегию для option cmd_opts:${NC}"
    read -r NEW_STRATEGY
    sed -i "s|option cmd_opts .*|    option cmd_opts '$NEW_STRATEGY'|" "$BYEDPI_CONFIG"
    echo -e "${GREEN}Стратегия обновлена на:${NC} $NEW_STRATEGY"

    [ -f /etc/init.d/byedpi ] && /etc/init.d/byedpi restart
    echo -e "${GREEN}ByeDPI перезапущена.${NC}\n"
    read -p "Enter..." dummy
}

# ==========================================
# Меню
# ==========================================
show_menu() {
    get_versions
    clear
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
    echo -e "${GREEN}5) Выход${NC}"
    echo -e "${GREEN}6) Интеграция ByeDPI в Podkop${NC}"
    echo -e "${GREEN}7) Исправить стратегию ByeDPI${NC}\n"

    echo -ne "Выберите пункт: "
    read choice
    case "$choice" in
        1) install_update ;;
        2) uninstall_byedpi ;;
        3) [ -f /etc/init.d/byedpi ] && /etc/init.d/byedpi restart && echo -e "${GREEN}ByeDPI перезапущена.${NC}" || echo -e "${RED}ByeDPI не установлена.${NC}"; sleep 2 ;;
        4) install_podkop ;;
        6) integrate_byedpi_podkop ;;
        7) fix_byedpi_strategy ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Запуск
# ==========================================
while true; do
    show_menu
done
