#!/bin/sh
# =============================================================================
# TG WS Proxy Manager by StressOzz (Refactored)
# Управление прокси-серверами для Telegram: Go / Rust / Python
# =============================================================================
# Требования: OpenWrt/Entware, root-доступ, curl/wget
# Лицензия: MIT
# =============================================================================

# -----------------------------------------------------------------------------
# КОНФИГУРАЦИЯ (можно переопределить в /etc/tg-ws-proxy-manager.conf)
# -----------------------------------------------------------------------------
readonly CONFIG_FILE="/etc/tg-ws-proxy-manager.conf"
readonly LOG_FILE="/var/log/tg-ws-proxy-manager.log"
readonly TMP_DIR="/tmp/tg-ws-proxy-manager"

# Пути по умолчанию
: "${BIN_PATH_GO:=/usr/bin/tg-ws-proxy-go}"
: "${INIT_PATH_GO:=/etc/init.d/tg-ws-proxy-go}"
: "${BIN_PATH_RS:=/usr/bin/tg-ws-proxy-rs}"
: "${INIT_PATH_RS:=/etc/init.d/tg-ws-proxy-rs}"
: "${BIN_PATH_PH:=/usr/bin/tg-ws-proxy}"
: "${INIT_PATH_PH:=/etc/init.d/tg-ws-proxy}"

# Порты
: "${PORT_GO:=1080}"
: "${PORT_RS:=2443}"
: "${PORT_PH:=1443}"

# Репозитории
: "${REPO_GO:=d0mhate/-tg-ws-proxy-Manager-go}"
: "${REPO_RS:=valnesfjord/tg-ws-proxy-rs}"
: "${REPO_PH:=Flowseal/tg-ws-proxy}"
: "${BRANCH_PH:=master}"

# Цвета (с проверкой терминала)
if [ -t 1 ]; then
    GREEN="\033[1;32m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"
    CYAN="\033[1;36m"; RED="\033[1;31m"; BLUE="\033[0;34m"; NC="\033[0m"
    BOLD="\033[1m"
else
    GREEN=""; YELLOW=""; MAGENTA=""; CYAN=""; RED=""; BLUE=""; NC=""; BOLD=""
fi

# Глобальные флаги
DRY_RUN=0
VERBOSE=0
FORCE=0

# -----------------------------------------------------------------------------
# УТИЛИТЫ И ЛОГИРОВАНИЕ
# -----------------------------------------------------------------------------

log() {
    local level="$1"; shift
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
    [ "$VERBOSE" -eq 1 ] && echo "$msg" >&2
}

info()  { log "INFO" "$@"; echo -e "${CYAN}ℹ${NC} $*" >&2; }
success(){ log "OK" "$@"; echo -e "${GREEN}✓${NC} $*" >&2; }
warn()  { log "WARN" "$@"; echo -e "${YELLOW}⚠${NC} $*" >&2; }
error() { log "ERROR" "$@"; echo -e "${RED}✗${NC} $*" >&2; }

die() {
    error "$@"
    exit 1
}

# Проверка прав
check_root() {
    [ "$(id -u)" -eq 0 ] || die "Запустите скрипт от имени root"
}

# Интерактивная пауза
pause() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    if [ -t 0 ]; then
        printf "\n${YELLOW}Нажмите Enter для продолжения...${NC}"
        read -r _ 2>/dev/null || true
    else
        sleep 2
    fi
}

# -----------------------------------------------------------------------------
# ОПРЕДЕЛЕНИЕ ПАКЕТНОГО МЕНЕДЖЕРА И АРХИТЕКТУРЫ
# -----------------------------------------------------------------------------

detect_pkg_manager() {
    if command -v opkg >/dev/null 2>&1; then
        PKG_CMD="opkg"
        PKG_UPDATE="opkg update"
        PKG_INSTALL="opkg install"
        PKG_REMOVE="opkg remove --autoremove --force-removal-of-dependent-packages"
        PKG_LIST="opkg list"
        PKG_INSTALLED="opkg list-installed"
        ARCH="$(opkg print-architecture 2>/dev/null | awk 'END{print $2}')"
    elif command -v apk >/dev/null 2>&1; then
        PKG_CMD="apk"
        PKG_UPDATE="apk update"
        PKG_INSTALL="apk add"
        PKG_REMOVE="apk del"
        PKG_LIST="apk search"
        PKG_INSTALLED="apk info"
        ARCH="$(apk --print-arch 2>/dev/null)"
    else
        die "Не найдены поддерживаемые пакетные менеджеры (opkg/apk)"
    fi
    info "Пакетный менеджер: $PKG_CMD, Архитектура: $ARCH"
}

