#!/bin/sh

# ===== CONFIG =====
REDSOCKS_PORT="12345"
SOCKS_IP="127.0.0.1"  # IP вашего SOCKS5 прокси
SOCKS_PORT="1080"      # Порт вашего SOCKS5 прокси

SET_NAME="telegram_list"
CHAIN_NAME="tg_redsocks"

CONF="/etc/redsocks.conf"
NFT_FILE="/etc/nft-tg-redsocks.conf"

# ===== COLORS =====
GREEN="\033[1;32m"
RED="\033[1;31m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
NC="\033[0m"

# ===== PKG MANAGER =====
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    UPDATE="opkg update"
    INSTALL="opkg install"
    REMOVE="opkg remove"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
    REMOVE="apk del"
fi

# ===== DOWNLOAD TELEGRAM IPS =====
download_telegram_ips() {
    echo -e "${CYAN}Загрузка IP адресов Telegram...${NC}"
    
    TEMP_IPS="/tmp/telegram_ips.txt"
    
    if command -v curl >/dev/null 2>&1; then
        curl -s "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt" -o "$TEMP_IPS"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$TEMP_IPS" "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"
    else
        echo -e "${RED}Ни curl, ни wget не установлены${NC}"
        echo -e "${YELLOW}Устанавливаем wget...${NC}"
        $UPDATE >/dev/null 2>&1
        $INSTALL wget >/dev/null 2>&1
        wget -q -O "$TEMP_IPS" "https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"
    fi
    
    if [ ! -s "$TEMP_IPS" ]; then
        echo -e "${YELLOW}Не удалось загрузить список, используем статический${NC}"
        cat > "$TEMP_IPS" << 'EOF'
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
        return 0
    fi
    
    # Фильтруем только IPv4
    grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' "$TEMP_IPS" > "${TEMP_IPS}.tmp"
    mv "${TEMP_IPS}.tmp" "$TEMP_IPS"
    
    echo -e "${GREEN}Список загружен${NC}"
    return 0
}

# ===== INSTALL REDSOCKS =====
install_redsocks() {
    echo -e "${YELLOW}Установка Redsocks...${NC}"
    
    $UPDATE >/dev/null 2>&1
    
    # Пробуем установить redsocks
    if ! $INSTALL redsocks 2>/dev/null && ! $INSTALL redsocks2 2>/dev/null; then
        echo -e "${RED}Пакет redsocks не найден в репозиториях${NC}"
        echo -e "${YELLOW}Проверьте подключение к интернету и репозитории${NC}"
        return 1
    fi
    
    # Создание конфига redsocks
    cat > $CONF <<EOF
base {
    log_debug = off;
    log_info = on;
    log = "syslog:daemon";
    daemon = on;
    redirector = iptables;
}

redsocks {
    local_ip = 0.0.0.0;
    local_port = $REDSOCKS_PORT;
    ip = $SOCKS_IP;
    port = $SOCKS_PORT;
    type = socks5;
}
EOF
    
    echo -e "${GREEN}Конфиг создан: $CONF${NC}"
    
    # Создание init скрипта если его нет
    if [ ! -f "/etc/init.d/redsocks" ]; then
        cat > '/etc/init.d/redsocks' << 'EOF'
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/sbin/redsocks -c /etc/redsocks.conf
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}

stop_service() {
    killall redsocks 2>/dev/null
}
EOF
        chmod +x /etc/init.d/redsocks
        echo -e "${GREEN}Init скрипт создан${NC}"
    fi
    
    # Запуск сервиса
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart
    
    sleep 2
    
    if pgrep -f "redsocks" >/dev/null 2>&1; then
        echo -e "${GREEN}Redsocks запущен на порту $REDSOCKS_PORT${NC}"
        return 0
    else
        echo -e "${YELLOW}Redsocks не запустился, проверьте логи: logread | grep redsocks${NC}"
        return 1
    fi
}

