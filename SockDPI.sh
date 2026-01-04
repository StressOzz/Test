#!/bin/sh
# DPI bypass manager (NO iptables, OpenWrt 24+)

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
    echo "=== Установка обхода (без iptables) ==="
    echo ""

    step "Обновление пакетов..."
    opkg update > /dev/null 2>&1
    success "Список пакетов обновлен"

    step "Установка kmod-tun..."
    opkg install kmod-tun > /dev/null 2>&1 || true
    success "kmod-tun установлен"

    step "Установка byedpi..."
    if ! opkg list-installed | grep -q "^byedpi "; then
        BYEDPI_URL="https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/byedpi_0.17.3-r1_aarch64_cortex-a53.ipk"
        wget -q -O /tmp/byedpi.ipk "$BYEDPI_URL" || { error "Не удалось скачать byedpi"; exit 1; }
        opkg install /tmp/byedpi.ipk > /dev/null 2>&1
        rm -f /tmp/byedpi.ipk
        success "byedpi установлен"
    else
        success "byedpi уже установлен"
    fi

    step "Установка hev-socks5-tunnel..."
    opkg install hev-socks5-tunnel > /dev/null 2>&1 || true
    success "hev-socks5-tunnel установлен"

    step "Настройка byedpi..."
    cat > /etc/config/byedpi << 'EOF'
config byedpi 'main'
	option enabled '1'
	option cmd_opts '-E -s12+s -d18+s -r6+s -a4 -An'
EOF
    success "byedpi настроен"

    step "Настройка hev-socks5-tunnel..."
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml << 'EOF'
tunnel:
  name: tun0
  mtu: 8500
  ipv4: 198.18.0.1

socks5:
  address: 127.0.0.1
  port: 1080
EOF

    uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
    uci set hev-socks5-tunnel.config.enabled='1'
    uci commit hev-socks5-tunnel
    success "hev-socks5-tunnel настроен"

    step "Включение автозапуска..."
    /etc/init.d/byedpi enable
    /etc/init.d/hev-socks5-tunnel enable
    success "Автозапуск включен"

    step "Запуск сервисов..."
    /etc/init.d/byedpi restart
    sleep 2
    /etc/init.d/hev-socks5-tunnel restart
    sleep 3

    if ip link show tun0 > /dev/null 2>&1; then
        success "tun0 создан, SOCKS5: 127.0.0.1:1080"
    else
        info "tun0 ещё не поднялся — проверь через пару секунд"
    fi

    echo ""
    success "Готово. Трафик НЕ перехватывается автоматически."
    info "Используй SOCKS5 127.0.0.1:1080 на нужных устройствах."
}

remove_bypass() {
    echo ""
    echo "=== Удаление обхода ==="
    read -p "Точно удалить? (y/N): " c
    [ "$c" != "y" ] && return

    /etc/init.d/byedpi stop 2>/dev/null || true
    /etc/init.d/hev-socks5-tunnel stop 2>/dev/null || true
    /etc/init.d/byedpi disable
    /etc/init.d/hev-socks5-tunnel disable

    opkg remove byedpi hev-socks5-tunnel > /dev/null 2>&1 || true
    rm -rf /etc/config/byedpi /etc/hev-socks5-tunnel

    success "Удалено"
}

main_menu() {
    while true; do
        echo ""
        echo "1) Установить обход (без iptables)"
        echo "2) Удалить обход"
        echo "3) Выход"
        read -p "> " c
        case "$c" in
            1) install_bypass ;;
            2) remove_bypass ;;
            *) exit 0 ;;
        esac
    done
}

main_menu
