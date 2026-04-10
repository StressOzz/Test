#!/bin/sh

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Функции
PAUSE() {
    echo -e "\n${CYAN}Нажмите Enter для продолжения...${NC}"
    read dummy
}

UPDATE="opkg update"
INSTALL="opkg install"

# Определение архитектуры для GO (ИСПРАВЛЕНО)
get_arch_GO() {
    case "$ARCH" in
        aarch64) echo "tg-ws-proxy-openwrt-aarch64" ;;
        aarch64_be) echo "tg-ws-proxy-openwrt-aarch64" ;;
        armv7*|armhf|armv7l) echo "tg-ws-proxy-openwrt-armv7" ;;
        mipsel_24kc|mipsel*) echo "tg-ws-proxy-openwrt-mipsel_24kc" ;;
        mips_24kc|mips*) echo "tg-ws-proxy-openwrt-mips_24kc" ;;
        x86_64) echo "tg-ws-proxy-openwrt-x86_64" ;;
        *) echo "Неизвестная архитектура: $ARCH"; return 1 ;;
    esac
}

# Альтернативный метод установки TG WS Proxy Go (через wget если curl не работает)
install_TG_GO() {
    echo -e "\n${MAGENTA}Установка TG WS Proxy Go${NC}"
    
    ARCH=$(uname -m)
    echo -e "${CYAN}Обнаружена архитектура:${NC} $ARCH"
    
    ARCH_FILE_GO="tg-ws-proxy-openwrt-aarch64"
    
    # Установка wget если нет curl
    if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
        echo -e "${CYAN}Устанавливаем wget${NC}"
        $UPDATE >/dev/null 2>&1 && $INSTALL wget >/dev/null 2>&1 || {
            echo -e "\n${RED}Ошибка установки wget${NC}\n"
            PAUSE
            return 1
        }
    fi
    
    echo -e "${CYAN}Скачиваем и устанавливаем${NC} $ARCH_FILE_GO"
    
    # Получаем последнюю версию
    if command -v curl >/dev/null 2>&1; then
        LATEST_TAG_GO="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest | sed 's#.*/tag/##')"
    else
        LATEST_TAG_GO="$(wget -q --method=HEAD -O /dev/null https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest 2>&1 | grep -oP 'tag/\K[^ ]+' | head -1)"
    fi
    
    [ -z "$LATEST_TAG_GO" ] && {
        echo -e "\n${RED}Не удалось получить версию, используем тег v1.0.0${NC}"
        LATEST_TAG_GO="v1.0.0"
    }
    
    DOWNLOAD_URL_GO="https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO"
    
    echo -e "${CYAN}Загрузка с:${NC} $DOWNLOAD_URL_GO"
    
    # Скачивание
    if command -v curl >/dev/null 2>&1; then
        curl -L --fail -o "/usr/bin/tg-ws-proxy-go" "$DOWNLOAD_URL_GO" >/dev/null 2>&1
    else
        wget -O "/usr/bin/tg-ws-proxy-go" "$DOWNLOAD_URL_GO" >/dev/null 2>&1
    fi
    
    if [ $? -ne 0 ] || [ ! -f "/usr/bin/tg-ws-proxy-go" ]; then
        echo -e "\n${RED}Ошибка скачивания${NC}"
        echo -e "${YELLOW}Пробуем альтернативный URL...${NC}"
        
        # Альтернативный URL
        DOWNLOAD_URL_GO="https://github.com/d0mhate/tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO"
        
        if command -v curl >/dev/null 2>&1; then
            curl -L --fail -o "/usr/bin/tg-ws-proxy-go" "$DOWNLOAD_URL_GO" >/dev/null 2>&1
        else
            wget -O "/usr/bin/tg-ws-proxy-go" "$DOWNLOAD_URL_GO" >/dev/null 2>&1
        fi
        
        [ $? -ne 0 ] && {
            echo -e "\n${RED}Ошибка скачивания через оба URL${NC}\n"
            PAUSE
            return 1
        }
    fi
    
    chmod +x "/usr/bin/tg-ws-proxy-go"
    
    # Создание init скрипта
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
EOF
    
    chmod +x "/etc/init.d/tg-ws-proxy-go"
    /etc/init.d/tg-ws-proxy-go enable
    /etc/init.d/tg-ws-proxy-go start
    
    sleep 2
    
    if pgrep -f "tg-ws-proxy-go" >/dev/null 2>&1; then
        echo -e "${GREEN}Сервис ${NC}TG WS Proxy Go${GREEN} запущен!${NC}\n"
    else
        echo -e "\n${RED}Сервис TG WS Proxy Go не запущен!${NC}"
        echo -e "${YELLOW}Проверьте логи: logread | grep tg-ws-proxy${NC}\n"
    fi
    PAUSE
}

