#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# Скрипт для установки, обновления и полного удаления Zapret на OpenWRT
# ==========================================

# Проверка на root
if [ "$(id -u)" != "0" ]; then
    echo "Этот скрипт должен запускаться от root!"
    exit 1
fi

# Включаем строгий режим
set -euo pipefail

# Цвета для вывода
GREEN="\033[1;32m"       # Зеленый для успешных действий и статусов
RED="\033[1;31m"         # Красный для ошибок или остановленных процессов
CYAN="\033[1;36m"        # Голубой для информационных сообщений
YELLOW="\033[1;33m"      # Желтый для подчеркивания важных данных
MAGENTA="\033[1;35m"     # Фиолетовый для заголовков и названия скрипта
BLUE="\033[0;34m"        # Синий для завершения действий
NC="\033[0m"             # Сброс цвета
GRAY='\033[38;5;239m'    # Темно-серый для ссылок
DGRAY='\033[38;5;236m'   # Очень темный серый для версии

# ==========================================
# Вспомогательные функции
# ==========================================
install_if_missing() {
    local pkg="$1"
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo -e "${GREEN}🔴 ${CYAN}Устанавливаем${NC} $pkg ${CYAN}для необходимых операций${NC}"
        opkg update >/dev/null 2>&1 || { echo -e "${RED}Ошибка обновления opkg! Проверьте интернет.${NC}"; exit 1; }
        opkg install "$pkg" >/dev/null 2>&1 || { echo -e "${RED}Ошибка установки $pkg!${NC}"; exit 1; }
    fi
}

stop_zapret() {
    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Останавливаем сервис ${NC}zapret"
        /etc/init.d/zapret stop >/dev/null 2>&1
    fi
    local PIDS=$(pgrep -f /opt/zapret/bin || true)
    if [ -n "$PIDS" ]; then
        echo -e "${GREEN}🔴 ${CYAN}Убиваем все процессы ${NC}zapret"
        for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
    fi
}

restart_zapret() {
    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Перезапуск службы ${NC}zapret"
        chmod +x /opt/zapret/sync_config.sh >/dev/null 2>&1
        /opt/zapret/sync_config.sh >/dev/null 2>&1
        /etc/init.d/zapret restart >/dev/null 2>&1
    fi
}

# ==========================================
# Функция получения информации о версиях, архитектуре и статусе
# ==========================================
get_versions() {
    INSTALLED_VER=$(opkg info zapret | grep Version | awk '{print $2}' || echo "не найдена")
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "неизвестна")
    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release || opkg print-architecture | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}' || echo "неизвестна")

    install_if_missing curl

    LATEST_URL=$(curl -s --fail https://api.github.com/repos/remittor/zapret-openwrt/releases/latest \
        | grep browser_download_url | grep "$LOCAL_ARCH.zip" | cut -d '"' -f 4) || true
    PREV_URL=$(curl -s --fail https://api.github.com/repos/remittor/zapret-openwrt/releases \
        | grep browser_download_url | grep "$LOCAL_ARCH.zip" | sed -n '2p' | cut -d '"' -f 4) || true

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