# ===== SETUP NFTABLES =====
setup_nftables() {
    echo -e "${YELLOW}Настройка nftables...${NC}"
    
    # Проверка и установка nftables
    if ! command -v nft >/dev/null 2>&1; then
        echo -e "${CYAN}Устанавливаем nftables...${NC}"
        $INSTALL nftables >/dev/null 2>&1
    fi
    
    # Загрузка IP адресов
    download_telegram_ips || return 1
    
    # Создание nft конфига
    cat > $NFT_FILE <<EOF
# Telegram прозрачное проксирование через Redsocks
table inet fw4 {

    set $SET_NAME {
        type ipv4_addr
        flags interval
        auto-merge
    }

    chain $CHAIN_NAME {
        type nat hook output priority dstnat; policy accept;
        
        # Редирект трафика Telegram на Redsocks
        ip daddr @$SET_NAME tcp dport {80, 443} redirect to :$REDSOCKS_PORT
    }
}
EOF
    
    # Загрузка правил
    nft -f $NFT_FILE 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Ошибка загрузки nft правил${NC}"
        return 1
    fi
    
    # Очистка и добавление IP
    nft flush set inet fw4 $SET_NAME 2>/dev/null
    
    # Добавление IP из файла
    echo -e "${CYAN}Добавление IP адресов в nftables...${NC}"
    TEMP_IPS="/tmp/telegram_ips.txt"
    count=0
    
    while IFS= read -r line; do
        # Пропускаем комментарии и пустые строки
        echo "$line" | grep -q '^#' && continue
        [ -z "$line" ] && continue
        
        # Добавляем /32 если это одиночный IP
        if echo "$line" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$'; then
            line="${line}/32"
        fi
        
        nft add element inet fw4 $SET_NAME { $line } 2>/dev/null
        if [ $? -eq 0 ]; then
            count=$((count + 1))
        fi
        
        # Показываем прогресс каждые 50 IP
        [ $((count % 50)) -eq 0 ] && echo -e "${CYAN}Добавлено $count IP/диапазонов...${NC}"
    done < "$TEMP_IPS"
    
    echo -e "${GREEN}Добавлено $count IP адресов/диапазонов${NC}"
    
    # Добавляем дополнительные статические диапазоны (на всякий случай)
    echo -e "${CYAN}Добавление дополнительных диапазонов...${NC}"
    nft add element inet fw4 $SET_NAME { \
        91.105.192.0/23, 91.108.4.0/22, 91.108.8.0/21, 91.108.16.0/22, \
        91.108.20.0/22, 91.108.34.0/23, 91.108.36.0/23, 91.108.38.0/23, \
        91.108.40.0/22, 91.108.48.0/22, 91.108.56.0/22, 95.161.64.0/20, \
        149.154.160.0/20, 185.76.151.0/24 \
    } 2>/dev/null
    
    # Создание скрипта для автозагрузки
    mkdir -p /etc/nftables.d
    cat > "/etc/nftables.d/99-tg-redsocks.nft" <<EOF
#!/usr/sbin/nft -f

add table inet fw4
add set inet fw4 $SET_NAME { type ipv4_addr; flags interval; auto-merge; }
add chain inet fw4 $CHAIN_NAME { type nat hook output priority dstnat; policy accept; }
add rule inet fw4 $CHAIN_NAME ip daddr @$SET_NAME tcp dport {80, 443} redirect to :$REDSOCKS_PORT
EOF
    
    chmod +x "/etc/nftables.d/99-tg-redsocks.nft"
    
    # Обновляем основной конфиг nftables если есть
    if [ -f "/etc/nftables.conf" ]; then
        if ! grep -q "99-tg-redsocks.nft" /etc/nftables.conf; then
            echo 'include "/etc/nftables.d/99-tg-redsocks.nft"' >> /etc/nftables.conf
        fi
    fi
    
    # Перезапуск фаервола для применения правил
    /etc/init.d/firewall restart 2>/dev/null
    
    # Очистка
    rm -f "$TEMP_IPS"
    
    echo -e "${GREEN}nftables настроен успешно${NC}"
    return 0
}