# Установка и настройка Redsocks (ИСПРАВЛЕНО)
install_Redsocks() {
    echo -e "\n${MAGENTA}Установка Redsocks${NC}"
    
    # Обновляем список пакетов
    $UPDATE >/dev/null 2>&1
    
    # Пробуем установить redsocks
    if ! $INSTALL redsocks; then
        echo -e "${YELLOW}Пакет redsocks не найден в стандартных репозиториях${NC}"
        echo -e "${CYAN}Пробуем установить из альтернативных источников...${NC}"
        
        # Для OpenWrt 24/25 redsocks может быть в отдельном репозитории
        $INSTALL redsocks2 2>/dev/null || {
            echo -e "${RED}Не удалось установить redsocks${NC}"
            echo -e "${YELLOW}Устанавливаем microsocks как альтернативу? (y/n)${NC}"
            read answer
            if [ "$answer" = "y" ]; then
                $INSTALL microsocks
                # Настройка microsocks
                cat > '/etc/config/microsocks' << 'EOF'
config microsocks
    option enabled '1'
    option port '1080'
    option bind '0.0.0.0'
EOF
                /etc/init.d/microsocks enable
                /etc/init.d/microsocks start
                echo -e "${GREEN}Microsocks установлен как SOCKS5 сервер на порту 1080${NC}"
                
                # Настройка redsocks конфиг для работы с microsocks
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
                /etc/init.d/redsocks enable 2>/dev/null
                /etc/init.d/redsocks start 2>/dev/null
                PAUSE
                return 0
            else
                PAUSE
                return 1
            fi
        }
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

# Настройка nftables правил
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
        
        # Статический список основных IP Telegram
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
    
    # Проверяем существует ли таблица inet fw4
    if ! nft list tables | grep -q "inet fw4"; then
        echo -e "${YELLOW}Таблица inet fw4 не найдена, создаем...${NC}"
        nft add table inet fw4
        nft add chain inet fw4 dstnat { type nat hook prerouting priority -100 \; }
    fi
    
    # Создаем сет
    nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null
    nft flush set inet fw4 telegram_list 2>/dev/null
    
    # Добавляем IP в сет
    echo -e "${CYAN}Добавление IP адресов в nftables...${NC}"
    
    count=0
    while IFS= read -r line; do
        # Пропускаем комментарии и пустые строки
        echo "$line" | grep -q '^#' && continue
        [ -z "$line" ] && continue
        
        # Добавляем IP/CIDR
        nft add element inet fw4 telegram_list { $line } 2>/dev/null
        count=$((count + 1))
        
        # Показываем прогресс каждые 50 IP
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
    
    # Удаляем старое правило если есть
    nft delete rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } 2>/dev/null
    
    # Добавляем новое правило
    nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345
    
    # Сохраняем правила
    echo -e "${CYAN}Сохранение правил...${NC}"
    
    # Для OpenWrt 24/25 сохраняем через firewall
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

# Проверка статуса
check_status() {
    echo -e "\n${MAGENTA}=== СТАТУС СЕРВИСОВ ===${NC}"
    
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
        COUNT=$(nft list set inet fw4 telegram_list 2>/dev/null | grep -c "[0-9]\+\.[0-9]\+/[0-9]\+" || echo "0")
        echo -e "Telegram IP:   ${GREEN}НАСТРОЕНО (множество IP)${NC}"
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
    
    echo -e "${CYAN}Удаление файлов...${NC}"
    rm -f /usr/bin/tg-ws-proxy-go
    rm -f /etc/init.d/tg-ws-proxy-go
    rm -f /etc/redsocks.conf
    
    echo -e "${CYAN}Очистка правил nftables...${NC}"
    # Удаляем сет и правила
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

# Проверка, что скрипт запущен на OpenWrt
if ! grep -q "OpenWrt" /etc/openwrt_release 2>/dev/null; then
    echo -e "${RED}Этот скрипт предназначен только для OpenWrt!${NC}"
    exit 1
fi

# Запуск главного меню
main_menu
