#!/bin/sh
# DPI bypass manager OpenWrt 24+ (firewall4 + nftables + TPROXY)

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

success() { echo -e "${GREEN}✓${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1"; exit 1; }
step() { echo -e "${YELLOW}→${NC} $1"; }
info() { echo -e "${BLUE}ℹ${NC} $1"; }

install_bypass() {
    echo ""
    echo "=== Установка DPI bypass (переживает перезагрузку) ==="
    echo ""

    step "Обновление пакетов..."
    opkg update > /dev/null 2>&1

    step "Установка необходимых пакетов..."
    opkg install \
        byedpi \
        hev-socks5-tunnel \
        kmod-tun \
        kmod-nf-tproxy \
        kmod-nft-socket \
        ip-full \
        nftables > /dev/null 2>&1 || error "Ошибка установки пакетов"
    success "Пакеты установлены"

    step "Настройка byedpi..."
    cat > /etc/config/byedpi << 'EOF'
config byedpi 'main'
	option enabled '1'
	option cmd_opts '-o2 --auto=t,r,a,s -d2'
	option hosts 'youtube.com googlevideo.com ytimg.com youtu.be youtube.googleapis.com'
EOF
    success "byedpi настроен"

    step "Настройка hev-socks5-tunnel..."
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml << 'EOF'
socks5:
  address: 127.0.0.1
  port: 1080
  udp: 'udp'
EOF

    uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
    uci set hev-socks5-tunnel.config.enabled='1'
    uci commit hev-socks5-tunnel
    success "hev-socks5-tunnel настроен"

    step "Включение автозапуска сервисов..."
    /etc/init.d/byedpi enable
    /etc/init.d/hev-socks5-tunnel enable
    success "Автозапуск включен"

    step "Настройка policy routing для TPROXY..."
    grep -q "100 tproxy" /etc/iproute2/rt_tables || echo "100 tproxy" >> /etc/iproute2/rt_tables
    ip rule add fwmark 1 lookup tproxy 2>/dev/null
    ip route add local 0.0.0.0/0 dev lo table tproxy 2>/dev/null
    success "Policy routing готов"

    step "Создание nftables include для firewall4..."
    cat > /etc/nftables.d/90-dpi-bypass.nft << 'EOF'
table inet dpi_bypass {

    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        ip protocol tcp tcp dport { 80, 443 } meta mark set 1 tproxy to :1080
    }
}
EOF
    success "nftables правила созданы"

    step "Перезапуск firewall и сервисов..."
    /etc/init.d/firewall restart
    /etc/init.d/byedpi restart
    /etc/init.d/hev-socks5-tunnel restart
    success "Все сервисы запущены"

    echo ""
    success "Готово. После перезагрузки всё будет работать."
}

remove_bypass() {
    echo ""
    echo "=== Удаление DPI bypass ==="
    read -p "Точно удалить? (y/N): " c
    [ "$c" != "y" ] && return

    /etc/init.d/byedpi stop 2>/dev/null
    /etc/init.d/hev-socks5-tunnel stop 2>/dev/null
    /etc/init.d/byedpi disable
    /etc/init.d/hev-socks5-tunnel disable

    rm -f /etc/nftables.d/90-dpi-bypass.nft
    sed -i '/100 tproxy/d' /etc/iproute2/rt_tables
    ip rule del fwmark 1 lookup tproxy 2>/dev/null
    ip route flush table tproxy 2>/dev/null

    opkg remove byedpi hev-socks5-tunnel > /dev/null 2>&1

    /etc/init.d/firewall restart
    success "Удалено полностью"
}

main_menu() {
    while true; do
        echo ""
        echo "1) Установить обход (переживает ребут)"
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
