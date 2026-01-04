#!/bin/sh
# ========================================
# Менеджер обхода блокировок для OpenWrt 24+
# byedpi + hev-socks5-tunnel + split-proxy IPv4
# ========================================

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

# ===============================
# Установка и настройка обхода
# ===============================
install_bypass() {
    echo ""
    echo "=== Установка обхода ==="
    echo ""

    step "Обновление списка пакетов..."
    opkg update > /dev/null 2>&1
    success "Список пакетов обновлен"

    step "Установка модулей ядра..."
    for pkg in kmod-tun kmod-nf-nat kmod-nf-conntrack; do
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

    step "Настройка split-proxy IPv4..."
    setup_split_proxy
    success "Split-proxy настроен"
}

# ===============================
# Split-proxy IPv4-only через fw4
# ===============================
DOMAIN_FILE="/etc/split-proxy-domains.txt"
FW_FILE="/etc/firewall.user"

setup_split_proxy() {
    LAN_NET=$(uci get network.lan.ipaddr | cut -d. -f1-3).0/24

    # Проверка файла доменов
    if [ ! -f "$DOMAIN_FILE" ]; then
        cat > "$DOMAIN_FILE" <<EOF
youtube.com
googlevideo.com
ytimg.com
discord.com
discord.gg
instagram.com
cdninstagram.com
x.com
twimg.com
EOF
        success "Файл доменов $DOMAIN_FILE создан с примерами"
    fi

    step "Генерация правил в $FW_FILE..."
    cat > "$FW_FILE" <<EOF
#!/bin/sh
# Split-proxy IPv4-only (авто-сгенерировано)
EOF

    while read domain; do
        [ -z "$domain" ] && continue
        for ip in $(nslookup "$domain" 2>/dev/null | awk '/^Address: / {print $2}'); do
            echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' || continue
            echo "iptables -t nat -A PREROUTING -s $LAN_NET -d $ip -p tcp --dport 80 -j REDIRECT --to-ports 1080" >> "$FW_FILE"
            echo "iptables -t nat -A PREROUTING -s $LAN_NET -d $ip -p tcp --dport 443 -j REDIRECT --to-ports 1080" >> "$FW_FILE"
        done
    done < "$DOMAIN_FILE"

    chmod +x "$FW_FILE"
    step "Применяем firewall..."
    /etc/init.d/firewall restart
}

# ===============================
# Удаление обхода
# ===============================
remove_bypass() {
    echo ""
    echo "=== Удаление обхода ==="
    echo ""

    read -p "Вы уверены? Это удалит все пакеты и настройки (y/N): " confirm
    [ "$confirm" != "y" ] && [ "$confirm" != "Y" ] && { info "Отменено"; return; }

    step "Остановка сервисов..."
    /etc/init.d/byedpi stop > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel stop > /dev/null 2>&1
    success "Сервисы остановлены"

    step "Отключение автозапуска..."
    /etc/init.d/byedpi disable > /dev/null 2>&1
    /etc/init.d/hev-socks5-tunnel disable > /dev/null 2>&1
    success "Автозапуск отключен"

    step "Удаление пакетов..."
    for pkg in byedpi hev-socks5-tunnel; do
        if opkg list-installed | grep -q "^${pkg} "; then
            opkg remove ${pkg} > /dev/null 2>&1
            success "  ${pkg} удален"
        fi
    done

    step "Удаление конфигураций..."
    rm -rf /etc/config/byedpi /etc/config/byedpi.hosts /etc/hev-socks5-tunnel
    rm -f "$FW_FILE" "$DOMAIN_FILE"
    success "Конфигурации удалены"

    step "Перезапуск firewall..."
    /etc/init.d/firewall restart

    success "Удаление завершено!"
}

# ===============================
# Главное меню
# ===============================
main_menu() {
    while true; do
        echo ""
        echo "╔════════════════════════════════════╗"
        echo "║    Менеджер обхода блокировок      ║"
        echo "╚════════════════════════════════════╝"
        echo ""
        echo "1) Установить обход"
        echo "2) Удалить обход"
        echo "3) Выход"
        read -p "Выберите действие [1-3]: " choice
        case $choice in
            1) install_bypass ;;
            2) remove_bypass ;;
            3|*) echo ""; info "Выход"; exit 0 ;;
        esac
    done
}

# ===============================
# Запуск меню
# ===============================
main_menu
