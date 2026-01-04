#!/bin/sh
# Менеджер обхода блокировок для OpenWRT


set -e

# Цвета
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Функции вывода
success() {
    echo -e "${GREEN}✓${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

step() {
    echo -e "${YELLOW}→${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Функция установки обхода
install_bypass() {
    echo ""
    echo "=== Установка обхода ==="
    echo ""
    
    step "Обновление списка пакетов..."
    opkg update > /dev/null 2>&1
    success "Список пакетов обновлен"
      
    step "Установка byedpi..."
    if ! opkg list-installed | grep -q "^byedpi "; then
        BYEDPI_URL="https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/byedpi_0.17.3-r1_aarch64_cortex-a53.ipk"
        BYEDPI_FILE="/tmp/byedpi.ipk"
        wget -q -O "$BYEDPI_FILE" "$BYEDPI_URL" 2>/dev/null || {
            error "Ошибка загрузки byedpi"
            exit 1
        }
        opkg install "$BYEDPI_FILE" > /dev/null 2>&1
        rm -f "$BYEDPI_FILE"
        success "byedpi установлен"
    else
        success "byedpi уже установлен"
    fi
    
    step "Установка hev-socks5-tunnel..."
    if ! opkg list-installed | grep -q "^hev-socks5-tunnel "; then
        opkg install hev-socks5-tunnel > /dev/null 2>&1
        success "hev-socks5-tunnel установлен"
    else
        success "hev-socks5-tunnel уже установлен"
    fi
    
    
    step "Настройка byedpi..."
    cat > /etc/config/byedpi << 'EOFUCI'
config byedpi 'main'
	option enabled '1'
	option cmd_opts '-E -s12+s -d18+s -r6+s -a4 -An'
EOFUCI

    cat > /etc/config/byedpi.hosts << 'EOFHOSTS'
google.com
googlevideo.com
googleapis.com
ytimg.com
ggpht.com
youtube.com
EOFHOSTS
    success "byedpi настроен"
    
    step "Настройка hev-socks5-tunnel..."
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml << 'EOFYAML'
socks5:
  port: 1080
  address: 127.0.0.1
  udp: 'udp'
EOFYAML
  
	# Создаем или обновляем конфигурацию UCI
    if ! uci get hev-socks5-tunnel.config > /dev/null 2>&1; then
        uci add hev-socks5-tunnel config
    fi
    uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
    uci set hev-socks5-tunnel.config.enabled='1'
    uci commit hev-socks5-tunnel
    success "hev-socks5-tunnel настроен и включен"
    
    
    step "Включение автозапуска..."
    /etc/init.d/byedpi enable > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel enable > /dev/null 2>&1
    success "Автозапуск включен"
    
    step "Запуск byedpi..."
    /etc/init.d/byedpi restart > /dev/null 2>&1
    sleep 3
    # Проверка, что byedpi запущен
    if /etc/init.d/byedpi status > /dev/null 2>&1; then
        success "byedpi запущен"
    else
        error "byedpi не запустился"
    fi
    
 
    step "Запуск hev-socks5-tunnel..."
    # Ждем, пока byedpi полностью запустится
    sleep 2
    /etc/init.d/hev-socks5-tunnel restart > /dev/null 2>&1
    sleep 5
    # Проверка, что TUN интерфейс создан (может потребоваться больше времени)

    success "Установка завершена!"
}

# Функция проверки статуса

# Функция удаления обхода
remove_bypass() {
    echo ""
    echo "=== Удаление обхода ==="
    echo ""
    read -p "Вы уверены? Это удалит все пакеты и настройки (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        info "Отменено"
        return
    fi
    
    step "Остановка сервисов..."
    /etc/init.d/byedpi stop > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel stop > /dev/null 2>&1

    success "Сервисы остановлены"
    
    step "Отключение автозапуска..."
    /etc/init.d/byedpi disable > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel disable > /dev/null 2>&1

    /etc/init.d/apply-proxy-rules disable > /dev/null 2>&1
    success "Автозапуск отключен"
    
    step "Удаление правил iptables..."
    iptables-nft -t nat -F PREROUTING 2>/dev/null || true
    rm -f /etc/firewall.user
    success "Правила удалены"
    
    step "Удаление пакетов..."
    for pkg in byedpi hev-socks5-tunnel; do
        if opkg list-installed | grep -q "^${pkg} "; then
            opkg remove ${pkg} > /dev/null 2>&1
            success "  ${pkg} удален"
        fi
    done
    
    step "Удаление модулей..."
    for mod in kmod-ipt-nat iptables-nft; do
        if opkg list-installed | grep -q "^${mod} "; then
            opkg remove ${mod} > /dev/null 2>&1
            success "  ${mod} удален"
        fi
    done
    
    # kmod-tun не удаляем, может использоваться другими сервисами
    
    step "Удаление конфигураций..."
    rm -rf /etc/config/byedpi /etc/config/byedpi.hosts
    rm -rf /etc/hev-socks5-tunnel
    rm -f /etc/init.d/apply-proxy-rules
    success "Конфигурации удалены"
    
    echo ""
    success "Удаление завершено!"
}

# Функция конфигурации byedpi
configure_byedpi() {
    echo ""
    echo "=== Конфигурация byedpi ==="
    echo ""
    
    if ! opkg list-installed | grep -q "^byedpi "; then
        error "byedpi не установлен. Сначала выполните установку обхода."
        return
    fi
    
    echo "Текущая конфигурация:"
    CURRENT_OPTS=$(uci get byedpi.main.cmd_opts 2>/dev/null || echo "")
    if [ -n "$CURRENT_OPTS" ]; then
        echo "  cmd_opts='${CURRENT_OPTS}'"
    else
        echo "  cmd_opts не установлен"
    fi
    echo ""
    
    echo "Введите новые параметры для cmd_opts:"
    echo "Пример: --split 2 --disorder 6+s --mod-http=h,d"
    echo "Или оставьте пустым для отмены"
    read -p "> " new_opts
    
    if [ -z "$new_opts" ]; then
        info "Отменено"
        return
    fi
    
    step "Применение конфигурации..."
    uci set byedpi.main.cmd_opts="${new_opts}"
    uci commit byedpi
    success "Конфигурация сохранена"
    
    step "Перезапуск byedpi..."
    /etc/init.d/byedpi restart > /dev/null 2>&1
    sleep 2
    success "byedpi перезапущен"
    
    echo ""
    echo "Новая конфигурация:"
    uci get byedpi.main.cmd_opts
    echo ""
}

# Главное меню
main_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════╗"
        echo "║    Менеджер обхода блокировок      ║"
        echo "╚════════════════════════════════════╝"
        echo ""
        echo "1) Установить обход"
        echo "2) Удалить обход"
        echo "3) Конфигурация byedpi"
        echo ""
        read -p "Выберите действие [1-5]: " choice
        
        case $choice in
            1)
                install_bypass
                ;;

            2)
                remove_bypass
                ;;
            3)
                configure_byedpi
                ;;
            *)
                echo ""
                info "Выход"
                exit 0
                ;;

        esac
    done
}

# Запуск меню
main_menu