# Получение имени файла для Rust-версии
get_rust_filename() {
    case "$ARCH" in
        aarch64*|arm64) echo "tg-ws-proxy-aarch64-unknown-linux-musl.tar.gz" ;;
        x86_64|amd64)   echo "tg-ws-proxy-x86_64-unknown-linux-musl.tar.gz" ;;
        *) echo ""; return 1 ;;
    esac
}

# Получение имени файла для Go-версии
get_go_filename() {
    case "$ARCH" in
        aarch64*|arm64)     echo "tg-ws-proxy-openwrt-aarch64" ;;
        armv7*|armhf|armv7l) echo "tg-ws-proxy-openwrt-armv7" ;;
        mipsel_24kc|mipsel*) echo "tg-ws-proxy-openwrt-mipsel_24kc" ;;
        mips_24kc|mips*)     echo "tg-ws-proxy-openwrt-mips_24kc" ;;
        x86_64|amd64)        echo "tg-ws-proxy-openwrt-x86_64" ;;
        *) echo ""; return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# СЕТЕВЫЕ ФУНКЦИИ С ПОВТОРНЫМИ ПОПЫТКАМИ
# -----------------------------------------------------------------------------

download_with_retry() {
    local url="$1" output="$2" max_attempts="${3:-3}" timeout="${4:-30}"
    local attempt=1

    [ "$DRY_RUN" -eq 1 ] && { info "[DRY-RUN] Скачивание: $url"; return 0; }

    while [ $attempt -le $max_attempts ]; do
        info "Скачивание: $url (попытка $attempt/$max_attempts)"
        if curl -L --fail --connect-timeout "$timeout" -o "$output" "$url" 2>/dev/null; then
            [ -s "$output" ] && return 0
        fi
        warn "Попытка $attempt не удалась, ожидание 2с..."
        sleep 2
        attempt=$((attempt + 1))
    done
    return 1
}

get_latest_tag() {
    local repo="$1"
    local url="https://github.com/$repo/releases/latest"
    local tag
    tag="$(curl -Ls -o /dev/null -w '%{url_effective}' "$url" 2>/dev/null | sed 's#.*/tag/##')"
    echo "$tag"
}

verify_checksum() {
    local file="$1" expected="$2"
    [ -z "$expected" ] && return 0  # Пропускаем если нет хеша
    local actual
    actual="$(sha256sum "$file" 2>/dev/null | awk '{print $1}' || md5sum "$file" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || return 1
}

# -----------------------------------------------------------------------------
# УПРАВЛЕНИЕ СЕРВИСАМИ (OpenWrt procd)
# -----------------------------------------------------------------------------

create_init_script() {
    local name="$1" bin_path="$2" port="${3:-}" secret_var="${4:-}" extra_args="${5:-}"
    local init_path="/etc/init.d/$name"

    [ "$DRY_RUN" -eq 1 ] && { info "[DRY-RUN] Создание init-скрипта: $init_path"; return 0; }

    cat << EOF > "$init_path"
#!/bin/sh /etc/rc.common
START=99
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command $bin_path --host 0.0.0.0 ${port:+--port $port} ${extra_args}
    ${secret_var:+procd_set_param env $secret_var}
    procd_set_param respawn
    procd_set_param respawn_threshold 30
    procd_close_instance
}

stop_service() { procd_kill "$name"; }
reload_service() { procd_send_signal "$name"; }
EOF
    chmod +x "$init_path"
    info "Создан init-скрипт: $init_path"
}

