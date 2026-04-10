#!/bin/sh

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Определение версии OpenWrt и пакетного менеджера
get_package_manager() {
    if grep -q "OpenWrt 2[4-5]" /etc/openwrt_release 2>/dev/null; then
        OPENWRT_VERSION=$(grep "DISTRIB_RELEASE" /etc/openwrt_release | cut -d'=' -f2 | tr -d '"')
        echo -e "${CYAN}Обнаружена OpenWrt версия:${NC} $OPENWRT_VERSION"
        
        # Проверяем наличие apk (OpenWrt 25+)
        if command -v apk >/dev/null 2>&1; then
            PKG_MANAGER="apk"
            UPDATE="apk update"
            INSTALL="apk add"
            REMOVE="apk del"
            echo -e "${GREEN}Используем пакетный менеджер: apk${NC}"
        else
            PKG_MANAGER="opkg"
            UPDATE="opkg update"
            INSTALL="opkg install"
            REMOVE="opkg remove"
            echo -e "${GREEN}Используем пакетный менеджер: opkg${NC}"
        fi
    else
        # Fallback на opkg
        PKG_MANAGER="opkg"
        UPDATE="opkg update"
        INSTALL="opkg install"
        REMOVE="opkg remove"
        echo -e "${YELLOW}Не удалось определить версию, используем opkg${NC}"
    fi
}

# Функции
PAUSE() {
    echo -e "\n${CYAN}Нажмите Enter для продолжения...${NC}"
    read dummy
}

# Определение архитектуры для GO
get_arch_GO() {
    ARCH=$(uname -m)
    case "$ARCH" in
        aarch64|aarch64_be) echo "tg-ws-proxy-openwrt-aarch64" ;;
        armv7*|armhf|armv7l) echo "tg-ws-proxy-openwrt-armv7" ;;
        armv8*|arm64) echo "tg-ws-proxy-openwrt-aarch64" ;;
        mipsel_24kc|mipsel*) echo "tg-ws-proxy-openwrt-mipsel_24kc" ;;
        mips_24kc|mips*) echo "tg-ws-proxy-openwrt-mips_24kc" ;;
        x86_64|amd64) echo "tg-ws-proxy-openwrt-x86_64" ;;
        i386|i686|x86) echo "tg-ws-proxy-openwrt-x86_64" ;;
        *) echo "Неизвестная архитектура: $ARCH"; return 1 ;;
    esac
}

