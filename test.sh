#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# Скрипт для установки, обновления и полного удаления Zapret на OpenWRT
# ==========================================

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

# Рабочая директория для скачивания и распаковки
WORKDIR="/tmp/zapret-update"  # Временная папка для загрузки архивов
LOGFILE="/tmp/zapret_manager.log"  # Лог-файл для отладки

# ==========================================
# Функция логирования
# ==========================================
log_message() {
    echo "$(date): $1" >> "$LOGFILE"
}

# ==========================================
# Проверка подключения к интернету
# ==========================================
check_internet() {
    ping -c 1 8.8.8.8 >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка: отсутствует подключение к интернету${NC}"
        log_message "Ошибка: отсутствует подключение к интернету"
        return 1
    fi
    return 0
}

# ==========================================
# Проверка свободного места
# ==========================================
check_free_space() {
    FREE_SPACE=$(df -h /tmp | tail -n1 | awk '{print $4}' | grep -o '[0-9]\+')
    if [ -z "$FREE_SPACE" ] || [ "$FREE_SPACE" -lt 50 ]; then
        echo -e "${RED}Недостаточно свободного места в /tmp${NC}"
        log_message "Ошибка: недостаточно свободного места в /tmp"
        return 1
    fi
    return 0
}

# ==========================================
# Функция получения информации о версиях, архитектуре и статусе
# ==========================================
get_versions() {
    INSTALLED_VER=$(opkg list-installed | grep '^zapret ' | awk '{print $3}')
    [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"

    LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}')
    if [ -z "$LOCAL_ARCH" ]; then
        echo -e "${RED}Ошибка: не удалось определить архитектуру устройства${NC}"
        log_message "Ошибка: не удалось определить архитектуру устройства"
        return 1
    fi

    command -v curl >/dev/null 2>&1 || {
        echo -e "${GREEN}🔴 ${CYAN}Устанавливаем${NC} curl ${CYAN}для загрузки информации с GitHub${NC}"
        log_message "Установка curl"
        opkg update >/dev/null 2>&1
        opkg install curl >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка: не удалось установить curl${NC}"
            log_message "Ошибка: не удалось установить curl"
            return 1
        fi
    }

    # Проверка лимита GitHub API
    LIMIT_REACHED=0
    LIMIT_CHECK=$(curl -s "https://api.github.com/repos/remittor/zapret-openwrt/releases/latest")
    if echo "$LIMIT_CHECK" | grep -q 'API rate limit exceeded'; then
        LATEST_VER="${RED}Достигнут лимит GitHub API. Подождите 15 минут.${NC}"
        LIMIT_REACHED=1
        log_message "Достигнут лимит GitHub API"
    else
        LATEST_URL=$(echo "$LIMIT_CHECK" | grep browser_download_url | grep "$LOCAL_ARCH.zip" | cut -d '"' -f 4)
        if [ -n "$LATEST_URL" ] && echo "$LATEST_URL" | grep -q '\.zip$'; then
            LATEST_FILE=$(basename "$LATEST_URL")
            LATEST_VER=$(echo "$LATEST_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
            USED_ARCH="$LOCAL_ARCH"
        else
            LATEST_VER="не найдена"
            USED_ARCH="нет пакета для вашей архитектуры"
            log_message "Нет пакета для архитектуры $LOCAL_ARCH"
        fi
    fi

    # Предыдущая версия
    PREV_URL=$(curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases \
        | grep browser_download_url | grep "$LOCAL_ARCH.zip" | sed -n '2p' | cut -d '"' -f 4)
    if [ -n "$PREV_URL" ] && echo "$PREV_URL" | grep -q '\.zip$'; then
        PREV_FILE=$(basename "$PREV_URL")
        PREV_VER=$(echo "$PREV_FILE" | sed -E 's/.*zapret_v([0-9]+\.[0-9]+)_.*\.zip/\1/')
    else
        PREV_VER="не найдена"
    fi

    # Статус службы
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
# Установка Zapret
# ==========================================
install_update() {
    local NO_PAUSE=$1
    [ "$NO_PAUSE" != "1" ] && clear
    [ "$NO_PAUSE" != "1" ] && echo -e ""

    echo -e "${MAGENTA}Устанавливаем ZAPRET${NC}"
    echo -e ""
    log_message "Начало установки/обновления Zapret"

    # Проверка интернета и свободного места
    check_internet || { [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
    check_free_space || { [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }

    get_versions || { [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }

    # Проверка лимита API
    if [ "$LIMIT_REACHED" -eq 1 ]; then
        echo -e "$LATEST_VER"
        echo -e ""
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    # Проверка архитектуры
    if [ -z "$USED_ARCH" ] || [ "$USED_ARCH" = "нет пакета для вашей архитектуры" ]; then
        echo -e "${RED}Нет доступного пакета для вашей архитектуры: ${NC}$LOCAL_ARCH"
        echo -e ""
        log_message "Нет пакета для архитектуры $LOCAL_ARCH"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    # Всегда последняя версия
    TARGET_URL="$LATEST_URL"
    TARGET_FILE="$LATEST_FILE"
    TARGET_VER="$LATEST_VER"

    if [ "$INSTALLED_VER" = "$TARGET_VER" ]; then
        echo -e "${BLUE}🔴 ${GREEN}Последняя версия уже установлена !${NC}"
        echo -e ""
        log_message "Последняя версия $INSTALLED_VER уже установлена"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 0
    fi

    # Остановка службы
    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Останавливаем сервис ${NC}zapret"
        /etc/init.d/zapret stop >/dev/null 2>&1
        PIDS=$(pgrep -f /opt/zapret)
        if [ -n "$PIDS" ]; then
            echo -e "${GREEN}🔴 ${CYAN}Пытаемся мягко завершить процессы ${NC}zapret"
            for pid in $PIDS; do kill -15 "$pid" >/dev/null 2>&1; done
            sleep 2
            PIDS=$(pgrep -f /opt/zapret)
            if [ -n "$PIDS" ]; then
                echo -e "${GREEN}🔴 ${CYAN}Принудительно завершаем процессы ${NC}zapret"
                for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
            fi
        fi
    fi

    mkdir -p "$WORKDIR"
    rm -rf "$WORKDIR"/* 2>/dev/null
    cd "$WORKDIR" || { echo -e "${RED}Ошибка: не удалось перейти в $WORKDIR${NC}"; log_message "Ошибка: не удалось перейти в $WORKDIR"; [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }

    echo -e "${GREEN}🔴 ${CYAN}Скачиваем архив ${NC}$TARGET_FILE"
    wget -q "$TARGET_URL" -O "$TARGET_FILE"
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось скачать ${NC}$TARGET_FILE"
        log_message "Ошибка: не удалось скачать $TARGET_FILE"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    command -v unzip >/dev/null 2>&1 || {
        echo -e "${GREEN}🔴 ${CYAN}Устанавливаем${NC} unzip ${CYAN}для распаковки архива${NC}"
        opkg update >/dev/null 2>&1
        opkg install unzip >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось установить unzip${NC}"
            log_message "Ошибка: не удалось установить unzip"
            [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
    }

    echo -e "${GREEN}🔴 ${CYAN}Распаковываем архив${NC}"
    unzip -o "$TARGET_FILE" >/dev/null
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось распаковать ${NC}$TARGET_FILE"
        log_message "Ошибка: не удалось распаковать $TARGET_FILE"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    for PKG in zapret_*.ipk luci-app-zapret_*.ipk; do
        [ -f "$PKG" ] && {
            echo -e "${GREEN}🔴 ${CYAN}Устанавливаем пакет ${NC}$PKG"
            opkg install --force-reinstall "$PKG" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}Не удалось установить пакет ${NC}$PKG"
                log_message "Ошибка: не удалось установить пакет $PKG"
                [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
                return 1
            fi
        }
    done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы и пакеты${NC}"
    cd /
    rm -rf "$WORKDIR"
    rm -f /tmp/*.ipk /tmp/*.zip /tmp/*zapret* 2>/dev/null

    [ -f /etc/init.d/zapret ] && {
        echo -e "${GREEN}🔴 ${CYAN}Перезапуск службы ${NC}zapret"
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        /etc/init.d/zapret restart >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось перезапустить службу zapret${NC}"
            log_message "Ошибка: не удалось перезапустить службу zapret"
            [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
    }

    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Zapret успешно установлен !${NC}"
    log_message "Zapret успешно установлен, версия $TARGET_VER"
    echo -e ""
    [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Чиним дефолтную стратегию
# ==========================================
fix_default() {
    local NO_PAUSE=$1
    [ "$NO_PAUSE" != "1" ] && clear
    [ "$NO_PAUSE" != "1" ] && echo -e ""
    echo -e "${MAGENTA}Редактируем стратегию по умолчанию${NC}"
    echo -e ""
    log_message "Начало оптимизации стратегии по умолчанию"

    # Проверка, установлен ли Zapret
    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен"
        [ "$NO_PAUSE" != "1" ] && echo -e ""
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    # Используем uci для изменения конфигурации
    uci delete zapret.@config[0].fake 2>/dev/null
    uci delete zapret.@rule[0] 2>/dev/null
    uci set zapret.@config[0].dpi_desync_repeats='6'
    uci commit zapret

    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Не удалось перезапустить службу zapret${NC}"
        log_message "Ошибка: не удалось перезапустить службу zapret"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    echo -e "${BLUE}🔴 ${GREEN}Стратегия по умолчанию отредактирована !${NC}"
    log_message "Стратегия по умолчанию отредактирована"
    [ "$NO_PAUSE" != "1" ] && echo -e ""
    [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Включение Discord и звонков в TG и WA
# ==========================================
enable_discord_calls() {
    local NO_PAUSE=$1
    [ "$NO_PAUSE" != "1" ] && clear
    [ "$NO_PAUSE" != "1" ] && echo -e ""
    [ "$NO_PAUSE" != "1" ] && echo -e "${MAGENTA}Меню настройки Discord и звонков в TG/WA${NC}"
    [ "$NO_PAUSE" != "1" ] && echo -e ""
    log_message "Начало настройки Discord и звонков в TG/WA"

    if [ ! -f /etc/init.d/zapret ]; then
        echo -e "${RED}Zapret не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен"
        echo -e ""
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
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

    [ "$NO_PAUSE" != "1" ] && echo -e "${YELLOW}Установленный скрипт:${NC} $CURRENT_SCRIPT"
    [ "$NO_PAUSE" != "1" ] && echo -e ""

    if [ "$NO_PAUSE" = "1" ]; then
        SELECTED="50-stun4all"
        URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-stun4all"
    else
        echo -e "${CYAN}1) ${GREEN}Установить скрипт ${NC}50-stun4all"
        echo -e "${CYAN}2) ${GREEN}Установить скрипт ${NC}50-quic4all"
        echo -e "${CYAN}3) ${GREEN}Удалить скрипт${NC}"
        echo -e "${CYAN}0) ${GREEN}Выход в главное меню (Enter)${NC}"
        echo -e ""
        echo -ne "${YELLOW}Выберите пункт:${NC} "
        read choice
        if ! [[ "$choice" =~ ^[0-3]$ ]]; then
            echo -e "${RED}Некорректный выбор. Пожалуйста, введите число от 0 до 3.${NC}"
            log_message "Ошибка: некорректный выбор в меню Discord/TG/WA"
            sleep 2
            show_menu
            return 0
        fi

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
                echo -e ""
                echo -e "${BLUE}🔴 ${GREEN}Скрипт удалён !${NC}"
                rm -f "$CUSTOM_DIR/50-script.sh" 2>/dev/null
                chmod +x /opt/zapret/sync_config.sh
                /opt/zapret/sync_config.sh
                /etc/init.d/zapret restart >/dev/null 2>&1
                log_message "Скрипт $CURRENT_SCRIPT удалён"
                echo -e ""
                read -p "Нажмите Enter для выхода в главное меню..." dummy
                show_menu
                return 0
                ;;
            *)
                echo -e ""
                echo -e "${GREEN}Выходим в главное меню...${NC}"
                log_message "Выход в главное меню из настроек Discord/TG/WA"
                sleep 1
                show_menu
                return 0
                ;;
        esac
    fi

    if [ "$CURRENT_SCRIPT" = "$SELECTED" ]; then
        echo -e ""
        echo -e "${RED}Выбранный скрипт уже установлен !${NC}"
        log_message "Скрипт $SELECTED уже установлен"
    else
        mkdir -p "$CUSTOM_DIR"
        check_internet || { [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
        if curl -fsSLo "$CUSTOM_DIR/50-script.sh" "$URL"; then
            if [ ! -s "$CUSTOM_DIR/50-script.sh" ]; then
                echo -e "${RED}Ошибка: загруженный скрипт пустой или не скачан${NC}"
                log_message "Ошибка: загруженный скрипт $SELECTED пустой или не скачан"
                [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
                return 1
            fi
            echo -e ""
            echo -e "${GREEN}🔴 ${CYAN}Скрипт ${NC}$SELECTED${CYAN} успешно установлен !${NC}"
            log_message "Скрипт $SELECTED успешно установлен"
            chmod +x /opt/zapret/sync_config.sh
            /opt/zapret/sync_config.sh
            /etc/init.d/zapret restart >/dev/null 2>&1
            echo -e ""
            echo -e "${BLUE}🔴 ${GREEN}Звонки и Discord включены !${NC}"
            log_message "Звонки и Discord включены с помощью $SELECTED"
        else
            echo -e "${RED}Ошибка при скачивании скрипта !${NC}"
            log_message "Ошибка: не удалось скачать скрипт $SELECTED"
            [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
    fi

    if ! uci show zapret | grep -q "filter_udp='50000-50099'"; then
        uci set zapret.@config[0].NFQWS_PORTS_UDP='443,50000-50099'
        uci add zapret rule
        uci set zapret.@rule[-1].filter_udp='50000-50099'
        uci set zapret.@rule[-1].filter_l7='discord,stun'
        uci set zapret.@rule[-1].dpi_desync='fake'
        uci commit zapret
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        /etc/init.d/zapret restart >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось перезапустить службу zapret${NC}"
            log_message "Ошибка: не удалось перезапустить службу zapret"
            [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
    fi

    echo -e ""
    [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Zapret под ключ
# ==========================================
zapret_key() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Установка и настройка Zapret под ключ${NC}"
    echo -e ""
    log_message "Начало установки Zapret под ключ"

    check_internet || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
    get_versions || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }

    if [ "$LIMIT_REACHED" -eq 1 ]; then
        echo -e ""
        echo -e "${RED}Достигнут лимит GitHub API. Подождите 15 минут.${NC}"
        log_message "Ошибка: достигнут лимит GitHub API"
        echo -e ""
        read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    uninstall_zapret "1" || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
    install_update "1" || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
    fix_default "1" || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }
    echo -e ""
    echo -e "${MAGENTA}Включаем Discord и звонки в TG и WA${NC}"
    echo -e ""
    enable_discord_calls "1" || { read -p "Нажмите Enter для выхода в главное меню..." dummy; return 1; }

    if [ -f /etc/init.d/zapret ]; then
        echo -e "Zapret ${GREEN}установлен и настроен !${NC}"
        log_message "Zapret успешно установлен и настроен под ключ"
    else
        echo -e "Zapret ${RED}не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен под ключ"
    fi

    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Вернуть настройки по умолчанию
# ==========================================
comeback_def() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Возвращаем настройки по умолчанию${NC}"
    echo -e ""
    log_message "Начало возврата настроек по умолчанию"

    if [ -f /opt/zapret/restore-def-cfg.sh ]; then
        rm -f /opt/zapret/init.d/openwrt/custom.d/50-script.sh 2>/dev/null
        [ -f /etc/init.d/zapret ] && /etc/init.d/zapret stop >/dev/null 2>&1
        chmod +x /opt/zapret/restore-def-cfg.sh
        /opt/zapret/restore-def-cfg.sh
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        [ -f /etc/init.d/zapret ] && /etc/init.d/zapret restart >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось перезапустить службу zapret${NC}"
            log_message "Ошибка: не удалось перезапустить службу zapret"
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
        echo -e "${BLUE}🔴 ${GREEN}Настройки возвращены, сервис перезапущен !${NC}"
        log_message "Настройки возвращены, сервис перезапущен"
    else
        echo -e "${RED}Zapret не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен"
    fi
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Остановить Zapret
# ==========================================
stop_zapret() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Останавливаем Zapret${NC}"
    echo -e ""
    log_message "Начало остановки Zapret"

    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Останавливаем сервис ${NC}Zapret"
        /etc/init.d/zapret stop >/dev/null 2>&1
        PIDS=$(pgrep -f /opt/zapret)
        if [ -n "$PIDS" ]; then
            echo -e "${GREEN}🔴 ${CYAN}Пытаемся мягко завершить процессы ${NC}Zapret"
            for pid in $PIDS; do kill -15 "$pid" >/dev/null 2>&1; done
            sleep 2
            PIDS=$(pgrep -f /opt/zapret)
            if [ -n "$PIDS" ]; then
                echo -e "${GREEN}🔴 ${CYAN}Принудительно завершаем процессы ${NC}Zapret"
                for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
            fi
        fi
        echo -e ""
        echo -e "${BLUE}🔴 ${GREEN}Zapret остановлен !${NC}"
        log_message "Zapret успешно остановлен"
    else
        echo -e "${RED}Zapret не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен"
    fi
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Запустить Zapret
# ==========================================
start_zapret() {
    clear
    echo -e ""
    echo -e "${MAGENTA}Запускаем Zapret${NC}"
    echo -e ""
    log_message "Начало запуска Zapret"

    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Запускаем сервис ${NC}Zapret"
        /etc/init.d/zapret start >/dev/null 2>&1
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        /etc/init.d/zapret restart >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Не удалось запустить службу zapret${NC}"
            log_message "Ошибка: не удалось запустить службу zapret"
            read -p "Нажмите Enter для выхода в главное меню..." dummy
            return 1
        fi
        echo -e ""
        echo -e "${BLUE}🔴 ${GREEN}Zapret запущен !${NC}"
        log_message "Zapret успешно запущен"
    else
        echo -e "${RED}Zapret не установлен !${NC}"
        log_message "Ошибка: Zapret не установлен"
    fi
    echo -e ""
    read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Полное удаление Zapret
# ==========================================
uninstall_zapret() {
    local NO_PAUSE=$1
    clear
    echo -e ""
    echo -e "${MAGENTA}Удаляем ZAPRET${NC}"
    echo -e ""
    log_message "Начало удаления Zapret"

    if [ -f /etc/init.d/zapret ]; then
        echo -e "${GREEN}🔴 ${CYAN}Останавливаем сервис ${NC}zapret"
        /etc/init.d/zapret stop >/dev/null 2>&1
    fi

    PIDS=$(pgrep -f /opt/zapret)
    if [ -n "$PIDS" ]; then
        echo -e "${GREEN}🔴 ${CYAN}Пытаемся мягко завершить процессы ${NC}zapret"
        for pid in $PIDS; do kill -15 "$pid" >/dev/null 2>&1; done
        sleep 2
        PIDS=$(pgrep -f /opt/zapret)
        if [ -n "$PIDS" ]; then
            echo -e "${GREEN}🔴 ${CYAN}Принудительно завершаем процессы ${NC}zapret"
            for pid in $PIDS; do kill -9 "$pid" >/dev/null 2>&1; done
        fi
    fi

    echo -e "${GREEN}🔴 ${CYAN}Удаляем пакеты${NC} zapret ${CYAN}и ${NC}luci-app-zapret"
    opkg remove --force-removal-of-dependent-packages zapret luci-app-zapret >/dev/null 2>&1
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка при удалении пакетов zapret и luci-app-zapret${NC}"
        log_message "Ошибка: не удалось удалить пакеты zapret и luci-app-zapret"
        [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
        return 1
    fi

    echo -e "${GREEN}🔴 ${CYAN}Удаляем конфигурации и рабочие папки${NC}"
    for path in /opt/zapret /etc/config/zapret /etc/firewall.zapret; do
        [ -e "$path" ] && rm -rf "$path"
    done

    if crontab -l >/dev/null 2>&1; then
        crontab -l | grep -v -i "zapret" | crontab -
        echo -e "${GREEN}🔴 ${CYAN}Очищаем${NC} crontab ${CYAN}задания${NC}"
        log_message "Очищены crontab задания"
    fi

    echo -e "${GREEN}🔴 ${CYAN}Удаляем${NC} ipset"
    for set in $(ipset list -n 2>/dev/null | grep -i zapret); do
        ipset destroy "$set" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            echo -e "${RED}Ошибка при удалении ipset $set${NC}"
            log_message "Ошибка: не удалось удалить ipset $set"
        fi
    done

    echo -e "${GREEN}🔴 ${CYAN}Удаляем временные файлы${NC}"
    rm -f /tmp/*zapret* /var/run/*zapret* 2>/dev/null

    echo -e "${GREEN}🔴 ${CYAN}Удаляем цепочки и таблицы${NC} nftables"
    for table in $(nft list tables 2>/dev/null | awk '{print $2}'); do
        chains=$(nft list table "$table" 2>/dev/null | grep zapret)
        if [ -n "$chains" ]; then
            nft delete table "$table" >/dev/null 2>&1
            if [ $? -ne 0 ]; then
                echo -e "${RED}Ошибка при удалении таблицы $table${NC}"
                log_message "Ошибка: не удалось удалить таблицу $table"
            fi
        fi
    done

    echo -e ""
    echo -e "${BLUE}🔴 ${GREEN}Zapret полностью удалён !${NC}"
    log_message "Zapret полностью удалён"
    echo -e ""
    [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter для выхода в главное меню..." dummy
}

# ==========================================
# Главное меню
# ==========================================
show_menu() {
    get_versions || return 1

    clear
    echo -e ""
    echo -e "╔════════════════════════════════════╗"
    echo -e "║     ${BLUE}Zapret on remittor Manager${NC}     ║"
    echo -e "╚════════════════════════════════════╝"
    echo -e "                                  ${DGRAY}v2.7${NC}"

    # Определяем актуальная/устарела
    if [ "$LIMIT_REACHED" -eq 1 ]; then
        INST_COLOR=$CYAN
        INSTALLED_DISPLAY="$INSTALLED_VER"
    elif [ "$INSTALLED_VER" = "$LATEST_VER" ] && [ "$LATEST_VER" != "не найдена" ]; then
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

    # Вывод информации о версиях и архитектуре
    echo -e ""
    echo -e "${YELLOW}Установленная версия: ${INST_COLOR}$INSTALLED_DISPLAY${NC}"
    echo -e ""
    echo -e "${YELLOW}Последняя версия на GitHub: ${CYAN}$LATEST_VER${NC}"
    echo -e ""
    echo -e "${YELLOW}Архитектура устройства:${NC} $LOCAL_ARCH"

    # Выводим статус службы zapret, если он известен
    [ -n "$ZAPRET_STATUS" ] && echo -e "\n${YELLOW}Статус Zapret: ${NC}$ZAPRET_STATUS"

    # Проверяем, установлен ли кастомный скрипт
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

    # Если скрипт найден, выводим строку
    [ -n "$CURRENT_SCRIPT" ] && echo -e "\n${YELLOW}Установлен скрипт: ${NC}$CURRENT_SCRIPT"

    echo -e ""

    # Вывод пунктов меню
    echo -e "${CYAN}1) ${GREEN}Установить последнюю версию${NC}"
    echo -e "${CYAN}2) ${GREEN}Оптимизировать стратегию по умолчанию${NC}"
    echo -e "${CYAN}3) ${GREEN}Вернуть настройки по умолчанию${NC}"
    echo -e "${CYAN}4) ${GREEN}Остановить ${NC}Zapret"
    echo -e "${CYAN}5) ${GREEN}Запустить ${NC}Zapret"
    echo -e "${CYAN}6) ${GREEN}Удалить ${NC}Zapret"
    echo -e "${CYAN}7) ${GREEN}Меню настройки ${NC}Discord${GREEN} и звонков в ${NC}TG${GREEN}/${NC}WA"
    echo -e "${CYAN}8) ${GREEN}Удалить / Установить / Настроить${NC} Zapret"
    echo -e "${CYAN}0) ${GREEN}Выход (Enter)${NC}"
    echo -e ""
    echo -ne "${YELLOW}Выберите пункт:${NC} "
    read choice

    if ! [[ "$choice" =~ ^[0-8]$ ]]; then
        echo -e "${RED}Некорректный выбор. Пожалуйста, введите число от 0 до 8.${NC}"
        log_message "Ошибка: некорректный выбор в главном меню"
        sleep 2
        return 0
    fi

    case "$choice" in
        1) install_update ;;
        2) fix_default ;;
        3) comeback_def ;;
        4) stop_zapret ;;
        5) start_zapret ;;
        6) uninstall_zapret ;;
        7) enable_discord_calls ;;
        8) zapret_key ;;
        *) exit 0 ;;
    esac
}

# ==========================================
# Старт скрипта (цикл)
# ==========================================
while true; do
    show_menu
done
