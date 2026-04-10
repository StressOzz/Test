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

# Определение архитектуры для GO
get_arch_GO() {
    case "$ARCH" in
        aarch64*) echo "tg-ws-proxy-openwrt-aarch64" ;;
        armv7*|armhf|armv7l) echo "tg-ws-proxy-openwrt-armv7" ;;
        mipsel_24kc|mipsel*) echo "tg-ws-proxy-openwrt-mipsel_24kc" ;;
        mips_24kc|mips*) echo "tg-ws-proxy-openwrt-mips_24kc" ;;
        x86_64) echo "tg-ws-proxy-openwrt-x86_64" ;;
        *) echo "Неизвестная архитектура: $ARCH"; return 1 ;;
    esac
}

# Установка TG WS Proxy Go
install_TG_GO() {
    echo -e "\n${MAGENTA}Установка TG WS Proxy Go${NC}"
    
    ARCH_FILE_GO="$(get_arch_GO)" || {
        echo -e "\n${RED}Архитектура не поддерживается:${NC} $(uname -m)\n"
        PAUSE
        return 1
    }
    
    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${CYAN}Устанавливаем ${NC}curl"
        $UPDATE >/dev/null 2>&1 && $INSTALL curl >/dev/null 2>&1 || {
            echo -e "\n${RED}Ошибка установки curl${NC}\n"
            PAUSE
            return 1
        }
    fi
    
    echo -e "${CYAN}Скачиваем и устанавливаем${NC} $ARCH_FILE_GO"
    LATEST_TAG_GO="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest | sed 's#.*/tag/##')"
    
    [ -z "$LATEST_TAG_GO" ] && {
        echo -e "\n${RED}Не удалось получить версию${NC} TG WS Proxy Go\n"
        PAUSE
        return 1
    }
    
    DOWNLOAD_URL_GO="https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG_GO/$ARCH_FILE_GO"
    
    curl -L --fail -o "/usr/bin/tg-ws-proxy-go" "$DOWNLOAD_URL_GO" >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка скачивания${NC}\n"
        PAUSE
        return 1
    }
    
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
    procd_close_instance
}
EOF
    
    chmod +x "/etc/init.d/tg-ws-proxy-go"
    /etc/init.d/tg-ws-proxy-go enable
    /etc/init.d/tg-ws-proxy-go start
    
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "${GREEN}Сервис ${NC}TG WS Proxy Go${GREEN} запущен!${NC}\n"
    else
        echo -e "\n${RED}Сервис TG WS Proxy Go не запущен!${NC}\n"
    fi
    PAUSE
}

# Установка и настройка Redsocks
install_Redsocks() {
    echo -e "\n${MAGENTA}Установка Redsocks${NC}"
    
    $UPDATE >/dev/null 2>&1
    $INSTALL redsocks >/dev/null 2>&1 || {
        echo -e "\n${RED}Ошибка установки redsocks${NC}\n"
        PAUSE
        return 1
    }
    
    echo -e "${GREEN}Redsocks установлен${NC}"
    
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
    
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart
    
    echo -e "${GREEN}Redsocks настроен и запущен${NC}\n"
    PAUSE
}

