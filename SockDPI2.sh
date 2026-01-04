#!/bin/sh
# Менеджер обхода блокировок для OpenWRT 24+

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; }
step() { echo -e "${YELLOW}→${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

install_bypass() {
    echo ""
    echo "=== Установка обхода ==="
    echo ""

    step "Обновление списка пакетов..."
    opkg update > /dev/null 2>&1
    success "Список пакетов обновлен"

    step "Установка модулей ядра..."
    for pkg in kmod-tun kmod-ipt-nat iptables-nft; do
        if ! opkg list-installed | grep -q "^${pkg} "; then
            opkg install ${pkg} > /dev/null 2>&1
        fi
    done
    success "Модули установлены"

    step "Установка byedpi..."
    if ! opkg list-installed | grep -q "^byedpi "; then
        BYEDPI_URL="https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/byedpi_0.17.3-r1_aarch64_cortex-a53.ipk"
        BYEDPI_FILE="/tmp/byedpi.ipk"
        wget -q -O "$BYEDPI_FILE" "$BYEDPI_URL" 2>/dev/null || { error "Ошибка загрузки byedpi"; exit 1; }
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

    success "byedpi настроен"

    step "Настройка hev-socks5-tunnel..."
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml << 'EOFYAML'
socks5:
  port: 1080
  address: 127.0.0.1
  udp: 'udp'
EOFYAML

    uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
    uci set hev-socks5-tunnel.config.enabled='1'
    uci commit hev-socks5-tunnel
    success "hev-socks5-tunnel настроен и включен"

    step "Включение автозапуска..."
    /etc/init.d/byedpi enable > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel enable > /dev/null 2>&1
    success "Автозапуск включен"

    step "Запуск сервисов..."
    /etc/init.d/byedpi restart > /dev/null 2>&1
    sleep 3
    /etc/init.d/hev-socks5-tunnel restart > /dev/null 2>&1
    sleep 5
    success "Сервисы запущены"

    step "Настройка iptables..."
    LAN_NET=$(uci get network.lan.ipaddr | cut -d. -f1-3).0/24
    iptables-nft -t nat -A PREROUTING -s ${LAN_NET} -p tcp --dport 80 -j REDIRECT --to-port 1080 2>/dev/null || true
    iptables-nft -t nat -A PREROUTING -s ${LAN_NET} -p tcp --dport 443 -j REDIRECT --to-port 1080 2>/dev/null || true
    success "Правила iptables настроены"

    success "Установка завершена!"
}

main_menu() {
    while true; do
        echo ""
        echo "1) Установить обход"
        echo "2) Выход"
        read -p "Выберите действие [1-2]: " choice
        case $choice in
            1) install_bypass ;;
            2|*) echo ""; info "Выход"; exit 0 ;;
        esac
    done
}

main_menu