# Установка TG WS Proxy Go
install_TG_GO() {
    echo -e "\n${MAGENTA}Установка TG WS Proxy Go${NC}"
    
    ARCH=$(uname -m)
    echo -e "${CYAN}Обнаружена архитектура:${NC} $ARCH"
    
    ARCH_FILE_GO="$(get_arch_GO)" || {
        echo -e "\n${RED}Архитектура не поддерживается:${NC} $ARCH\n"
        PAUSE
        return 1
    }
    
    echo -e "${CYAN}Бинарный файл:${NC} $ARCH_FILE_GO"
    
    # Установка curl или wget если нет
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "${CYAN}Устанавливаем wget...${NC}"
        $UPDATE >/dev/null 2>&1
        $INSTALL wget >/dev/null 2>&1 || {
            echo -e "\n${RED}Ошибка установки wget${NC}\n"
            PAUSE
            return 1
        }
    fi
    
    echo -e "${CYAN}Скачиваем и устанавливаем${NC} $ARCH_FILE_GO"
    
    # Получаем последнюю версию
    LATEST_TAG_GO=""
    if command -v curl >/dev/null 2>&1; then
        LATEST_TAG_GO="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest 2>/dev/null | sed 's#.*/tag/##')"
    else
        LATEST_TAG_GO="$(wget -q --method=HEAD -O /dev/null https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest 2>&1 | grep -oP 'tag/\K[^ ]+' | head -1)"
    fi
    
    if [ -z "$LATEST_TAG_GO" ]; then
        echo -e "${YELLOW}Не удалось получить версию, пробуем альтернативный метод...${NC}"
        # Альтернативный метод получения версии
        if command -v curl >/dev/null 2>&1; then
            LATEST_TAG_GO="$(curl -s https://api.github.com/repos/d0mhate/-tg-ws-proxy-Manager-go/releases/latest 2>/dev/null | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)".*/\1/')"
        fi
    fi
    
    [ -z "$LATEST_TAG_GO" ] && {
        echo -e "${YELLOW}Не удалось получить последнюю версию, используем v1.0.0${NC}"
        LATEST_TAG_GO="v1.0.0"
    }
    
    echo -e "${CYAN}Версия:${NC} $LATEST_TAG_GO"
    
    # Пробуем разные URL
    DOWNLOAD_SUCCESS=0
    for URL in "https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO" \
               "https://github.com/d0mhate/tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO" \
               "https://github.com/d0mhate/tg-ws-proxy-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO"; do
        
        echo -e "${CYAN}Пробуем:${NC} $URL"
        
        if command -v curl >/dev/null 2>&1; then
            if curl -L --fail -o "/usr/bin/tg-ws-proxy-go" "$URL" 2>/dev/null; then
                DOWNLOAD_SUCCESS=1
                break
            fi
        else
            if wget -O "/usr/bin/tg-ws-proxy-go" "$URL" 2>/dev/null; then
                DOWNLOAD_SUCCESS=1
                break
            fi
        fi
    done
    
    if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
        echo -e "\n${RED}Ошибка скачивания - не удалось загрузить бинарный файл${NC}"
        echo -e "${YELLOW}Проверьте подключение к интернету и доступность GitHub${NC}\n"
        PAUSE
        return 1
    fi
    
    chmod +x "/usr/bin/tg-ws-proxy-go"
    
    # Создание init скрипта (работает и в OpenWrt 24 и 25)
    cat > '/etc/init.d/tg-ws-proxy-go' << 'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy-go --host 0.0.0.0 --port 1080
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall tg-ws-proxy-go 2>/dev/null
}
EOF
    
    chmod +x "/etc/init.d/tg-ws-proxy-go"
    
    # Для apk (OpenWrt 25) нужно добавить сервис по-другому
    if [ "$PKG_MANAGER" = "apk" ]; then
        # OpenWrt 25 использует другой способ управления сервисами
        /etc/init.d/tg-ws-proxy-go enable
        /etc/init.d/tg-ws-proxy-go start
    else
        /etc/init.d/tg-ws-proxy-go enable
        /etc/init.d/tg-ws-proxy-go start
    fi
    
    sleep 2
    
    if pgrep -f "tg-ws-proxy-go" >/dev/null 2>&1; then
        echo -e "${GREEN}Сервис ${NC}TG WS Proxy Go${GREEN} запущен!${NC}"
        echo -e "${CYAN}Прокси слушает на:${NC} 127.0.0.1:1080\n"
    else
        echo -e "\n${RED}Сервис TG WS Proxy Go не запущен!${NC}"
        echo -e "${YELLOW}Проверьте логи: logread | grep tg-ws-proxy${NC}\n"
    fi
    PAUSE
}

