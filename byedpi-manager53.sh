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
# Определение версий
# ==========================================
get_versions() {
    # --- ByeDPI ---
    INSTALLED_VER=$(opkg list-installed | grep '^byedpi ' | awk '{print $3}' | sed 's/-r[0-9]\+$//')
    [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | tail -n1 | awk '{print $2}')

    command -v curl >/dev/null 2>&1 || {
        clear
		echo -e ""
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
        LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/^byedpi_([0-9]+\.[0-9]+\.[0-9]+)(-r[0-9]+)?_.*/\1/')
    else
        LATEST_VER="не найдена"
    fi

# --- Podkop ---
    if command -v podkop >/dev/null 2>&1; then
        PODKOP_VER=$(podkop show_version 2>/dev/null | sed 's/-r[0-9]\+$//')
        [ -z "$PODKOP_VER" ] && PODKOP_VER="не найдена"
    else
        PODKOP_VER="не найдена"
    fi
    PODKOP_API_URL="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    PODKOP_LATEST_VER=$(curl -s "$PODKOP_API_URL" | grep '"tag_name"' | head -n1 | cut -d'"' -f4 | sed 's/-r[0-9]\+$//')
    [ -z "$PODKOP_LATEST_VER" ] && PODKOP_LATEST_VER="не найдена"
}

# ==========================================
# Установка / обновление ByeDPI
# ==========================================
install_update() {
    clear
	echo -e ""
    echo -e "${MAGENTA}Установка / обновление ByeDPI${NC}"
    get_versions

    [ -z "$LATEST_URL" ] && {
        echo -e ""
		echo -e "${RED}Последняя версия ByeDPI не найдена. Установка пропущена.${NC}"
        echo -e ""
		read -p "Нажмите Enter..." dummy
        return
    }

    if [ "$INSTALLED_VER" = "$LATEST_VER" ]; then
        echo -e ""
		echo -e "${YELLOW}Уже установлена последняя версия (${CYAN}$INSTALLED_VER${YELLOW})${NC}"
        echo -e ""
		read -p "Нажмите Enter..." dummy
        return
    fi

    echo -e ""
	echo -e "${CYAN}Скачиваем пакет: ${NC}$LATEST_FILE"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return
    curl -L -s -o "$LATEST_FILE" "$LATEST_URL" || {
        echo -e "${RED}Ошибка загрузки ${NC}$LATEST_FILE"
        read -p "Нажмите Enter..." dummy
        return
    }

    echo -e ""
	echo -e "${CYAN}Устанавливаем пакет...${NC}"
    opkg install --force-reinstall "$LATEST_FILE" >/dev/null 2>&1
    rm -rf "$WORKDIR"
	echo -e ""
    echo -e "${GREEN}ByeDPI успешно установлен!${NC}"
	echo -e ""
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Удаление ByeDPI
# ==========================================
uninstall_byedpi() {
    clear
	echo -e ""
    echo -e "${MAGENTA}Удаление ByeDPI${NC}"
    [ -f /etc/init.d/byedpi ] && {
        /etc/init.d/byedpi stop >/dev/null 2>&1
        /etc/init.d/byedpi disable >/dev/null 2>&1
    }
    opkg remove --force-removal-of-dependent-packages byedpi >/dev/null 2>&1
    rm -rf /etc/init.d/byedpi /opt/byedpi /etc/config/byedpi
	echo -e ""
    echo -e "${GREEN}ByeDPI удалён полностью.${NC}"
	echo -e ""
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Установка / обновление Podkop
# ==========================================
install_podkop() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Установка / обновление Podkop${NC}"

    # Получаем актуальные версии перед установкой
    get_versions

    if [ "$PODKOP_LATEST_VER" = "не найдена" ]; then
        echo -e ""
        echo -e "${RED}Последняя версия Podkop не найдена. Установка пропущена.${NC}"
        echo -e ""
        read -p "Нажмите Enter..." dummy
        return
    fi

    # Проверяем, не актуальна ли уже установленная версия
    if [ "$PODKOP_VER" = "$PODKOP_LATEST_VER" ]; then
        echo -e ""
        echo -e "${YELLOW}Уже установлена последняя версия Podkop (${CYAN}$PODKOP_VER${YELLOW}).${NC}"
        echo -e ""
        read -p "Нажмите Enter..." dummy
        return
    fi

    TMPDIR="/tmp/podkop_installer"
    rm -rf "$TMPDIR"
    mkdir -p "$TMPDIR"
    cd "$TMPDIR" || return

    echo -e ""
    echo -e "${CYAN}Скачиваем и запускаем официальный инсталлятор Podkop...${NC}"
    echo -e ""

    if curl -fsSL -o install.sh "https://raw.githubusercontent.com/itdoginfo/podkop/main/install.sh"; then
        chmod +x install.sh
        sh install.sh
        echo -e ""
        echo -e "${GREEN}Podkop установлен / обновлён.${NC}"
    else
        echo -e ""
        echo -e "${RED}Ошибка загрузки установочного скрипта Podkop.${NC}"
    fi

    rm -rf "$TMPDIR"
    echo -e ""
    read -p "Нажмите Enter..." dummy
}
# ==========================================
# Интеграция ByeDPI в Podkop
# ==========================================
integration_byedpi_podkop() {
    clear
	echo -e ""
    echo -e "${MAGENTA}Интеграция ByeDPI в Podkop${NC}"
	echo -e ""

	# Проверяем установлен ли ByeDPI
    if ! command -v byedpi >/dev/null 2>&1 && [ ! -f /etc/init.d/byedpi ]; then
		echo -e "${YELLOW}ByeDPI не установлен.${NC}"
		echo -e ""
        read -p "Нажмите Enter..." dummy
        return
    fi

    uci set dhcp.@dnsmasq[0].localuse='0'
    uci commit dhcp
	/etc/init.d/dnsmasq restart >/dev/null 2>&1

    # Меняем стратегию ByeDPI на интеграционную
    if [ -f /etc/config/byedpi ]; then
        sed -i "s|option cmd_opts .*| option cmd_opts '-o2 --auto=t,r,a,s -d2'|" /etc/config/byedpi
    fi

    # Создаём / меняем /etc/config/podkop
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
	echo -e ""
    echo -e "${GREEN}ByeDPI интегрирован в Podkop.${NC}"
	echo -e ""
    echo -ne "Нужно ${RED}обязательно${NC} перезагрузить роутер. Перезагрузить сейчас? [y/N]: "
	echo -e ""
    read REBOOT_CHOICE
    case "$REBOOT_CHOICE" in
	y|Y)
		echo -e ""
        echo -e "${GREEN}Перезагрузка роутера...${NC}"
        reboot
        ;;
    *) 
        echo -e "${YELLOW}Необходимость перезагрузки отложена.${NC}" 
        ;;
esac
echo -e ""
read -p "Нажмите Enter..." dummy
}