# ===== UPDATE TELEGRAM IPS =====
update_telegram_ips() {
    echo -e "${YELLOW}Обновление списка IP Telegram...${NC}"
    
    download_telegram_ips || return 1
    
    # Очищаем существующий сет
    nft flush set inet fw4 $SET_NAME 2>/dev/null
    
    TEMP_IPS="/tmp/telegram_ips.txt"
    count=0
    
    while IFS= read -r line; do
        echo "$line" | grep -q '^#' && continue
        [ -z "$line" ] && continue
        
        if echo "$line" | grep -q '^[0-9]\+\.[0-9]\+\.[0-9]\+\.[0-9]\+$'; then
            line="${line}/32"
        fi
        
        nft add element inet fw4 $SET_NAME { $line } 2>/dev/null
        count=$((count + 1))
    done < "$TEMP_IPS"
    
    echo -e "${GREEN}Обновлено $count IP адресов/диапазонов${NC}"
    rm -f "$TEMP_IPS"
    
    return 0
}

# ===== REMOVE ALL =====
remove_all() {
    echo -e "${YELLOW}=== УДАЛЕНИЕ ===${NC}"
    
    # Остановка сервисов
    /etc/init.d/redsocks stop 2>/dev/null
    /etc/init.d/redsocks disable 2>/dev/null
    
    # Удаление файлов
    rm -f $CONF
    rm -f $NFT_FILE
    rm -f /etc/nftables.d/99-tg-redsocks.nft
    
    # Удаление правил nftables
    nft delete set inet fw4 $SET_NAME 2>/dev/null
    nft delete chain inet fw4 $CHAIN_NAME 2>/dev/null
    
    # Удаление пакетов
    echo -e "${CYAN}Удаление пакетов...${NC}"
    $REMOVE redsocks redsocks2 2>/dev/null
    
    echo -e "${GREEN}=== УДАЛЕНИЕ ЗАВЕРШЕНО ===${NC}"
    read -p "Enter..."
}

# ===== STATUS =====
status() {
    echo -e "${CYAN}╔════════════════════════════════╗${NC}"
    echo -e "${CYAN}║          СТАТУС               ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════╝${NC}"
    echo ""
    
    # Redsocks
    if pgrep -f "redsocks" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Redsocks:     ${GREEN}РАБОТАЕТ${NC}"
        echo -e "   Порт:         ${CYAN}$REDSOCKS_PORT${NC}"
        echo -e "   Целевой SOCKS: ${CYAN}$SOCKS_IP:$SOCKS_PORT${NC}"
    else
        echo -e "${RED}✗${NC} Redsocks:     ${RED}НЕ РАБОТАЕТ${NC}"
    fi
    
    echo ""
    
    # nftables
    if nft list set inet fw4 $SET_NAME >/dev/null 2>&1; then
        COUNT=$(nft list set inet fw4 $SET_NAME 2>/dev/null | grep -c "[0-9]\+\.[0-9]\+/[0-9]\+")
        echo -e "${GREEN}✓${NC} nftables:     ${GREEN}НАСТРОЕН${NC}"
        echo -e "   IP правил:    ${CYAN}$COUNT${NC}"
    else
        echo -e "${RED}✗${NC} nftables:     ${RED}НЕ НАСТРОЕН${NC}"
    fi
    
    echo ""
    
    # Проверка правил
    if nft list chain inet fw4 $CHAIN_NAME >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Правило редиректа: ${GREEN}АКТИВНО${NC}"
        nft list chain inet fw4 $CHAIN_NAME 2>/dev/null | grep -q "redirect to"
        if [ $? -eq 0 ]; then
            echo -e "   Редирект:     ${CYAN}-> :$REDSOCKS_PORT${NC}"
        fi
    else
        echo -e "${RED}✗${NC} Цепочка $CHAIN_NAME: ${RED}НЕ НАЙДЕНА${NC}"
    fi
    
    echo ""
    
    # Проверка SOCKS доступности
    if nc -z $SOCKS_IP $SOCKS_PORT 2>/dev/null || timeout 1 bash -c "echo >/dev/tcp/$SOCKS_IP/$SOCKS_PORT" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} SOCKS сервер:  ${GREEN}ДОСТУПЕН${NC} ($SOCKS_IP:$SOCKS_PORT)"
    else
        echo -e "${RED}✗${NC} SOCKS сервер:  ${RED}НЕ ДОСТУПЕН${NC}"
        echo -e "   ${YELLOW}Проверьте что SOCKS5 прокси запущен на $SOCKS_IP:$SOCKS_PORT${NC}"
    fi
}

