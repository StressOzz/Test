#!/bin/sh
# tg-ws-proxy-redsocks-installer.sh
# Установка TG WS Proxy Go + прозрачное проксирование через Redsocks + nftables
# Совместим с OpenWrt 24.10+ (firewall4 / nftables)
# POSIX sh compatible (ash/busybox)

set -e

# === Цвета для вывода ===
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# === Пути и переменные ===
BIN_PATH_GO="/usr/bin/tg-ws-proxy-go"
INIT_PATH_GO="/etc/init.d/tg-ws-proxy-go"
REDSOCKS_CONF="/etc/redsocks.conf"
FIREWALL_USER="/etc/firewall.user"
TELEGRAM_IPS_URL="https://raw.githubusercontent.com/runetfreedom/russia-blocked-geoip/refs/heads/release/text/telegram.txt"
NFT_SET_NAME="telegram_list"
NFT_TABLE="inet fw4"

# === Утилиты ===
log_info() { echo -e "${CYAN}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
pause() { echo -e "\n${MAGENTA}Нажмите Enter для продолжения...${NC}"; read -r dummy 2>/dev/null || true; }

# === Определение архитектуры для TG WS Proxy Go ===
get_arch_GO() {
    case "$(uname -m)" in
        aarch64*|arm64) echo "tg-ws-proxy-openwrt-aarch64" ;;
        armv7*|armhf|armv7l) echo "tg-ws-proxy-openwrt-armv7" ;;
        mipsel_24kc|mipsel*) echo "tg-ws-proxy-openwrt-mipsel_24kc" ;;
        mips_24kc|mips*) echo "tg-ws-proxy-openwrt-mips_24kc" ;;
        x86_64|amd64) echo "tg-ws-proxy-openwrt-x86_64" ;;
        *) log_error "Неизвестная архитектура: $(uname -m)"; return 1 ;;
    esac
}

# === Установка пакетов через opkg ===
install_packages() {
    log_info "Обновляем списки пакетов..."
    opkg update >/dev/null 2>&1 || { log_error "Не удалось обновить opkg"; return 1; }
    
    for pkg in redsocks curl nftables iptables-zz-compat-iptables; do
        if ! opkg list-installed | grep -q "^$pkg "; then
            log_info "Устанавливаем $pkg..."
            opkg install "$pkg" >/dev/null 2>&1 || {
                log_error "Ошибка установки $pkg"
                return 1
            }
        fi
    done
    log_success "Необходимые пакеты установлены"
}

# === Установка TG WS Proxy Go ===
install_tg_ws_proxy_go() {
    log_info "Установка TG WS Proxy Go..."
    
    ARCH_FILE_GO="$(get_arch_GO)" || return 1
    
    # Получаем последнюю версию
    LATEST_TAG=$(curl -Ls -o /dev/null -w '%{url_effective}' \
        https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest 2>/dev/null | \
        sed 's#.*/tag/##')
    
    [ -z "$LATEST_TAG" ] && { log_error "Не удалось получить версию TG WS Proxy Go"; return 1; }
    
    DOWNLOAD_URL="https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/download/$LATEST_TAG/$ARCH_FILE_GO"
    
    log_info "Скачиваем $ARCH_FILE_GO ($LATEST_TAG)..."
    curl -L --fail -o "$BIN_PATH_GO" "$DOWNLOAD_URL" 2>/dev/null || {
        log_error "Ошибка скачивания"
        return 1
    }
    
    chmod +x "$BIN_PATH_GO"
    
    # Создаем init-скрипт
    cat > "$INIT_PATH_GO" << 'INITSCRIPT'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy-go --host 0.0.0.0 --port 1080
    procd_set_param respawn
    procd_set_param respawn_threshold 60
    procd_set_param respawn_timeout 5
    procd_close_instance
}

stop_service() {
    procd_kill tg-ws-proxy-go
}
INITSCRIPT
    
    chmod +x "$INIT_PATH_GO"
    
    # Включаем и запускаем сервис
    /etc/init.d/tg-ws-proxy-go enable
    /etc/init.d/tg-ws-proxy-go start
    
    if pidof tg-ws-proxy-go >/dev/null 2>&1; then
        log_success "TG WS Proxy Go запущен на порту 1080"
    else
        log_error "Не удалось запустить TG WS Proxy Go"
        return 1
    fi
}