# Настройка nftables правил
setup_nftables() {
    echo -e "\n${MAGENTA}Настройка nftables правил для Telegram${NC}"
    
    # Скачивание списка IP Telegram
    echo -e "${CYAN}Загрузка списка IP адресов Telegram...${NC}"
    
    TEMP_FILE="/tmp/telegram_ips.txt"
    curl -s "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt" -o "$TEMP_FILE"
    
    if [ ! -s "$TEMP_FILE" ]; then
        echo -e "${RED}Не удалось загрузить список IP адресов${NC}"
        PAUSE
        return 1
    fi
    
    # Создание скрипта для настройки nftables
    cat > '/etc/firewall.user' << 'EOF'
# Telegram прозрачное проксирование через Redsocks

# Создание сета для IP Telegram
nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null

# Очистка сета
nft flush set inet fw4 telegram_list 2>/dev/null

EOF
    
    # Добавление IP в сет
    echo -e "${CYAN}Добавление IP адресов в nftables...${NC}"
    
    # Формируем строку с IP для добавления
    IP_LIST=""
    while IFS= read -r line; do
        # Пропускаем комментарии и пустые строки
        echo "$line" | grep -q '^#' && continue
        [ -z "$line" ] && continue
        
        # Обрабатываем CIDR и одиночные IP
        if echo "$line" | grep -q '/'; then
            IP_LIST="$IP_LIST $line"
        else
            IP_LIST="$IP_LIST $line/32"
        fi
    done < "$TEMP_FILE"
    
    # Добавляем IP в сет
    if [ -n "$IP_LIST" ]; then
        # Разбиваем на части по 50 IP, чтобы избежать слишком длинной команды
        echo "$IP_LIST" | xargs -n 50 sh -c 'nft add element inet fw4 telegram_list { $* } 2>/dev/null' sh
    fi
    
    # Добавляем статические диапазоны (CDN и медиа)
    cat >> '/etc/firewall.user' << 'EOF'
# Добавление статических диапазонов (CDN и медиа)
nft add element inet fw4 telegram_list { \
91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
149.154.160.0/20, 185.76.151.0/24 \
} 2>/dev/null

# Удаляем старое правило если есть
nft delete rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345 2>/dev/null

# Добавляем правило редиректа
nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345

EOF
    
    # Перезапуск фаервола
    echo -e "${CYAN}Применение правил фаервола...${NC}"
    /etc/init.d/firewall restart
    
    # Проверка
    sleep 2
    echo -e "\n${GREEN}Правила nftables:${NC}"
    nft list set inet fw4 telegram_list 2>/dev/null | head -n 20
    
    echo -e "\n${GREEN}Правило редиректа:${NC}"
    nft list chain inet fw4 dstnat 2>/dev/null | grep -A 2 "telegram_list"
    
    rm -f "$TEMP_FILE"
    echo -e "\n${GREEN}Настройка nftables завершена!${NC}\n"
    PAUSE
}

# Проверка статуса
check_status() {
    echo -e "\n${MAGENTA}=== СТАТУС СЕРВИСОВ ===${NC}"
    
    # TG WS Proxy Go
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        echo -e "TG WS Proxy Go: ${GREEN}РАБОТАЕТ${NC}"
    else
        echo -e "TG WS Proxy Go: ${RED}НЕ РАБОТАЕТ${NC}"
    fi
    
    # Redsocks
    if pidof redsocks >/dev/null 2>&1; then
        echo -e "Redsocks:      ${GREEN}РАБОТАЕТ${NC}"
    else
        echo -e "Redsocks:      ${RED}НЕ РАБОТАЕТ${NC}"
    fi
    
    # Проверка правил nftables
    if nft list set inet fw4 telegram_list 2>/dev/null | grep -q "elements = {"; then
        COUNT=$(nft list set inet fw4 telegram_list 2>/dev/null | grep -c "[0-9]\+\.[0-9]\+")
        echo -e "Telegram IP:   ${GREEN}ЗАГРУЖЕНЫ ($COUNT+ IP)${NC}"
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
    # Восстанавливаем оригинальный firewall.user
    if [ -f /etc/firewall.user.bak ]; then
        mv /etc/firewall.user.bak /etc/firewall.user
    else
        rm -f /etc/firewall.user
        touch /etc/firewall.user
    fi
    
    # Удаляем сет и правила
    nft delete set inet fw4 telegram_list 2>/dev/null
    nft delete rule inet fw4 dstnat ip daddr @telegram_list 2>/dev/null
    
    /etc/init.d/firewall restart
    
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

# Создание бэкапа firewall.user если его нет
if [ -f /etc/firewall.user ] && [ ! -f /etc/firewall.user.bak ]; then
    cp /etc/firewall.user /etc/firewall.user.bak
fi

# Запуск главного меню
main_menu