# ==========================================
# Установка или обновление Zapret
# ==========================================
install_update() {
    local TARGET="$1"
    clear
    echo -e ""
    if [ "$INSTALLED_VER" != "не найдена" ]; then
        echo -e "${MAGENTA}Обновляем ZAPRET${NC}"
        ACTION="update"
    else
        echo -e "${MAGENTA}Устанавливаем ZAPRET${NC}"
        ACTION="install"
    fi
    echo -e ""
    get_versions

    if [ "$TARGET" = "prev" ]; then
        TARGET_URL="$PREV_URL"
        TARGET_FILE="$PREV_FILE"
        TARGET_VER="$PREV_VER"
    else
        TARGET_URL="$LATEST_URL"
        TARGET_FILE="$LATEST_FILE"
        TARGET_VER="$LATEST_VER"
    fi

    if [ "$USED_ARCH" = "нет пакета для вашей архитектуры" ]; then
        echo -e "${RED}Нет доступного пакета для вашей архитектуры: ${NC}$LOCAL_ARCH"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return
    fi

    if [ "$INSTALLED_VER" = "$TARGET_VER" ]; then
        echo -e "${BLUE}🔴 ${GREEN}Эта версия уже установлена!${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return
    fi

    stop_zapret

    WORKDIR=$(mktemp -d /tmp/zapret-update.XXXXXX)
    cd "$WORKDIR" || return
    echo -e "${GREEN}🔴 ${CYAN}Скачиваем архив ${NC}$TARGET_FILE"
    install_if_missing curl
    curl -s -o "$TARGET_FILE" "$TARGET_URL" --max-time 30 || {
        echo -e "${RED}Не удалось скачать ${NC}$TARGET_FILE"
        rm -rf "$WORKDIR"
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return
    }

    install_if_missing unzip

    echo -e "${GREEN}🔴 ${CYAN}Распаковываем архив${NC}"
    unzip -o "$TARGET_FILE" >/dev/null

    for PKG in zapret_*.ipk luci-app-zapret_*.ipk; do
        if [ -f "$PKG" ]; then
            echo -e "${GREEN}🔴 ${CYAN}Устанавливаем пакет ${NC}$PKG"
            opkg install --force-reinstall "$PKG" >/dev/null 2>&1
        fi
    done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы${NC}"
    cd /
    rm -rf "$WORKDIR"

    restart_zapret

    echo -e ""
    if [ "$ACTION" = "update" ]; then
        echo -e "${BLUE}🔴 ${GREEN}Zapret успешно обновлён!${NC}"
    else
        echo -e "${BLUE}🔴 ${GREEN}Zapret успешно установлен!${NC}"
    fi
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Исправление дефолтной стратегии
# ==========================================
fix_default() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Исправляем стратегию по умолчанию${NC}"
    echo -e ""

    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен!${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return
    fi

    # Убираем fake в dpi-desync
    sed -i '/--dpi-desync=/s/fake,//g' /etc/config/zapret

    # Удаляем конкретный блок, если он существует
    if grep -q '--filter-tcp=80 <HOSTLIST>' /etc/config/zapret; then
        sed -i '/--filter-tcp=80 <HOSTLIST>/,/--new/d' /etc/config/zapret
    fi

    restart_zapret

    echo -e "${BLUE}🔴 ${GREEN}Стратегия по умолчанию исправлена!${NC}"
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Включение Discord и звонков в TG и WA
# ==========================================
enable_discord_calls() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Включаем Discord и звонки в TG и WA${NC}"
    echo -e ""

    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен!${NC}"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return
    fi

    CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
    CURRENT_SCRIPT="не установлен"
    if [ -f "$CUSTOM_DIR/50-script.sh" ]; then
        FIRST_LINE=$(sed -n '1p' "$CUSTOM_DIR/50-script.sh")
        if echo "$FIRST_LINE" | grep -q "QUIC"; then
            CURRENT_SCRIPT="50-quic4all"
        elif echo "$FIRST_LINE" | grep -q "stun"; then
            CURRENT_SCRIPT="50-stun4all"
        else
            CURRENT_SCRIPT="неизвестный"
        fi
    fi

    echo -e "${YELLOW}Текущий установленный скрипт:${NC} $CURRENT_SCRIPT"
    echo -e ""

    echo -e "${CYAN}1) ${GREEN}Установить скрипт ${NC}50-stun4all"
    echo -e "${CYAN}2) ${GREEN}Установить скрипт ${NC}50-quic4all"
    echo -e "${CYAN}3) ${GREEN}Удалить текущий скрипт (если установлен)${NC}"
    echo -e "${CYAN}4) ${GREEN}Выход в главное меню (Enter)${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice

    case "$choice" in
        1)
            SELECTED="50-stun4all"
            URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-stun4all"
            ;;
        2)
            SELECTED="50-quic4all"
            URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-quic4all"
            ;;
        3)
            if [ "$CURRENT_SCRIPT" != "не установлен" ]; then
                rm -f "$CUSTOM_DIR/50-script.sh"
                echo -e "${GREEN}🔴 ${CYAN}Скрипт удалён!${NC}"
                restart_zapret
            else
                echo -e "${RED}Нет скрипта для удаления!${NC}"
            fi
            echo -e ""
            read -p "Нажмите Enter для продолжения..." dummy
            return
            ;;
        4|"")
            echo -e ""
            echo -e "${GREEN}Выходим в главное меню${NC}"
            return
            ;;
        *)
            echo -e ""
            echo -e "${GREEN}Выходим в главное меню${NC}"
            return
            ;;
    esac

    if [ "$CURRENT_SCRIPT" = "$SELECTED" ]; then
        echo -e ""
        echo -e "${RED}Выбранный скрипт уже установлен!${NC}"
    else
        mkdir -p "$CUSTOM_DIR"
        if curl -fsSLo "$CUSTOM_DIR/50-script.sh" "$URL"; then
            echo -e ""
            echo -e "${GREEN}🔴 ${CYAN}Скрипт ${NC}$SELECTED${CYAN} успешно установлен!${NC}"
        else
            echo -e ""
            echo -e "${RED}Ошибка при скачивании скрипта!${NC}"
            echo -e ""
            read -p "Нажмите Enter для продолжения..." dummy
            return
        fi
    fi

    # Добавляем блок UDP, если его нет
    if ! grep -q -- "--filter-udp=50000-50099" /etc/config/zapret; then
        if ! grep -q '50000-50099' /etc/config/zapret; then
            sed -i "/NFQWS_PORTS_UDP/s/'443'/'443,50000-50099'/" /etc/config/zapret
        fi
        sed -i "/^'$/d" /etc/config/zapret
        printf -- '--new\n--filter-udp=50000-50099\n--filter-l7=discord,stun\n--dpi-desync=fake\n' >> /etc/config/zapret
        echo "'" >> /etc/config/zapret
    fi

    restart_zapret
    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Звонки и Discord включены!${NC}"
    echo -e ""
    read -p "Нажмите Enter для продолжения..." dummy
}