# === Настройка Redsocks ===
configure_redsocks() {
    log_info "Настраиваем Redsocks..."
    
    cat > "$REDSOCKS_CONF" << 'REDSOCKS'
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
REDSOCKS
    
    # Включаем и перезапускаем redsocks
    /etc/init.d/redsocks enable
    /etc/init.d/redsocks restart
    
    if pidof redsocks >/dev/null 2>&1; then
        log_success "Redsocks запущен на порту 12345"
    else
        log_error "Не удалось запустить Redsocks"
        return 1
    fi
}

# === Настройка nftables правил для Telegram ===
configure_nftables() {
    log_info "Настраиваем nftables правила для Telegram..."
    
    # Создаём временный файл для сбора всех IP
    TEMP_IPS="/tmp/telegram_ips_$$"
    : > "$TEMP_IPS"
    
    # 1. Добавляем статические диапазоны (CDN и основные сервера)
    cat >> "$TEMP_IPS" << 'STATIC_IPS'
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
STATIC_IPS
    
    # 2. Скачиваем динамический список из GitHub (если доступно)
    if command -v curl >/dev/null 2>&1; then
        log_info "Скачиваем актуальный список IP Telegram..."
        curl -sL --fail "$TELEGRAM_IPS_URL" -o /tmp/telegram_dynamic_$$ 2>/dev/null && {
            # Фильтруем только валидные CIDR IPv4
            grep -E '^[0-9]{1,3}(\.[0-9]{1,3}){3}/[0-9]{1,2}$' /tmp/telegram_dynamic_$$ 2>/dev/null >> "$TEMP_IPS" || true
            rm -f /tmp/telegram_dynamic_$$
            log_success "Динамический список добавлен"
        } || log_info "Не удалось скачать динамический список, используем только статические"
    fi
    
    # 3. Удаляем дубликаты и сортируем
    sort -u "$TEMP_IPS" -o "$TEMP_IPS"
    
    # 4. Создаём/обновляем nft set
    # Инициализируем set (игнорируем ошибку если уже существует)
    nft add set "$NFT_TABLE" "$NFT_SET_NAME" '{ type ipv4_addr; flags interval; }' 2>/dev/null || true
    
    # Очищаем set перед наполнением
    nft flush set "$NFT_TABLE" "$NFT_SET_NAME" 2>/dev/null || true
    
    # Добавляем IP пачками по 50 (чтобы не превысить лимит командной строки)
    log_info "Добавляем $(wc -l < "$TEMP_IPS") записей в nft set..."
    count=0
    batch=""
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        batch="$batch $ip,"
        count=$((count + 1))
        if [ $((count % 50)) -eq 0 ]; then
            batch="${batch%,}"  # убираем последнюю запятую
            nft add element "$NFT_TABLE" "$NFT_SET_NAME" "{ $batch }" 2>/dev/null || true
            batch=""
        fi
    done < "$TEMP_IPS"
    
    # Добавляем остаток
    if [ -n "$batch" ]; then
        batch="${batch%,}"
        nft add element "$NFT_TABLE" "$NFT_SET_NAME" "{ $batch }" 2>/dev/null || true
    fi
    
    rm -f "$TEMP_IPS"
    
    # 5. Создаём правило редиректа в dstnat (если ещё нет)
    # Сначала удаляем старое правило (если есть)
    nft delete rule "$NFT_TABLE" dstnat ip daddr @"$NFT_SET_NAME" tcp dport { 80, 443 } counter redirect to :12345 2>/dev/null || true
    
    # Добавляем новое правило в начало цепи
    nft insert rule "$NFT_TABLE" dstnat ip daddr @"$NFT_SET_NAME" tcp dport { 80, 443 } counter redirect to :12345
    
    log_success "nftables правила настроены"
}

