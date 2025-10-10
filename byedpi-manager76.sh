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
# Запуск ByeDPI
# ==========================================
start_byedpi() {
echo -e "Запуск ByeDPI..."
echo -e ""
    /etc/init.d/byedpi enable
    /etc/init.d/byedpi start
}

# ==========================================
# Запуск Podkop
# ==========================================
start_podkop_full() {
    echo -e "Запуск Podkop..."
echo -e ""
    echo -e "Включаем автозапуск..."
    podkop enable >/dev/null 2>&1
echo -e ""
    echo -e "Применяем конфигурацию..."
    podkop reload >/dev/null 2>&1
echo -e ""
    echo -e "Перезапускаем сервис..."
    podkop restart >/dev/null 2>&1
echo -e ""
    echo -e "Обновляем списки..."
    podkop list_update >/dev/null 2>&1
echo -e ""
    echo -e "Podkop готов к работе."
}

# ==========================================
# Функция проверки и установки curl
# ==========================================
curl_install() {
    command -v curl >/dev/null 2>&1 || {
		clear 
		echo -e ""
        echo -e "${CYAN}Устанавливаем${NC} curl ${CYAN}для загрузки информации с ${NC}GitHub"
		echo -e ""
        opkg update >/dev/null 2>&1
        opkg install curl >/dev/null 2>&1
    }
}
# ==========================================
# Подготовка статусов и версий
# ==========================================
get_versions() {
    # --- ByeDPI ---
    BYEDPI_VER=$(opkg list-installed | grep '^byedpi ' | awk '{print $3}' | sed 's/-r[0-9]\+$//')
    [ -z "$BYEDPI_VER" ] && BYEDPI_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | tail -n1 | awk '{print $2}')

    # --- Получаем последнюю версию ByeDPI ---
    curl -sL "https://api.github.com/repos/DPITrickster/ByeDPI-OpenWrt/releases" | \
    grep browser_download_url | grep "$LOCAL_ARCH.ipk" | head -n1 | cut -d'"' -f4 | \
    { read BYEDPI_URL; BYEDPI_FILE=$(basename "$BYEDPI_URL"); BYEDPI_LATEST_VER=$(echo "$BYEDPI_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+).*/\1/'); }

    [ -z "$BYEDPI_LATEST_VER" ] && BYEDPI_LATEST_VER="не найдена"

    # --- Podkop ---
    if command -v podkop >/dev/null 2>&1; then
        PODKOP_VER=$(podkop show_version 2>/dev/null | sed 's/-r[0-9]\+$//')
        [ -z "$PODKOP_VER" ] && PODKOP_VER="не найдена"
    else
        PODKOP_VER="не установлен"
    fi

    PODKOP_LATEST_VER=$(curl -sL "https://api.github.com/repos/itdoginfo/podkop/releases/latest" | grep '"tag_name"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
    [ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"

    CURRENT_STRATEGY=$(grep 'cmd_opts' /etc/config/byedpi 2>/dev/null | cut -d"'" -f2)
    [ -z "$CURRENT_STRATEGY" ] && CURRENT_STRATEGY="не задана"
}

# ==========================================
# Проверка статусов
# ==========================================
check_byedpi_status() {
    if [ "$BYEDPI_VER" = "не найдена" ] || [ "$BYEDPI_VER" = "не установлен" ]; then
        BYEDPI_STATUS="${RED}$BYEDPI_VER${NC}"
    elif [ "$BYEDPI_VER" != "$BYEDPI_LATEST_VER" ]; then
        BYEDPI_STATUS="${RED}$BYEDPI_VER${NC}"
    else
        BYEDPI_STATUS="${GREEN}$BYEDPI_VER${NC}"
    fi
}

check_podkop_status() {
    if [ "$PODKOP_VER" = "не найден" ] || [ "$PODKOP_VER" = "не установлен" ]; then
        PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
    elif [ "$PODKOP_VER" != "$PODKOP_LATEST_VER" ]; then
        PODKOP_STATUS="${RED}$PODKOP_VER${NC}"
    else
        PODKOP_STATUS="${GREEN}$PODKOP_VER${NC}"
    fi
}

# ==========================================
# Полная установка + интеграция
# ==========================================
full_install_integration() {
    install_update
    install_podkop
    integration_byedpi_podkop
}
# ==========================================
# Установка / обновление ByeDPI
# ==========================================
install_update() {
    clear
	echo -e ""
    echo -e "${MAGENTA}Установка / обновление ByeDPI${NC}"
    get_versions

    [ -z "$LATEST_URL" ] && { echo -e "${RED}Последняя версия ByeDPI не найдена.${NC}"; read -p "Enter..."; return; }

    if [ "$BYEDPI_VER" = "$LATEST_VER" ]; then
        echo -e "${YELLOW}Уже установлена последняя версия (${CYAN}$BYEDPI_VER${YELLOW})${NC}"
        read -p "Enter..."
        return
    fi

    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return
    curl -L -s -O "$LATEST_URL" || { echo -e "${RED}Ошибка загрузки ${NC}$LATEST_FILE"; read -p "Enter..."; return; }

    echo -e "${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$LATEST_FILE" >/dev/null 2>&1
    rm -rf "$WORKDIR"
    echo -e "${GREEN}ByeDPI успешно установлен!${NC}"
    read -p "Enter..."
}

# ==========================================
# Удаление ByeDPI
# ==========================================
uninstall_byedpi() {
    clear
	echo -e ""
    echo -e "${MAGENTA}Удаление ByeDPI${NC}"
    [ -f /etc/init.d/byedpi ] && { /etc/init.d/byedpi stop >/dev/null 2>&1; /etc/init.d/byedpi disable >/dev/null 2>&1; }
    opkg remove --force-removal-of-dependent-packages byedpi >/dev/null 2>&1
    rm -rf /etc/init.d/byedpi /opt/byedpi /etc/config/byedpi
    echo -e "${GREEN}ByeDPI удалён полностью.${NC}"
    read -p "Enter..."
}

# ==========================================
# Установка / обновление Podkop
# ==========================================
install_podkop() {
    clear
    echo -e "${MAGENTA}Установка / обновление Podkop${NC}"

    TMPDIR="/tmp/podkop_installer"
    rm -rf "$TMPDIR"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || return

    curl_install
    PODKOP_API_URL="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    LATEST_VER=$(curl -s "$PODKOP_API_URL" | grep '"tag_name"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')

    if [ -z "$LATEST_VER" ]; then echo -e "${RED}Не удалось получить последнюю версию Podkop.${NC}"; read -p "Enter..."; return; fi

    PKG_PODKOP="podkop-v${LATEST_VER}-r1-all.ipk"
    PKG_LUCI_APP="luci-app-podkop-v${LATEST_VER}-r1-all.ipk"
    PKG_LUCI_RU="luci-i18n-podkop-ru-v${LATEST_VER}.ipk"

    echo -ne "Установить русский интерфейс Podkop? [y/N]: "
    read RU_CHOICE
    INSTALL_RU=0
    case "$RU_CHOICE" in y|Y) INSTALL_RU=1 ;; esac

    echo -e "${CYAN}Скачиваем Podkop и luci-app...${NC}"
    for pkg in "$PKG_PODKOP" "$PKG_LUCI_APP"; do
        curl -L -s -O "https://github.com/itdoginfo/podkop/releases/download/v${LATEST_VER}/${pkg}" || { echo -e "${RED}Ошибка загрузки $pkg${NC}"; read -p "Enter..."; return; }
    done
    [ "$INSTALL_RU" -eq 1 ] && curl -L -s -O "https://github.com/itdoginfo/podkop/releases/download/v${LATEST_VER}/${PKG_LUCI_RU}" || true

    echo -e "${CYAN}Устанавливаем пакеты...${NC}"
    opkg install --force-reinstall "$PKG_PODKOP" "$PKG_LUCI_APP" >/dev/null 2>&1
    [ "$INSTALL_RU" -eq 1 ] && opkg install --force-reinstall "$PKG_LUCI_RU" >/dev/null 2>&1

    rm -rf "$TMPDIR"
    echo -e "${GREEN}Podkop успешно установлен / обновлён!${NC}"
    read -p "Enter..."
}

# ==========================================
# Интеграция ByeDPI ↔ Podkop
# ==========================================
integration_byedpi_podkop() {
    clear
	echo -e "${MAGENTA}Интеграция ByeDPI в Podkop${NC}"

	if ! command -v byedpi >/dev/null 2>&1 && [ ! -f /etc/init.d/byedpi ]; then
		echo -e "${YELLOW}ByeDPI не установлен.${NC}"
		read -p "Enter..." dummy
		return
	fi

	echo -e "Отключаем локальный DNS..."
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
	list community_lists 'russia_inside'
	list community_lists 'hodca'
EOF

	start_byedpi
	start_podkop_full
	echo -e "${GREEN}ByeDPI интегрирован в Podkop.${NC}"
	echo -ne "Нужно ${RED}обязательно${NC} перезагрузить роутер. Перезагрузить сейчас? [y/N]: "
	read REBOOT_CHOICE
	case "$REBOOT_CHOICE" in
	y|Y) echo -e "${GREEN}Перезагрузка роутера...${NC}"; reboot ;;
	*) echo -e "${YELLOW}Необходимость перезагрузки отложена.${NC}" ;;
	esac
	read -p "Enter..." dummy
}