# ==========================================
# Полное удаление Zapret
# ==========================================
uninstall_zapret() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Удаляем ZAPRET${NC}"
    echo -e ""

    stop_zapret

    echo -e "${GREEN}🔴 ${CYAN}Удаляем пакеты${NC} zapret ${CYAN}и ${NC}luci-app-zapret"
    opkg remove --force-removal-of-dependent-packages --autoremove zapret luci-app-zapret >/dev/null 2>&1 || true

    echo -e "${GREEN}🔴 ${CYAN}Удаляем конфигурации и рабочие папки${NC}"
    rm -rf /opt/zapret /etc/config/zapret /etc/firewall.zapret >/dev/null 2>&1

    if crontab -l | grep -q -i "zapret"; then
        echo -e "${GREEN}🔴 ${CYAN}Очищаем${NC} crontab ${CYAN}задания${NC}"
        crontab -l | grep -v -i "zapret" | crontab -
    fi

    echo -e "${GREEN}🔴 ${CYAN}Удаляем${NC} ipset"
    for set in $(ipset list -n 2>/dev/null | grep -i zapret || true); do ipset destroy "$set" >/dev/null 2>&1; done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы${NC}"
    rm -rf /tmp/*zapret* /var/run/*zapret* 2>/dev/null

    echo -e "${GREEN}🔴 ${CYAN}Удаляем цепочки и таблицы${NC} nftables"
    for table in $(nft list tables 2>/dev/null | awk '{print $2}' || true); do
        if nft list table "$table" 2>/dev/null | grep -q zapret; then
            nft delete table "$table" >/dev/null 2>&1
        fi
    done

    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Zapret полностью удалён!${NC}"
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Главное меню
# ==========================================
show_menu() {
    get_versions

    clear
    echo -e ""
    echo -e "${YELLOW}Модель и архитектура роутера:${NC} $MODEL / $LOCAL_ARCH"
    echo -e ""
    echo -e "╔════════════════════════════════════╗"
    echo -e "║     ${BLUE}Zapret on remittor Manager${NC}     ║"
    echo -e "╚════════════════════════════════════╝"
    echo -e "                                  ${DGRAY}v2.4${NC}"

    if [ "$INSTALLED_VER" = "$LATEST_VER" ] && [ "$LATEST_VER" != "не найдена" ]; then
        INST_COLOR=$GREEN
        INSTALLED_DISPLAY="$INSTALLED_VER (актуальная)"
    elif [ "$LATEST_VER" = "не найдена" ]; then
        INST_COLOR=$CYAN
        INSTALLED_DISPLAY="$INSTALLED_VER"
    elif [ "$INSTALLED_VER" != "не найдена" ]; then
        INST_COLOR=$RED
        INSTALLED_DISPLAY="$INSTALLED_VER (устарела)"
    else
        INST_COLOR=$RED
        INSTALLED_DISPLAY="$INSTALLED_VER"
    fi

    echo -e ""
    echo -e "${YELLOW}Установленная версия: ${INST_COLOR}$INSTALLED_DISPLAY${NC}"
    echo -e ""
    echo -e "${YELLOW}Последняя версия на GitHub: ${CYAN}$LATEST_VER${NC}"
    echo -e ""
    echo -e "${YELLOW}Предыдущая версия: ${CYAN}$PREV_VER${NC}"
    echo -e ""
    echo -e "${YELLOW}Архитектура устройства:${NC} $LOCAL_ARCH"

    [ -n "$ZAPRET_STATUS" ] && echo -e "\n${YELLOW}Статус Zapret: ${NC}$ZAPRET_STATUS"

    CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
    CURRENT_SCRIPT=""
    if [ -f "$CUSTOM_DIR/50-script.sh" ]; then
        FIRST_LINE=$(sed -n '1p' "$CUSTOM_DIR/50-script.sh")
        if echo "$FIRST_LINE" | grep -q "QUIC"; then
            CURRENT_SCRIPT="50-quic4all"
        elif echo "$FIRST_LINE" | grep -q "stun"; then
            CURRENT_SCRIPT="50-stun4all"
        fi
    fi
    [ -n "$CURRENT_SCRIPT" ] && echo -e "\n${YELLOW}Установлен скрипт: ${NC}$CURRENT_SCRIPT"

    echo -e ""

    echo -e "${CYAN}1) ${GREEN}Установить/обновить до последней версии${NC}"
    echo -e "${CYAN}2) ${GREEN}Установить предыдущую версию${NC}"
    echo -e "${CYAN}3) ${GREEN}Исправить стратегию по умолчанию${NC}"
    echo -e "${CYAN}4) ${GREEN}Вернуть настройки по умолчанию${NC}"
    echo -e "${CYAN}5) ${GREEN}Остановить ${NC}Zapret"
    echo -e "${CYAN}6) ${GREEN}Запустить ${NC}Zapret"
    echo -e "${CYAN}7) ${GREEN}Удалить ${NC}Zapret"
    echo -e "${CYAN}8) ${GREEN}Включить ${NC}Discord${GREEN} и звонки в ${NC}TG${GREEN} и ${NC}WA ${RED}(test)${NC}"
    echo -e "${CYAN}9) ${GREEN}Выход (Enter)${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice
    case "$choice" in
        1) install_update "latest"; show_menu ;;
        2) install_update "prev"; show_menu ;;
        3) fix_default; show_menu ;;
        4)
            clear
            echo -e ""
            echo -e "${MAGENTA}Возвращаем настройки по умолчанию${NC}"
            echo -e ""
            if [ -f /opt/zapret/restore-def-cfg.sh ]; then
                rm -f /opt/zapret/init.d/openwrt/custom.d/50-script.sh >/dev/null 2>&1
                stop_zapret
                chmod +x /opt/zapret/restore-def-cfg.sh
                /opt/zapret/restore-def-cfg.sh
                restart_zapret
                echo -e "${BLUE}🔴 ${GREEN}Настройки возвращены, сервис перезапущен!${NC}"
            else
                echo -e "${RED}Zapret не установлен!${NC}"
            fi
            echo -e ""
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            show_menu
            ;;
        5)
            clear
            echo -e ""
            echo -e "${MAGENTA}Останавливаем Zapret${NC}"
            echo -e ""
            if [ -f /etc/init.d/zapret ]; then
                stop_zapret
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Zapret остановлен!${NC}"
            else
                echo -e "${RED}Zapret не установлен!${NC}"
            fi
            echo -e ""
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            show_menu
            ;;
        6)
            clear
            echo -e ""
            echo -e "${MAGENTA}Запускаем Zapret${NC}"
            echo -e ""
            if [ -f /etc/init.d/zapret ]; then
                /etc/init.d/zapret start >/dev/null 2>&1
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Zapret запущен!${NC}"
            else
                echo -e "${RED}Zapret не установлен!${NC}"
            fi
            echo -e ""
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            show_menu
            ;;
        7) uninstall_zapret; show_menu ;;
        8) enable_discord_calls; show_menu ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Старт скрипта
# ==========================================
show_menu