# Установка и настройка Redsocks
install_Redsocks() {
    echo -e "\n${MAGENTA}Установка Redsocks${NC}"
    
    # Обновляем список пакетов
    $UPDATE >/dev/null 2>&1
    
    # Пробуем установить redsocks
    INSTALL_SUCCESS=0
    
    # Список пакетов для разных версий
    if [ "$PKG_MANAGER" = "apk" ]; then
        # Для OpenWrt 25 пакеты могут называться иначе
        for PKG in redsocks redsocks2; do
            echo -e "${CYAN}Пробуем установить $PKG...${NC}"
            if $INSTALL $PKG 2>/dev/null; then
                INSTALL_SUCCESS=1
                break
            fi
        done
    else
        # Для OpenWrt 24 и старше
        for PKG in redsocks redsocks2; do
            echo -e "${CYAN}Пробуем установить $PKG...${NC}"
            if $INSTALL $PKG 2>/dev/null; then
                INSTALL_SUCCESS=1
                break
            fi
        done
    fi
    
    if [ $INSTALL_SUCCESS -eq 0 ]; then
        echo -e "${YELLOW}Пакет redsocks не найден в репозиториях${NC}"
        echo -e "${CYAN}Устанавливаем microsocks как альтернативу...${NC}"
        
        if $INSTALL microsocks 2>/dev/null; then
            # Настройка microsocks
            if [ -f "/etc/config/microsocks" ]; then
                uci set microsocks.@microsocks[0].enabled=1
                uci set microsocks.@microsocks[0].port=1080
                uci set microsocks.@microsocks[0].bind='0.0.0.0'
                uci commit microsocks
            fi
            
            /etc/init.d/microsocks enable 2>/dev/null
            /etc/init.d/microsocks start 2>/dev/null
            
            echo -e "${GREEN}Microsocks установлен как SOCKS5 сервер на порту 1080${NC}"
            
            # Создаем конфиг для redsocks (который будет работать через microsocks)
            cat > '/etc/redsocks.conf' << 'EOF'
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 1080;
    type = socks5;
}
EOF
            
            # Запускаем redsocks если он установлен
            if command -v redsocks >/dev/null 2>&1; then
                /etc/init.d/redsocks enable 2>/dev/null
                /etc/init.d/redsocks start 2>/dev/null
            fi
            
            PAUSE
            return 0
        else
            echo -e "${RED}Не удалось установить ни redsocks, ни microsocks${NC}"
            PAUSE
            return 1
        fi
    fi
    
    # Создание конфига redsocks
    cat > '/etc/redsocks.conf' << 'EOF'
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = 12345;
    ip = 127.0.0.1;
    port = 1080;
    type = socks5;
}
EOF
    
    # Создание init скрипта для redsocks если его нет
    if [ ! -f "/etc/init.d/redsocks" ]; then
        cat > '/etc/init.d/redsocks' << 'EOF'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/redsocks -c /etc/redsocks.conf
    procd_set_param respawn
    procd_close_instance
}

stop_service() {
    killall redsocks 2>/dev/null
}
EOF
        chmod +x /etc/init.d/redsocks
    fi
    
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart
    
    sleep 2
    
    if pgrep -f "redsocks" >/dev/null 2>&1; then
        echo -e "${GREEN}Redsocks настроен и запущен${NC}\n"
    else
        echo -e "${YELLOW}Redsocks не запущен, но конфиг создан${NC}\n"
    fi
    PAUSE
}