# ===== CONFIGURE SOCKS SETTINGS =====
configure_socks() {
    echo -e "${CYAN}Настройка SOCKS параметров${NC}"
    echo -e "${YELLOW}Текущие настройки:${NC}"
    echo -e "  SOCKS IP:   $SOCKS_IP"
    echo -e "  SOCKS порт: $SOCKS_PORT"
    echo -e "  Redsocks порт: $REDSOCKS_PORT"
    echo ""
    
    read -p "Изменить SOCKS IP? (y/n): " change_ip
    if [ "$change_ip" = "y" ]; then
        read -p "Введите SOCKS IP [127.0.0.1]: " new_ip
        SOCKS_IP=${new_ip:-127.0.0.1}
    fi
    
    read -p "Изменить SOCKS порт? (y/n): " change_port
    if [ "$change_port" = "y" ]; then
        read -p "Введите SOCKS порт [1080]: " new_port
        SOCKS_PORT=${new_port:-1080}
    fi
    
    echo -e "${GREEN}Настройки обновлены${NC}"
    echo -e "${YELLOW}Для применения изменений переустановите redsocks${NC}"
    read -p "Enter..."
}

# ===== MENU =====
menu() {
    while true; do
        clear
        echo -e "${CYAN}╔══════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║     Redsocks + nftables для TG      ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}1)${NC} Установить Redsocks + nftables"
        echo -e "${GREEN}2)${NC} Обновить список IP Telegram"
        echo -e "${YELLOW}3)${NC} Настроить SOCKS параметры"
        echo -e "${CYAN}4)${NC} Проверить статус"
        echo -e "${RED}5)${NC} Удалить всё"
        echo -e "${RED}0)${NC} Выход"
        echo ""
        echo -e "${CYAN}Пакетный менеджер: ${NC}$PKG"
        echo -e "${CYAN}Redsocks порт: ${NC}$REDSOCKS_PORT"
        echo -e "${CYAN}Целевой SOCKS: ${NC}$SOCKS_IP:$SOCKS_PORT"
        echo ""
        
        read -p "Выбор: " c
        
        case "$c" in
            1)
                install_redsocks && setup_nftables
                echo -e "${GREEN}Установка завершена!${NC}"
                read -p "Enter..."
                ;;
            2)
                update_telegram_ips
                read -p "Enter..."
                ;;
            3)
                configure_socks
                ;;
            4)
                status
                read -p "Enter..."
                ;;
            5)
                remove_all
                ;;
            0)
                echo -e "${GREEN}До свидания!${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Неверный выбор${NC}"
                sleep 1
                ;;
        esac
    done
}

# ===== START =====
# Проверка root
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}Запустите с правами root (sudo)$NC}"
    exit 1
fi

# Проверка наличия wget/curl
if ! command -v wget >/dev/null 2>&1 && ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}Устанавливаем wget...${NC}"
    $UPDATE >/dev/null 2>&1
    $INSTALL wget >/dev/null 2>&1
fi

menu