# ==========================================
# Изменение стратегии ByeDPI
# ==========================================
fix_strategy() {
    clear
    echo -e "${MAGENTA}Изменение стратегии ByeDPI${NC}"

    if [ -f /etc/config/byedpi ]; then
        CURRENT_STRATEGY=$(grep 'cmd_opts' /etc/config/byedpi | cut -d"'" -f2)
        echo -e "Текущие параметры: ${CYAN}$CURRENT_STRATEGY${NC}"
        echo -ne "Введите новые параметры: "
        read NEW_STRATEGY
        sed -i "s|option cmd_opts .*| option cmd_opts '$NEW_STRATEGY'|" /etc/config/byedpi
        /etc/init.d/byedpi restart >/dev/null 2>&1
        echo -e "${GREEN}Стратегия обновлена и ByeDPI перезапущен.${NC}"
    else
        echo -e "${RED}ByeDPI не установлен.${NC}"
    fi
    read -p "Enter..." dummy
}

# ==========================================
# Удаление Podkop
# ==========================================
uninstall_podkop() {
    clear
    echo -e "${MAGENTA}Удаление Podkop${NC}"
    podkop disable >/dev/null 2>&1 2>/dev/null || true
    opkg remove --force-removal-of-dependent-packages podkop luci-app-podkop luci-i18n-podkop-ru >/dev/null 2>&1
    rm -rf /etc/config/podkop
    echo -e "${GREEN}Podkop удалён полностью.${NC}"
    read -p "Enter..."
}

