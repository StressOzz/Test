#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# Скрипт для установки, обновления и полного удаления Zapret на OpenWRT
# ==========================================

# ===============================
# Цвета для вывода
# ===============================
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
GRAY='\033[38;5;239m'
DGRAY='\033[38;5;236m'

# ===============================
# Рабочая директория
# ===============================
WORKDIR="/tmp/zapret-update"

# ===============================
# Вспомогательные функции
# ===============================
pause() {
    read -p "Нажмите Enter для продолжения..." dummy
}

stop_zapret() {
    [ -f /etc/init.d/zapret ] && /etc/init.d/zapret stop >/dev/null 2>&1
    PIDS=$(pgrep -f /opt/zapret)
    [ -n "$PIDS" ] && for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
}

ensure_tools() {
    command -v curl >/dev/null 2>&1 || { echo -e "${GREEN}🔴 ${CYAN}Устанавливаем curl${NC}"; opkg update >/dev/null 2>&1; opkg install curl >/dev/null 2>&1; }
    command -v unzip >/dev/null 2>&1 || { echo -e "${GREEN}🔴 ${CYAN}Устанавливаем unzip${NC}"; opkg update >/dev/null 2>&1; opkg install unzip >/dev/null 2>&1; }
}

get_versions() {
    INSTALLED_VER=$(opkg list-installed | grep '^zapret ' | awk '{print $3}'); [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"
    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}')
    ensure_tools
    LATEST_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases/latest | grep browser_download_url | grep "$LOCAL_ARCH.zip" | cut -d '"' -f 4)
    PREV_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases | grep browser_download_url | grep "$LOCAL_ARCH.zip" | sed -n '2p' | cut -d '"' -f 4)

    if [ -n "$LATEST_URL" ] && echo "$LATEST_URL" | grep -q '\.zip$'; then
        LATEST_FILE=$(basename "$LATEST_URL")
        LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
        USED_ARCH="$LOCAL_ARCH"
    else
        LATEST_VER="не найдена"
        USED_ARCH="нет пакета для вашей архитектуры"
    fi

    if [ -n "$PREV_URL" ] && echo "$PREV_URL" | grep -q '\.zip$'; then
        PREV_FILE=$(basename "$PREV_URL")
        PREV_VER=$(echo "$PREV_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
    else
        PREV_VER="не найдена"
    fi

    if [ -f /etc/init.d/zapret ]; then
        if /etc/init.d/zapret status 2>/dev/null | grep -qi "running"; then
            ZAPRET_STATUS="${GREEN}запущен${NC}"
        else
            ZAPRET_STATUS="${RED}остановлен${NC}"
        fi
    else
        ZAPRET_STATUS=""
    fi
}