service_control() {
    local name="$1" action="$2"
    local init="/etc/init.d/$name"
    
    [ ! -x "$init" ] && { warn "Init-скрипт $init не найден или не исполняемый"; return 1; }
    
    if [ "$DRY_RUN" -eq 1 ]; then
        info "[DRY-RUN] $init $action"
        return 0
    fi
    
    "$init" "$action" >/dev/null 2>&1
}

is_service_running() {
    local name="$1" pidof_cmd="$2"
    [ "$DRY_RUN" -eq 1 ] && return 1
    pidof "$pidof_cmd" >/dev/null 2>&1 || pgrep -f "$name" >/dev/null 2>&1
}

# -----------------------------------------------------------------------------
# УСТАНОВКА: RUST
# -----------------------------------------------------------------------------

install_rust_version() {
    info "Установка TG WS Proxy (Rust)"
    
    local arch_file
    arch_file="$(get_rust_filename)" || die "Архитектура $ARCH не поддерживается для Rust-версии"
    
    local tag url tmp_archive tmp_extract
    tag="$(get_latest_tag "$REPO_RS")" || die "Не удалось получить последнюю версию Rust"
    [ -z "$tag" ] && die "Пустой тег версии Rust"
    
    url="https://github.com/$REPO_RS/releases/download/$tag/$arch_file"
    tmp_archive="$TMP_DIR/rust.tar.gz"
    tmp_extract="$TMP_DIR/rust_extract"

    # Зависимости
    command -v curl >/dev/null 2>&1 || {
        info "Установка curl..."
        $PKG_UPDATE >/dev/null 2>&1 && $PKG_INSTALL curl >/dev/null 2>&1 || die "Не удалось установить curl"
    }

    mkdir -p "$TMP_DIR" "$tmp_extract"
    
    # Скачивание
    download_with_retry "$url" "$tmp_archive" || die "Ошибка скачивания архива Rust"
    
    # Распаковка
    tar -xzf "$tmp_archive" -C "$tmp_extract" || die "Ошибка распаковки"
    
    # Установка бинарника
    local bin_src
    bin_src="$(find "$tmp_extract" -type f -name 'tg-ws-proxy*' | head -1)"
    [ -z "$bin_src" ] && die "Не найден бинарный файл в архиве"
    
    mkdir -p "$(dirname "$BIN_PATH_RS")"
    mv "$bin_src" "$BIN_PATH_RS"
    chmod +x "$BIN_PATH_RS"
    
    # Очистка
    rm -rf "$tmp_extract" "$tmp_archive"
    
    # Генерация секрета и создание сервиса
    local secret
    secret="$(head -c16 /dev/urandom | hexdump -e '16/1 "%02x"')"
    
    create_init_script "tg-ws-proxy-rs" "$BIN_PATH_RS" "$PORT_RS" "SECRET=$secret"
    
    # Запуск
    service_control "tg-ws-proxy-rs" enable
    service_control "tg-ws-proxy-rs" start
    sleep 1
    
    if is_service_running "tg-ws-proxy-rs" "tg-ws-proxy-rs"; then
        success "TG WS Proxy Rust запущен на порту $PORT_RS"
        echo -e "\n${YELLOW}Подключайтесь в Telegram:${NC}"
        echo "tg://proxy?server=$(get_local_ip)&port=$PORT_RS&secret=dd$secret"
    else
        error "Сервис не запустился! Проверьте логи: $LOG_FILE"
        return 1
    fi
    pause
}

remove_rust_version() {
    info "Удаление TG WS Proxy (Rust)"
    
    service_control "tg-ws-proxy-rs" stop
    service_control "tg-ws-proxy-rs" disable
    
    rm -f "$BIN_PATH_RS" "$INIT_PATH_RS"
    success "Rust-версия удалена"
    pause
}

# -----------------------------------------------------------------------------
# УСТАНОВКА: PYTHON
# -----------------------------------------------------------------------------