# ==========================================
# Главное меню
# ==========================================
show_menu() {
    clear
    echo -e ""
    echo -e "╔═══════════════════════════════╗"
    echo -e "║     ${BLUE}Podkop+ByeDPI Manager${NC}     ║"
    echo -e "╚═══════════════════════════════╝"
    echo -e "                             ${DGRAY}v1.7${NC}"

    get_versions
    check_podkop_status
    check_byedpi_status

    echo -e "${MAGENTA}--- ByeDPI ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $BYEDPI_STATUS"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$BYEDPI_LATEST_VER${NC}"
    echo -e "${YELLOW}Текущая стратегия:${NC} ${WHITE}$CURRENT_STRATEGY${NC}"
    echo -e ""
    echo -e "${MAGENTA}--- Podkop ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_STATUS"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$PODKOP_LATEST_VER${NC}"
    echo -e ""
    echo -e "${YELLOW}Архитектура устройства:${NC} $LOCAL_ARCH"
    echo -e ""
    echo -e "${GREEN}1) Установить / обновить ByeDPI${NC}"
    echo -e "${GREEN}2) Удалить ByeDPI${NC}"
    echo -e "${GREEN}3) Интеграция ByeDPI в Podkop${NC}"
    echo -e "${GREEN}4) Изменить стратегию ByeDPI${NC}"
    echo -e "${GREEN}5) Установить / обновить Podkop${NC}"
    echo -e "${GREEN}6) Удалить Podkop${NC}"
    echo -e "${GREEN}7) Установить ByeDPI + Podkop + Интеграция${NC}"
    echo -e "${GREEN}8) Выход (Enter)${NC}"
    echo -e ""
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
# Цикл
# ==========================================
while true; do
    show_menu
done