install_or_update() {
    TARGET_URL="$1"
    TARGET_FILE=$(basename "$TARGET_URL")
    TARGET_VER="$2"

    clear; echo -e "${MAGENTA}Начинаем установку ZAPRET${NC}\n"
    get_versions

    [ "$USED_ARCH" = "нет пакета для вашей архитектуры" ] && { echo -e "${RED}Нет пакета для вашей архитектуры: $LOCAL_ARCH${NC}"; pause; return; }
    [ "$INSTALLED_VER" = "$TARGET_VER" ] && { echo -e "${BLUE}🔴 ${GREEN}Эта версия уже установлена!${NC}"; pause; return; }

    stop_zapret

    mkdir -p "$WORKDIR" && cd "$WORKDIR" || return
    echo -e "${GREEN}🔴 ${CYAN}Скачиваем архив ${NC}$TARGET_FILE"
    wget -q "$TARGET_URL" -O "$TARGET_FILE" || { echo -e "${RED}Не удалось скачать $TARGET_FILE${NC}"; pause; return; }

    echo -e "${GREEN}🔴 ${CYAN}Распаковываем архив${NC}"
    unzip -o "$TARGET_FILE" >/dev/null

    stop_zapret

    for PKG in zapret_*.ipk luci-app-zapret_*.ipk; do
        [ -f "$PKG" ] && { echo -e "${GREEN}🔴 ${CYAN}Устанавливаем пакет ${NC}$PKG"; opkg install --force-reinstall "$PKG" >/dev/null 2>&1; }
    done

    cd /; rm -rf "$WORKDIR"; rm -f /tmp/*.ipk /tmp/*.zip /tmp/*zapret* 2>/dev/null

    [ -f /etc/init.d/zapret ] && { chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1; }

    echo -e "\n${BLUE}🔴 ${GREEN}Zapret успешно установлен/обновлён версия $TARGET_VER!${NC}\n"
    pause
}

choose_version() {
    clear; echo -e "${MAGENTA}Последние 10 версий Zapret${NC}\n"
    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}')
    RELEASES=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases | grep '"tag_name"' | grep -Eo '[0-9]+\.[0-9]+[0-9]*' | head -n 10)

    [ -z "$RELEASES" ] && { echo -e "${RED}Не удалось получить список версий${NC}"; pause; return; }

    i=1
    echo "$RELEASES" | while read ver; do
        LABEL=""
        COLOR="$NC"
        [ "$ver" = "$LATEST_VER" ] && { LABEL="- последняя"; COLOR="$GREEN"; }
        [ "$ver" = "$INSTALLED_VER" ] && { [ -n "$LABEL" ] && LABEL="$LABEL, "; LABEL="$LABEL- установленная"; [ "$COLOR" = "$NC" ] && COLOR="$CYAN"; }
        echo -e "${GREEN}$i) ${COLOR}$ver $LABEL${NC}"; i=$((i+1))
    done

    echo -n "Введите номер пункта для установки (или Enter для выхода меню): "
    read num; [ -z "$num" ] && return
    SELECTED=$(echo "$RELEASES" | sed -n "${num}p")
    [ -z "$SELECTED" ] && { echo -e "${RED}Неверный номер${NC}"; sleep 2; return; }

    TARGET_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases | grep browser_download_url | grep "$SELECTED" | grep "$LOCAL_ARCH.zip" | cut -d'"' -f4)
    [ -z "$TARGET_URL" ] && { echo -e "${RED}Не найден пакет для вашей архитектуры${NC}"; pause; return; }

    install_or_update "$TARGET_URL" "$SELECTED"
}

uninstall_zapret() {
    clear; echo -e "${MAGENTA}Начинаем удаление ZAPRET${NC}\n"
    stop_zapret
    echo -e "${GREEN}🔴 ${CYAN}Удаляем пакеты${NC} zapret и luci-app-zapret"
    opkg remove --force-removal-of-dependent-packages zapret luci-app-zapret >/dev/null 2>&1
    echo -e "${GREEN}🔴 ${CYAN}Удаляем конфигурации и рабочие папки${NC}"
    for path in /opt/zapret /etc/config/zapret /etc/firewall.zapret; do [ -e "$path" ] && rm -rf "$path"; done
    crontab -l 2>/dev/null | grep -v -i "zapret" | crontab -
    for set in $(ipset list -n 2>/dev/null | grep -i zapret); do ipset destroy "$set" >/dev/null 2>&1; done
    rm -f /tmp/*zapret* /var/run/*zapret* 2>/dev/null
    for table in $(nft list tables 2>/dev/null | awk '{print $2}'); do chains=$(nft list table "$table" 2>/dev/null | grep zapret); [ -n "$chains" ] && nft delete table "$table" >/dev/null 2>&1; done
    echo -e "\n${BLUE}🔴 ${GREEN}Zapret полностью удалён!${NC}\n"
    pause
}

# ===============================
# Главное меню
# ===============================
show_menu() {
    get_versions
    clear
    echo -e "███████╗ █████╗ ██████╗ ██████╗ ███████╗████████╗"
    echo -e "╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝"
    echo -e "  ███╔╝ ███████║██████╔╝██████╔╝█████╗     ██║   "
    echo -e " ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██╔══╝     ██║   "
    echo -e "███████╗██║  ██║██║     ██║  ██║███████╗   ██║   "
    echo -e "╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝   "
    echo -e "              ${MAGENTA}on remittor Manager by StressOzz${NC}"
    echo -e "                                          ${DGRAY}v1.7${NC}"
    echo -e "${GRAY}https://github.com/bol-van/zapret${NC}"
    echo -e "${GRAY}https://github.com/remittor/zapret-openwrt${NC}\n"

    [ "$INSTALLED_VER" = "$LATEST_VER" ] && INST_COLOR=$GREEN || INST_COLOR=$RED
    [ "$INSTALLED_VER" = "$LATEST_VER" ] && INSTALLED_DISPLAY="$INSTALLED_VER (актуальная)" || ([ "$INSTALLED_VER" != "не найдена" ] && INSTALLED_DISPLAY="$INSTALLED_VER (устарела)" || INSTALLED_DISPLAY="$INSTALLED_VER")
    [ "$INSTALLED_VER" = "не найдена" ] && MENU1_TEXT="Установить последнюю версию" || ([ "$INSTALLED_VER" = "$LATEST_VER" ] && MENU1_TEXT="Установить последнюю версию" || MENU1_TEXT="Обновить до последней версии")

    echo -e "${YELLOW}Установленная версия: ${INST_COLOR}$INSTALLED_DISPLAY${NC}"
    echo -e "${YELLOW}Последняя версия на GitHub: ${NC}$LATEST_VER"
    echo -e "${YELLOW}Архитектура устройства: ${NC}$LOCAL_ARCH\n"
    [ -n "$ZAPRET_STATUS" ] && echo -e "${YELLOW}Статус Zapret: ${NC}$ZAPRET_STATUS\n"

    echo -e "${GREEN}1) $MENU1_TEXT${NC}"
    echo -e "${GREEN}2) Меню версий для установки${NC}"
    echo -e "${GREEN}3) Вернуть настройки по умолчанию${NC}"
    echo -e "${GREEN}4) Остановить Zapret${NC}"
    echo -e "${GREEN}5) Запустить Zapret${NC}"
    echo -e "${GREEN}6) Удалить Zapret${NC}"
    echo -e "${GREEN}7) Выход (Enter)${NC}\n"
    echo -n "Выберите пункт: "
    read choice
    case "$choice" in
        1) install_or_update "$LATEST_URL" "$LATEST_VER" ;;
        2) choose_version ;;
        3)
            clear; echo -e "${MAGENTA}Возврат к настройкам по умолчанию${NC}\n"
            if [ -f /opt/zapret/restore-def-cfg.sh ]; then
                stop_zapret
                chmod +x /opt/zapret/restore-def-cfg.sh
                /opt/zapret/restore-def-cfg.sh
                chmod +x /opt/zapret/sync_config.sh
                /opt/zapret/sync_config.sh
                [ -f /etc/init.d/zapret ] && /etc/init.d/zapret restart >/dev/null 2>&1
                echo -e "${BLUE}🔴 ${GREEN}Настройки возвращены, сервис перезапущен!${NC}\n"
            else
                echo -e "${RED}Zapret не установлен!${NC}\n"
            fi
            pause; show_menu ;;
        4) stop_zapret; echo -e "${BLUE}🔴 ${GREEN}Zapret остановлен!${NC}\n"; pause ;;
        5)
            [ -f /etc/init.d/zapret ] && /etc/init.d/zapret start >/dev/null 2>&1 && echo -e "${BLUE}🔴 ${GREEN}Zapret запущен!${NC}\n" || echo -e "${RED}Zapret не установлен!${NC}\n"
            pause ;;
        6) uninstall_zapret ;;
        *) exit 0 ;;
    esac
}

# ===============================
# Старт скрипта
# ===============================
while true; do
    show_menu
done