# === Настройка persistence для firewall.user ===
configure_firewall_persistence() {
    log_info "Настраиваем сохранение правил после перезагрузки..."
    
    # Проверяем, есть ли уже include для firewall.user в fw4
    if ! grep -q 'fw4_compatible.*1' /etc/config/firewall 2>/dev/null; then
        # Добавляем include для firewall.user
        cat >> /etc/config/firewall << 'FWINCLUDE'

config include
    option enabled '1'
    option type 'script'
    option path '/etc/firewall.user'
    option fw4_compatible '1'
FWINCLUDE
        log_info "Добавлен include для /etc/firewall.user в /etc/config/firewall"
    fi
    
    # Создаём /etc/firewall.user с нашими правилами (для восстановления после перезагрузки)
    cat > "$FIREWALL_USER" << 'FWUSER'
#!/bin/sh
# Custom nftables rules for Telegram transparent proxy
# This file is included by fw4 on boot (fw4_compatible=1)

# Ждём инициализации fw4
sleep 2

# Создаём set если не существует
nft add set inet fw4 telegram_list '{ type ipv4_addr; flags interval; }' 2>/dev/null

# Правило редиректа для трафика к Telegram
nft list rule inet fw4 dstnat | grep -q "redirect to :12345" 2>/dev/null || \
    nft insert rule inet fw4 dstnat ip daddr @telegram_list tcp dport { 80, 443 } counter redirect to :12345
FWUSER
    
    chmod +x "$FIREWALL_USER"
    
    # Добавляем в sysupgrade.conf чтобы файл сохранился при обновлении
    if ! grep -q '/etc/firewall.user' /etc/sysupgrade.conf 2>/dev/null; then
        echo '/etc/firewall.user' >> /etc/sysupgrade.conf
        echo '/etc/redsocks.conf' >> /etc/sysupgrade.conf
        echo '/etc/init.d/tg-ws-proxy-go' >> /etc/sysupgrade.conf
    fi
    
    log_success "Persistence настроен"
}

# === Перезагрузка фаервола ===
reload_firewall() {
    log_info "Перезагружаем firewall..."
    /etc/init.d/firewall restart >/dev/null 2>&1 || {
        log_error "Не удалось перезагрузить firewall"
        return 1
    }
    sleep 2
    log_success "Firewall перезагружен"
}

# === Проверка работы ===
verify_setup() {
    echo ""
    log_info "Проверка установки..."
    
    echo -e "\n${CYAN}=== Статус сервисов ===${NC}"
    pidof tg-ws-proxy-go >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} TG WS Proxy Go: запущен" || echo -e "${RED}✗${NC} TG WS Proxy Go: не работает"
    pidof redsocks >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} Redsocks: запущен" || echo -e "${RED}✗${NC} Redsocks: не работает"
    
    echo -e "\n${CYAN}=== nftables set telegram_list ===${NC}"
    nft list set inet fw4 telegram_list 2>/dev/null | head -20
    echo "..."
    echo "Всего записей: $(nft list set inet fw4 telegram_list 2>/dev/null | grep -c 'elements = {' || echo 0)"
    
    echo -e "\n${CYAN}=== Правила dstnat ===${NC}"
    nft list chain inet fw4 dstnat 2>/dev/null | grep -A2 -B2 "12345" || echo "Правила не найдены"
    
    echo -e "\n${GREEN}=== Настройка завершена! ===${NC}"
    echo "Telegram трафик (80/443) теперь перенаправляется через TG WS Proxy Go"
    echo "Для проверки: подключитесь к устройству и попробуйте открыть telegram.org"
}

# === Основная функция ===
main() {
    echo -e "${MAGENTA}=== TG WS Proxy Go + Redsocks Installer для OpenWrt 24/25 ===${NC}\n"
    
    # Проверка прав
    [ "$(id -u)" -ne 0 ] && { log_error "Запустите скрипт от root"; exit 1; }
    
    # Проверка версии OpenWrt
    if ! grep -q 'OPENWRT_RELEASE' /etc/openwrt_release 2>/dev/null; then
        log_info "Предупреждение: возможно, это не OpenWrt или старая версия"
    fi
    
    # Пошаговое выполнение
    install_packages || exit 1
    install_tg_ws_proxy_go || exit 1
    configure_redsocks || exit 1
    configure_nftables || exit 1
    configure_firewall_persistence || exit 1
    reload_firewall || exit 1
    verify_setup
    
    pause
}

# Запуск
main "$@"
