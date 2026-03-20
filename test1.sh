#!/bin/sh
# Скрипт установки tg-ws-proxy для OpenWRT
# Поддерживает OpenWRT 24.x (opkg) и OpenWRT 25.x (apk)

set -e

TG_PROXY_DIR="/opt/tg-ws-proxy"
INIT_SCRIPT="/etc/init.d/tg-ws-proxy"
PROXY_HOST="0.0.0.0"
PROXY_PORT="1080"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log_info() {
    echo "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo "${RED}[ERROR]${NC} $1"
}

# Определение версии OpenWRT и пакетного менеджера
detect_system() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MANAGER="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        log_info "Обнаружена OpenWRT 25.x (используется apk)"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MANAGER="opkg"
        PKG_UPDATE="opkg update"
        PKG_INSTALL="opkg install"
        log_info "Обнаружена OpenWRT 24.x (используется opkg)"
    else
        log_error "Не удалось определить пакетный менеджер"
        exit 1
    fi
}

# Проверка наличия Python
check_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        log_warn "Python3 не установлен. Устанавливаю..."
        $PKG_UPDATE
        if [ "$PKG_MANAGER" = "apk" ]; then
            $PKG_INSTALL python3 python3-pip
        else
            $PKG_INSTALL python3-light python3-pip
        fi
    else
        log_info "Python3 уже установлен"
    fi
    
    # Проверка pip
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        log_warn "pip не установлен. Устанавливаю..."
        if [ "$PKG_MANAGER" = "apk" ]; then
            $PKG_INSTALL python3-pip
        else
            $PKG_INSTALL python3-pip
        fi
    fi
}

# Установка git если необходимо
check_git() {
    if ! command -v git >/dev/null 2>&1; then
        log_warn "Git не установлен. Устанавливаю..."
        $PKG_INSTALL git
    else
        log_info "Git уже установлен"
    fi
}

# Установка tg-ws-proxy
install_tg_proxy() {
    log_info "Установка tg-ws-proxy..."
    
    # Создание директории если не существует
    mkdir -p "$TG_PROXY_DIR"
    
    # Клонирование или обновление репозитория
    if [ -d "$TG_PROXY_DIR/.git" ]; then
        log_info "Обновление существующего репозитория..."
        cd "$TG_PROXY_DIR"
        git pull
    else
        log_info "Клонирование репозитория..."
        rm -rf "$TG_PROXY_DIR"
        git clone https://github.com/Flowseal/tg-ws-proxy "$TG_PROXY_DIR"
        cd "$TG_PROXY_DIR"
    fi
    
    # Установка Python пакета
    log_info "Установка Python зависимостей..."
    if command -v pip3 >/dev/null 2>&1; then
        pip3 install -e "$TG_PROXY_DIR"
    else
        pip install -e "$TG_PROXY_DIR"
    fi
    
    # Проверка успешности установки
    if command -v tg-ws-proxy >/dev/null 2>&1; then
        log_info "tg-ws-proxy успешно установлен"
    else
        log_warn "tg-ws-proxy не найден в PATH, создаю симлинк..."
        ln -sf "$TG_PROXY_DIR/tg_ws_proxy/main.py" /usr/bin/tg-ws-proxy
        chmod +x /usr/bin/tg-ws-proxy
    fi
}

# Создание init скрипта
create_init_script() {
    log_info "Создание init скрипта..."
    
    cat > "$INIT_SCRIPT" << EOF
#!/bin/sh /etc/rc.common

START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy --host $PROXY_HOST --port $PROXY_PORT
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
EOF
    
    chmod +x "$INIT_SCRIPT"
    log_info "Init скрипт создан: $INIT_SCRIPT"
}

# Настройка автозапуска
enable_service() {
    log_info "Настройка автозапуска..."
    
    if [ "$PKG_MANAGER" = "apk" ]; then
        # Для OpenWRT 25.x с apk и procd
        if [ -f "$INIT_SCRIPT" ]; then
            # Перезагрузка конфигурации procd
            /etc/init.d/tg-ws-proxy enable
            log_info "Сервис добавлен в автозапуск"
        fi
    else
        # Для OpenWRT 24.x с opkg
        if [ -f "$INIT_SCRIPT" ]; then
            /etc/init.d/tg-ws-proxy enable
            log_info "Сервис добавлен в автозапуск"
        fi
    fi
}

# Запуск сервиса
start_service() {
    log_info "Запуск tg-ws-proxy..."
    
    # Остановка если уже запущен
    if [ -f "$INIT_SCRIPT" ]; then
        /etc/init.d/tg-ws-proxy stop 2>/dev/null || true
        sleep 2
        /etc/init.d/tg-ws-proxy start
    fi
    
    # Проверка статуса
    sleep 2
    if pgrep -f "tg-ws-proxy" > /dev/null; then
        log_info "Сервис успешно запущен"
    else
        log_error "Не удалось запустить сервис. Проверьте логи: logread | grep tg-ws-proxy"
    fi
}

# Вывод информации о настройке
show_info() {
    # Получение IP адреса роутера
    ROUTER_IP=$(ip addr show br-lan 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    if [ -z "$ROUTER_IP" ]; then
        ROUTER_IP=$(ip addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -n1)
    fi
    if [ -z "$ROUTER_IP" ]; then
        ROUTER_IP="IP_ВАШЕГО_РОУТЕРА"
    fi
    
    echo ""
    echo "========================================="
    echo "${GREEN}Установка tg-ws-proxy завершена!${NC}"
    echo "========================================="
    echo ""
    echo "Настройки прокси для Telegram:"
    echo "  Тип прокси: SOCKS5"
    echo "  Адрес: $ROUTER_IP"
    echo "  Порт: $PROXY_PORT"
    echo ""
    echo "Команды управления:"
    echo "  Запуск:    /etc/init.d/tg-ws-proxy start"
    echo "  Остановка: /etc/init.d/tg-ws-proxy stop"
    echo "  Перезапуск:/etc/init.d/tg-ws-proxy restart"
    echo "  Статус:    /etc/init.d/tg-ws-proxy status"
    echo ""
    echo "Проверка логов: logread | grep tg-ws-proxy"
    echo ""
    echo "Для тестирования (без сервиса):"
    echo "  tg-ws-proxy --host 0.0.0.0 --port $PROXY_PORT"
    echo ""
    echo "========================================="
}

# Проверка прав root
check_root() {
    if [ "$(id -u)" != "0" ]; then
        log_error "Скрипт должен быть запущен с правами root"
        exit 1
    fi
}

# Основная функция
main() {
    echo "========================================="
    echo "Установка tg-ws-proxy для OpenWRT"
    echo "========================================="
    
    check_root
    detect_system
    check_python
    check_git
    install_tg_proxy
    create_init_script
    enable_service
    start_service
    show_info
}

# Запуск основной функции
main