# ==========================================
# Измениние стратегии ByeDP
# ==========================================
fix_strategy() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Измениние стратегии ByeDPI${NC}"

    if [ -f /etc/config/byedpi ]; then
        # Получаем текущую стратегию
        CURRENT_STRATEGY=$(grep "option cmd_opts" /etc/config/byedpi | sed -E "s/.*'(.+)'/\1/")
        [ -z "$CURRENT_STRATEGY" ] && CURRENT_STRATEGY="(не задана)"
        echo -e ""
        echo -e "${CYAN}Текущая стратегия:${NC} ${WHITE}$CURRENT_STRATEGY${NC}"
        echo -e ""
        read -p "Введите новую стратегию (Enter — оставить текущую): " NEW_STRATEGY
        echo -e ""
        if [ -z "$NEW_STRATEGY" ]; then
            echo -e "${YELLOW}Стратегия не изменена. Оставлена текущая:${NC} ${WHITE}$CURRENT_STRATEGY${NC}"
        else
            sed -i "s|option cmd_opts .*|    option cmd_opts '$NEW_STRATEGY'|" /etc/config/byedpi
            start_byedpi
            echo -e ""
            echo -e "${GREEN}Стратегия изменена на:${NC} ${WHITE}$NEW_STRATEGY${NC}"
        fi
    else
		echo -e ""
        echo -e "${YELLOW}ByeDPI не установлен.${NC}"
    fi
    echo -e ""
    read -p "Нажмите Enter..." dummy
}

# ==========================================
# Удаление Podkop
# ==========================================
uninstall_podkop() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Удаление Podkop${NC}"
    opkg remove luci-i18n-podkop-ru luci-app-podkop podkop --autoremove >/dev/null 2>&1 || true
    rm -rf /etc/config/podkop /tmp/podkop_installer
    echo -e ""
    echo -e "${GREEN}Podkop удалён полностью.${NC}"
    echo -e ""
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

# ==========================================	
# Получаем текущую стратегию ByeDPI
# ==========================================
if [ -f /etc/config/byedpi ]; then
    CURRENT_STRATEGY=$(grep "option cmd_opts" /etc/config/byedpi | sed -E "s/.*'(.+)'/\1/")
    [ -z "$CURRENT_STRATEGY" ] && CURRENT_STRATEGY="(не задана)"
else
    CURRENT_STRATEGY="не найдена"
fi
# ==========================================
# Получаем модель роутера
# ==========================================
	MODEL=$(cat /tmp/sysinfo/model 2>/dev/null)
	[ -z "$MODEL" ] && MODEL="не определено"

	clear
	echo -e ""
	echo -e "${BLUE}--- Podkop+ByeDPI Manager ---${NC}"
	echo -e ""
    echo -e "${MAGENTA}--- ByeDPI ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $INSTALLED_VER"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$LATEST_VER${NC}"
	echo -e "${YELLOW}Текущая стратегия:${NC} ${WHITE}$CURRENT_STRATEGY${NC}"
	echo -e ""
    echo -e "${MAGENTA}--- Podkop ---${NC}"
    echo -e "${YELLOW}Установленная версия:${NC} $PODKOP_VER"
    echo -e "${YELLOW}Последняя версия:${NC} ${CYAN}$PODKOP_LATEST_VER${NC}"
	echo -e ""
	echo -e "${YELLOW}Модель и архитектура роутера:${NC} $MODEL / $LOCAL_ARCH"
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
# Запуск
# ==========================================
while true; do
    show_menu
done
