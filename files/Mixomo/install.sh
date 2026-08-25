#!/bin/sh
# Mixomo OpenWrt Installer от Internet Helper (StressOzz Remix)
# Стиль и структура — по образцу Zapret Manager: тонкий install.sh
# + lib/*.sh с логикой + assets/ со статическими файлами LuCI.
#
# Запуск:
#   ./install.sh                       — полная установка
#   ./install.sh mihomo                — только ядро Mihomo + LuCI
#   ./install.sh hev-tunnel            — только hev-socks5-tunnel
#   ./install.sh magitrickle           — только MagiTrickle
#
# Если репозиторий не склонирован целиком (например, скрипт скачан
# отдельно), install.sh сам подтянет недостающие assets/lib с GitHub.

SCRIPT_VERSION="v0.3.0"
REPO="StressOzz/Test"   # укажите свой репозиторий, если форкаете
BRANCH="main"
REPO_SUBDIR="files/Mixomo"        # путь внутри репозитория до этой папки

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LIB_DIR="$SCRIPT_DIR/lib"
ASSETS_DIR="$SCRIPT_DIR/assets"

# --- Автозагрузка недостающих файлов проекта (для запуска через curl|sh) ---
bootstrap_if_needed() {
    [ -f "$SCRIPT_DIR/common.sh" ] && return 0

    echo "Скачивание файлов Mixomo..."

    BASE="https://github.com/StressOzz/Test/raw/refs/heads/main/files/Mixomo"

    mkdir -p "$SCRIPT_DIR"

    for f in \
        common.sh \
        mihomo.sh \
        hev_tunnel.sh \
        magitrickle.sh \
        mixomo.zip
    do
        curl -fsSL "$BASE/$f" -o "$SCRIPT_DIR/$f" || {
            echo "Ошибка загрузки $f"
            exit 1
        }
    done
}
bootstrap_if_needed

. "$LIB_DIR/common.sh"
. "$LIB_DIR/mihomo.sh"
. "$LIB_DIR/hev_tunnel.sh"
. "$LIB_DIR/magitrickle.sh"

finalize_install() {
    echo "Выставление прав доступа"
    chmod -R 755 /www/luci-static/resources/view/mihomo 2>/dev/null || true
    find /www/luci-static/resources/view/mihomo -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 644 /www/luci-static/resources/view/magitrickle/magitrickle.js 2>/dev/null || true

    echo "Очистка кэша LuCI и перезапуск сервисов"
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/
    /etc/init.d/rpcd restart   >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    /etc/init.d/mihomo restart >/dev/null 2>&1
}

run_step() {
    n="$1"; total="$2"; title="$3"; shift 3
    log_done "[$n/$total] $title"
    "$@" || step_fail
    echo ""
}

run_full_install() {
    clear
    log_done "=== Mixomo OpenWrt от Internet Helper (StressOzz Remix) $SCRIPT_VERSION ==="
    echo ""

    run_step 1 6 "Установка зависимостей"        install_deps
    run_step 2 6 "Установка Mihomo"               install_mihomo
    run_step 3 6 "Установка Hev-Socks5-Tunnel"    install_hev_tunnel
    run_step 4 6 "Установка MagiTrickle"          install_magitrickle
    run_step 5 6 "Настройка MagiTrickle"          configure_magitrickle
    run_step 6 6 "Установка панели Zashboard"     install_zashboard_ui

    finalize_install || step_fail

    echo ""
    log_done "Установка Mixomo OpenWrt прошла успешно!"
    echo ""
}

case "${1:-}" in
    "" )              run_full_install ;;
    mihomo )          install_deps && install_mihomo && install_zashboard_ui && finalize_install ;;
    hev-tunnel )       install_hev_tunnel ;;
    magitrickle )      install_magitrickle && configure_magitrickle ;;
    -v|--version )     echo "$SCRIPT_VERSION" ;;
    * )
        echo "Использование: $0 [mihomo|hev-tunnel|magitrickle]"
        exit 1
        ;;
esac
