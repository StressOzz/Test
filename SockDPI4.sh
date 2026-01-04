#!/bin/sh
# DPI bypass manager OpenWrt 24+ (nftables, split-proxy)

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

SITES="google.com googlevideo.com discord.com youtube.com instagram.com facebook.com"

install_bypass() {
    echo ""
    echo "=== Установка обхода (nftables + split-proxy) ==="
    echo ""

    step "Обновление пакетов..."
    opkg update > /dev/null 2>&1
    success "Список пакетов обновлен"

    step "Установка модулей ядра..."
    opkg install kmod-tun kmod-nf-nat kmod-nf-conntrack > /dev/null 2>&1 || true
    success "Модули установлены"

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
socks5:
  port: 1080
  address: 127.0.0.1
  udp: 'udp'
EOF

    uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
    uci set hev-socks5-tunnel.config.enabled='1'
    uci commit hev-socks5-tunnel
    success "hev-socks5-tunnel настроен и включен"

    step "Включение автозапуска..."
    /etc/init.d/byedpi enable
    /etc/init.d/hev-socks5-tunnel enable
    success "Автозапуск включен"

    step "Запуск сервисов..."
    /etc/init.d/byedpi restart
    sleep 2
    /etc/init.d/hev-socks5-tunnel restart
    sleep 3
    success "Сервисы запущены"

    step "Настройка nftables (split-proxy)..."
    LAN_NET=$(uci get network.lan.ipaddr | cut -d. -f1-3).0/24

    mkdir -p /etc/nftables.d

    cat > /etc/nftables.d/90-bypass.nft <<EOF
table inet bypass {
    chain prerouting {
        type nat hook prerouting priority dstnat;
        # split-proxy: только для указанных сайтов
EOF

    for host in $SITES; do
        IPs=$(nslookup $host | awk '/^Address: / {print $2}')
        for ip in $IPs; do
            [ -n "$ip" ] && echo "        ip saddr $LAN_NET ip daddr $ip tcp dport {80,443} redirect to :1080" >> /etc/nftables.d/90-bypass.nft
        done
    done

    cat >> /etc/nftables.d/90-bypass.nft <<'EOF'
    }
}
EOF

    # Применяем сразу
    nft -f /etc/nftables.d/90-bypass.nft
    success "nftables настроены, split-proxy для LAN готов"
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

    rm -f /etc/nftables.d/90-bypass.nft
    nft delete table inet bypass 2>/dev/null || true

    success "Удалено"
}

main_menu() {
    while true; do
        echo ""
        echo "1) Установить обход (split-proxy)"
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