# Настройка nftables правил (остается без изменений)
setup_nftables() {
    echo -e "\n${MAGENTA}Настройка nftables правил для Telegram${NC}"
    
    # Проверяем наличие nftables
    if ! command -v nft >/dev/null 2>&1; then
        echo -e "${CYAN}Устанавливаем nftables...${NC}"
        $UPDATE >/dev/null 2>&1
        $INSTALL nftables >/dev/null 2>&1
    fi
    
    # Скачивание списка IP Telegram
    echo -e "${CYAN}Загрузка списка IP адресов Telegram...${NC}"
    
    TEMP_FILE="/tmp/telegram_ips.txt"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt" -o "$TEMP_FILE"
    else
        wget -q -O "$TEMP_FILE" "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"
    fi
    
    if [ ! -s "$TEMP_FILE" ]; then
        echo -e "${RED}Не удалось загрузить список IP адресов${NC}"
        echo -e "${YELLOW}Использую статический список...${NC}"
        
        cat > "$TEMP_FILE" << 'EOF'
91.105.192.0/23
91.108.4.0/22
91.108.8.0/21
91.108.16.0/22
91.108.20.0/22
91.108.34.0/23
91.108.36.0/23
91.108.38.0/23
91.108.40.0/22
91.108.48.0/22
91.108.56.0/22
95.161.64.0/20
149.154.160.0/20
185.76.151.0/24
EOF
    fi
    
    # Создание сета в nftables
    echo -e "${CYAN}Создание сета Telegram в nftables...${NC}"
    
    if ! nft list tables 2>/dev/null | grep -q "inet fw4"; then
        echo -e "${YELLOW}Таблица inet fw4 не найдена, создаем...${NC}"
        nft add table inet fw4
        nft add chain inet fw4 dstnat { type nat hook prerouting priority -100 \; }
    fi
    
    nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null
    nft flush set inet fw4 telegram_list 2>/dev/null
    
    echo -e "${CYAN}Добавление IP адресов в nftables...${NC}"
    
    count=0
    while IFS= read -r line; do
        echo "$line" | grep -q '^#' && continue
        [ -z "$line" ] && continue
        
        nft add element inet fw4 telegram_list { $line } 2>/dev/null
        count=$((count + 1))
        
        [ $((count % 50)) -eq 0 ] && echo -e "${CYAN}Добавлено $count IP...${NC}"
    done < "$TEMP_FILE"
    
    echo -e "${GREEN}Добавлено $count IP адресов/диапазонов${NC}"
    
    # Добавляем дополнительные статические диапазоны
    echo -e "${CYAN}Добавление дополнительных диапазонов...${NC}"
    nft add element inet fw4 telegram_list { \
        91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
        91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
        91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
        149.154.160.0/20, 185.76.151.0/24 \
    } 2>/dev/null
    
    # Добавляем правило редиректа
    echo -e "${CYAN}Добавление правила редиректа...${NC}"
    
    nft delete rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } 2>/dev/null
    nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345
    
    # Сохраняем правила
    echo -e "${CYAN}Сохранение правил...${NC}"
    
    if [ -f "/etc/init.d/firewall" ]; then
        /etc/init.d/firewall restart
    fi
    
    # Проверка
    sleep 2
    echo -e "\n${GREEN}=== ПРОВЕРКА НАСТРОЕК ===${NC}"
    
    echo -e "\n${CYAN}Сет Telegram:${NC}"
    nft list set inet fw4 telegram_list 2>/dev/null | head -n 10
    echo "..."
    
    echo -e "\n${CYAN}Правило редиректа:${NC}"
    nft list chain inet fw4 dstnat 2>/dev/null | grep -A 2 "telegram_list"
    
    rm -f "$TEMP_FILE"
    echo -e "\n${GREEN}Настройка nftables завершена!${NC}\n"
    PAUSE
}

# Остальные функции (check_status, delete_all, main_menu) остаются без изменений
# Проверка статуса
check_status() {
    echo -e "\n${MAGENTA}=== СТАТУС СЕРВИСОВ ===${NC}"
    
    echo -e "${CYAN}Пакетный менеджер:${NC} $PKG_MANAGER"
    
    # TG WS Proxy Go
    if pgrep -f "tg-ws-proxy-go" >/dev/null 2>&1; then
        echo -e "TG WS Proxy Go: ${GREEN}РАБОТАЕТ${NC}"
    else
        echo -e "TG WS Proxy Go: ${RED}НЕ РАБОТАЕТ${NC}"
    fi
    
    # Redsocks
    if pgrep -f "redsocks" >/dev/null 2>&1; then
        echo -e "Redsocks:      ${GREEN}РАБОТАЕТ${NC}"
    else
        echo -e "Redsocks:      ${RED}НЕ РАБОТАЕТ${NC}"
    fi
    
    # Microsocks
    if pgrep -f "microsocks" >/dev/null 2>&1; then
        echo -e "Microsocks:    ${GREEN}РАБОТАЕТ${NC}"
    fi
    
    # SOCKS5 порт
    if netstat -tln 2>/dev/null | grep -q ":1080"; then
        echo -e "SOCKS5 порт:   ${GREEN}СЛУШАЕТ (1080)${NC}"
    else
        echo -e "SOCKS5 порт:   ${RED}НЕ СЛУШАЕТ${NC}"
    fi
    
    # REDIRECT порт
    if netstat -tln 2>/dev/null | grep -q ":12345"; then
        echo -e "REDIRECT порт: ${GREEN}СЛУШАЕТ (12345)${NC}"
    else
        echo -e "REDIRECT порт: ${RED}НЕ СЛУШАЕТ${NC}"
    fi
    
    # Проверка правил nftables
    if nft list set inet fw4 telegram_list 2>/dev/null | grep -q "elements = {"; then
        echo -e "Telegram IP:   ${GREEN}НАСТРОЕНО${NC}"
    else
        echo -e "Telegram IP:   ${RED}НЕ НАСТРОЕНЫ${NC}"
    fi
    
    echo ""
    PAUSE
}