install_python_version() {
    info "Установка TG WS Proxy (Python)"
    
    # Проверка места
    local free_space
    free_space="$(df -m /root 2>/dev/null | awk 'NR==2 {print $4+0}')"
    [ "$free_space" -lt 50 ] && die "Недостаточно места на /root (требуется ≥50MB)"

    # Проверка пакетов
    local required_pkgs="python3-light python3-pip python3-cryptography unzip"
    for pkg in $required_pkgs; do
        if ! $PKG_LIST 2>/dev/null | grep -qw "$pkg"; then
            die "Пакет $pkg недоступен для архитектуры $ARCH"
        fi
    done

    # Установка зависимостей
    $PKG_UPDATE >/dev/null 2>&1 || warn "Не удалось обновить список пакетов"
    $PKG_INSTALL $required_pkgs >/dev/null 2>&1 || die "Не удалось установить зависимости"

    # Скачивание исходников
    local src_url="https://github.com/$REPO_PH/archive/refs/heads/$BRANCH_PH.zip"
    local src_dir="/root/tg-ws-proxy"
    
    rm -rf "$src_dir" "$TMP_DIR/ph_src"
    mkdir -p "$TMP_DIR"
    
    download_with_retry "$src_url" "$TMP_DIR/ph.zip" || die "Ошибка скачивания Python-версии"
    
    mkdir -p "$TMP_DIR/ph_src"
    unzip -q "$TMP_DIR/ph.zip" -d "$TMP_DIR/ph_src" || die "Ошибка распаковки"
    
    mv "$TMP_DIR/ph_src"/*-main "$src_dir" 2>/dev/null || mv "$TMP_DIR/ph_src"/* "$src_dir"
    rm -f "$TMP_DIR/ph.zip"
    
    # Установка через pip
    cd "$src_dir"
    pip install --root-user-action=ignore --no-deps --disable-pip-version-check -e . >/dev/null 2>&1 || \
        python3 -m pip install --root-user-action=ignore --no-deps -e . >/dev/null 2>&1 || \
        die "Ошибка установки Python-пакета"

    # Секрет и сервис
    local secret
    secret="$(head -c16 /dev/urandom | hexdump -e '16/1 "%02x"')"
    
    create_init_script "tg-ws-proxy" "$BIN_PATH_PH" "$PORT_PH" "SECRET=$secret"
    
    service_control "tg-ws-proxy" enable
    service_control "tg-ws-proxy" start
    sleep 1
    
    if is_service_running "tg-ws-proxy" "tg-ws-proxy"; then
        success "TG WS Proxy Python запущен на порту $PORT_PH"
        echo -e "\n${YELLOW}Подключайтесь в Telegram:${NC}"
        echo "tg://proxy?server=$(get_local_ip)&port=$PORT_PH&secret=dd$secret"
    else
        error "Сервис не запустился!"
        return 1
    fi
    pause
}

remove_python_version() {
    info "Удаление TG WS Proxy (Python)"
    
    service_control "tg-ws-proxy" stop
    service_control "tg-ws-proxy" disable
    
    # Удаление pip-пакета
    pip uninstall -y tg-ws-proxy >/dev/null 2>&1 || \
    python3 -m pip uninstall -y tg-ws-proxy >/dev/null 2>&1 || true
    
    # Удаление зависимостей (осторожно)
    $PKG_REMOVE python3-light python3-pip python3-cryptography unzip >/dev/null 2>&1 || true
    
    # Очистка файлов
    rm -rf /root/tg-ws-proxy "$BIN_PATH_PH" "$INIT_PATH_PH"
    rm -rf /root/.cache/pip /root/.local/lib/python* 2>/dev/null || true
    
    success "Python-версия удалена"
    pause
}

# -----------------------------------------------------------------------------
# УСТАНОВКА: GO
# -----------------------------------------------------------------------------

install_go_version() {
    info "Установка TG WS Proxy (Go)"
    
    local arch_file
    arch_file="$(get_go_filename)" || die "Архитектура $ARCH не поддерживается для Go-версии"
    
    local tag url
    tag="$(get_latest_tag "$REPO_GO")" || die "Не удалось получить версию Go"
    [ -z "$tag" ] && die "Пустой тег версии Go"
    
    url="https://github.com/$REPO_GO/releases/download/$tag/$arch_file"

    command -v curl >/dev/null 2>&1 || {
        $PKG_UPDATE >/dev/null 2>&1 && $PKG_INSTALL curl >/dev/null 2>&1 || die "Не удалось установить curl"
    }

    mkdir -p "$(dirname "$BIN_PATH_GO")"
    
    download_with_retry "$url" "$BIN_PATH_GO" || die "Ошибка скачивания бинарника Go"
    chmod +x "$BIN_PATH_GO"
    
    # Создаём сервис (Go-версия обычно не требует секрет)
    create_init_script "tg-ws-proxy-go" "$BIN_PATH_GO" "$PORT_GO" "" "--protocol socks5"
    
    service_control "tg-ws-proxy-go" enable
    service_control "tg-ws-proxy-go" start
    sleep 1
    
    if is_service_running "tg-ws-proxy-go" "tg-ws-proxy-go"; then
        success "TG WS Proxy Go запущен на порту $PORT_GO (SOCKS5)"
        echo -e "\n${YELLOW}Настройки для Telegram:${NC}"
        echo "Тип: SOCKS5 | Хост: $(get_local_ip) | Порт: $PORT_GO"
    else
        error "Сервис не запустился!"
        return 1
    fi
    pause
}

remove_go_version() {
    info "Удаление TG WS Proxy (Go)"
    
    service_control "tg-ws-proxy-go" stop
    service_control "tg-ws-proxy-go" disable
    
    rm -f "$BIN_PATH_GO" "$INIT_PATH_GO"
    success "Go-версия удалена"
    pause
}

# -----------------------------------------------------------------------------
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# -----------------------------------------------------------------------------

get_local_ip() {
    # Пробуем разные методы получения локального IP
    ip -4 route get 1 2>/dev/null | awk '{print $7; exit}' || \
    ifconfig br-lan 2>/dev/null | grep 'inet addr' | awk '{print $2}' | cut -d: -f2 || \
    uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1 || \
    hostname -I 2>/dev/null | awk '{print $1}' || \
    echo "192.168.1.1"  # fallback
}

check_disk_space() {
    local required_mb="${1:-25}"
    local available
    available="$(df -m / 2>/dev/null | awk 'NR==2 {print $4}')"
    [ "$available" -ge "$required_mb" ] || {
        error "Недостаточно места: требуется ${required_mb}MB, доступно ${available}MB"
        return 1
    }
}

show_status() {
    echo -e "\n${BOLD}Статус сервисов:${NC}"
    
    # Python
    if is_service_running "tg-ws-proxy" "tg-ws-proxy"; then
        echo -e "  ${GREEN}●${NC} Python: запущен (порт $PORT_PH, MTProto)"
    elif [ -f "$BIN_PATH_PH" ] || [ -d "/root/tg-ws-proxy" ]; then
        echo -e "  ${YELLOW}○${NC} Python: установлен, но не запущен"
    else
        echo -e "  ${RED}○${NC} Python: не установлен"
    fi
    
    # Rust
    if is_service_running "tg-ws-proxy-rs" "tg-ws-proxy-rs"; then
        echo -e "  ${GREEN}●${NC} Rust: запущен (порт $PORT_RS, MTProto)"
    elif [ -f "$BIN_PATH_RS" ]; then
        echo -e "  ${YELLOW}○${NC} Rust: установлен, но не запущен"
    else
        echo -e "  ${RED}○${NC} Rust: не установлен"
    fi
    
    # Go
    if is_service_running "tg-ws-proxy-go" "tg-ws-proxy-go"; then
        echo -e "  ${GREEN}●${NC} Go: запущен (порт $PORT_GO, SOCKS5)"
    elif [ -f "$BIN_PATH_GO" ]; then
        echo -e "  ${YELLOW}○${NC} Go: установлен, но не запущен"
    else
        echo -e "  ${RED}○${NC} Go: не установлен"
    fi
}

# -----------------------------------------------------------------------------
# МЕНЮ
# -----------------------------------------------------------------------------

show_menu() {
    clear
    cat << EOF
╔════════════════════════════════════════╗
║  ${BLUE}${BOLD}TG WS Proxy Manager${NC} (Refactored)  ║
║  by StressOzz                          ║
╚════════════════════════════════════════╝

EOF
    show_status
    
    echo -e "\n${YELLOW}Действия:${NC}"
    
    # Опции для Go
    if [ -f "$BIN_PATH_GO" ]; then
        echo -e "  ${CYAN}[1]${NC} Удалить Go-версию (SOCKS5, порт $PORT_GO)"
    else
        echo -e "  ${CYAN}[1]${NC} Установить Go-версию (SOCKS5, порт $PORT_GO)"
    fi
    
    # Опции для Rust
    if [ -f "$BIN_PATH_RS" ]; then
        echo -e "  ${CYAN}[2]${NC} Удалить Rust-версию (MTProto, порт $PORT_RS)"
    else
        echo -e "  ${CYAN}[2]${NC} Установить Rust-версию (MTProto, порт $PORT_RS)"
    fi
    
    # Опции для Python
    if [ -f "$BIN_PATH_PH" ] || [ -d "/root/tg-ws-proxy" ]; then
        echo -e "  ${CYAN}[3]${NC} Удалить Python-версию (MTProto, порт $PORT_PH)"
    else
        echo -e "  ${CYAN}[3]${NC} Установить Python-версию (MTProto, порт $PORT_PH)"
    fi
    
    echo -e "  ${CYAN}[R]${NC} Перезапустить все сервисы"
    echo -e "  ${CYAN}[L]${NC} Показать логи"
    echo -e "  ${CYAN}[Enter]${NC} Выход"
    echo -e "\n${YELLOW}Выберите действие:${NC} "
}

handle_menu_choice() {
    read -r choice
    case "$choice" in
        1) [ -f "$BIN_PATH_GO" ] && remove_go_version || install_go_version ;;
        2) [ -f "$BIN_PATH_RS" ] && remove_rust_version || install_rust_version ;;
        3) [ -f "$BIN_PATH_PH" ] || [ -d "/root/tg-ws-proxy" ] && remove_python_version || install_python_version ;;
        [rR]) 
            info "Перезапуск сервисов..."
            for svc in tg-ws-proxy-go tg-ws-proxy-rs tg-ws-proxy; do
                [ -x "/etc/init.d/$svc" ] && service_control "$svc" restart
            done
            pause ;;
        [lL])
            [ -f "$LOG_FILE" ] && tail -50 "$LOG_FILE" || echo "Лог-файл пуст"
            pause ;;
        *) exit 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# ОБРАБОТКА АРГУМЕНТОВ КОМАНДНОЙ СТРОКИ
# -----------------------------------------------------------------------------

show_help() {
    cat << EOF
${BOLD}TG WS Proxy Manager${NC} — управление прокси для Telegram

Использование: $0 [опции]

Опции:
  -n, --dry-run     Имитация действий без изменений
  -v, --verbose     Подробный вывод
  -f, --force       Пропускать некоторые проверки
  -h, --help        Показать эту справку
  --install-go      Установить Go-версию
  --install-rust    Установить Rust-версию  
  --install-python  Установить Python-версию
  --remove-all      Удалить все версии

Примеры:
  $0                    # Интерактивный режим
  $0 --install-rust     # Установка Rust в фоновом режиме
  $0 -nv --install-go   # Сухой прогон + подробный вывод
EOF
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -n|--dry-run) DRY_RUN=1; shift ;;
            -v|--verbose) VERBOSE=1; shift ;;
            -f|--force) FORCE=1; shift ;;
            -h|--help) show_help; exit 0 ;;
            --install-go) install_go_version; exit 0 ;;
            --install-rust) install_rust_version; exit 0 ;;
            --install-python) install_python_version; exit 0 ;;
            --remove-all)
                remove_go_version 2>/dev/null || true
                remove_rust_version 2>/dev/null || true
                remove_python_version 2>/dev/null || true
                exit 0 ;;
            *) die "Неизвестный аргумент: $1 (используйте --help)" ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# ТОЧКА ВХОДА
# -----------------------------------------------------------------------------

main() {
    check_root
    parse_args "$@"
    detect_pkg_manager
    
    # Создаём директорию для логов
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    
    # Инициализация
    mkdir -p "$TMP_DIR"
    trap 'rm -rf "$TMP_DIR"' EXIT
    
    info "Запуск менеджера (arch=$ARCH, pkg=$PKG_CMD)"
    
    # Интерактивный режим
    while true; do
        show_menu
        handle_menu_choice
    done
}

# Запуск
main "$@"