# Остановка и удаление всего
delete_all() {
    echo -e "\n${RED}=== УДАЛЕНИЕ ВСЕХ КОМПОНЕНТОВ ===${NC}"
    
    echo -e "${CYAN}Остановка сервисов...${NC}"
    /etc/init.d/tg-ws-proxy-go stop 2>/dev/null
    /etc/init.d/tg-ws-proxy-go disable 2>/dev/null
    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null
    /etc/init.d/microsocks stop 2>/dev/null
    /etc/init.d/microsocks disable 2>/dev/null
    
    echo -e "${CYAN}Удаление файлов...${NC}"
    rm -f /usr/bin/tg-ws-proxy-go
    rm -f /etc/init.d/tg-ws-proxy-go
    rm -f /etc/redsocks.conf
    
    echo -e "${CYAN}Удаление пакетов...${NC}"
    if [ "$PKG_MANAGER" = "apk" ]; then
        $REMOVE redsocks redsocks2 microsocks 2>/dev/null
    else
        $REMOVE redsocks redsocks2 microsocks 2>/dev/null
    fi
    
    echo -e "${CYAN}Очистка правил nftables...${NC}"
    nft delete set inet fw4 telegram_list 2>/dev/null
    nft delete rule inet fw4 dstnat ip daddr @telegram_list 2>/dev/null
    
    /etc/init.d/firewall restart 2>/dev/null
    
    echo -e "${GREEN}Все компоненты удалены!${NC}\n"
    PAUSE
}

# Главное меню
main_menu() {
    while true; do
        clear
        echo -e "${CYAN}================================${NC}"
        echo -e "${GREEN}  Установка TG Proxy + Redsocks  ${NC}"
        echo -e "${CYAN}================================${NC}"
        echo -e "${YELLOW}1)${NC} Полная установка (все компоненты)"
        echo -e "${YELLOW}2)${NC} Установить только TG WS Proxy Go"
        echo -e "${YELLOW}3)${NC} Установить только Redsocks"
        echo -e "${YELLOW}4)${NC} Настроить nftables (Telegram IP)"
        echo -e "${YELLOW}5)${NC} Проверить статус"
        echo -e "${YELLOW}6)${NC} Удалить всё"
        echo -e "${YELLOW}0)${NC} Выход"
        echo -e "${CYAN}================================${NC}"
        echo -n "Выберите пункт: "
        read choice
        
        case $choice in
            1)
                install_TG_GO
                install_Redsocks
                setup_nftables
                check_status
                ;;
            2)
                install_TG_GO
                ;;
            3)
                install_Redsocks
                ;;
            4)
                setup_nftables
                ;;
            5)
                check_status
                ;;
            6)
                delete_all
                ;;
            0)
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор!${NC}"
                sleep 1
                ;;
        esac
    done
}

# Запуск
get_package_manager
main_menu
