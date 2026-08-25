#!/bin/sh
# Mixomo OpenWrt Installer от Internet Helper (StressOzz Remix)

SCRIPT_VERSION="v0.3.0"

REPO="StressOzz/Test"
BRANCH="main"
REPO_SUBDIR="files/Mixomo"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# --- Автозагрузка файлов проекта ---
bootstrap_if_needed() {

    [ -f "$SCRIPT_DIR/common.sh" ] && return 0

    echo "Скачивание файлов Mixomo..."

    BASE="https://raw.githubusercontent.com/${REPO}/refs/heads/${BRANCH}/${REPO_SUBDIR}"

    mkdir -p "$SCRIPT_DIR"

    for f in \
        common.sh \
        mihomo.sh \
        hev_tunnel.sh \
        magitrickle.sh \
        mixomo.zip
    do
        echo "Скачивание $f..."

        curl -fsSL "$BASE/$f" -o "$SCRIPT_DIR/$f" || {
            echo "Ошибка загрузки $f"
            exit 1
        }
    done
}

bootstrap_if_needed


# Подключаем модули
. "$SCRIPT_DIR/common.sh"
. "$SCRIPT_DIR/mihomo.sh"
. "$SCRIPT_DIR/hev_tunnel.sh"
. "$SCRIPT_DIR/magitrickle.sh"


finalize_install() {

    echo "Очистка кэша LuCI и перезапуск сервисов"

    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/

    /etc/init.d/rpcd restart   >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1

    /etc/init.d/mihomo restart >/dev/null 2>&1 || true
}


run_step() {

    n="$1"
    total="$2"
    title="$3"

    shift 3

    echo "[$n/$total] $title"

    "$@" || {
        echo "Ошибка: $title"
        exit 1
    }

    echo
}


run_full_install() {

    clear

    echo "=================================="
    echo " Mixomo OpenWrt $SCRIPT_VERSION"
    echo "=================================="
    echo


    run_step 1 6 "Установка зависимостей" \
        install_deps

    run_step 2 6 "Установка Mihomo" \
        install_mihomo

    run_step 3 6 "Установка Hev-Socks5-Tunnel" \
        install_hev_tunnel

    run_step 4 6 "Установка MagiTrickle" \
        install_magitrickle

    run_step 5 6 "Настройка MagiTrickle" \
        configure_magitrickle

    run_step 6 6 "Установка Zashboard" \
        install_zashboard_ui


    finalize_install


    echo
    echo "Установка Mixomo завершена!"
}


case "${1:-}" in

    "")
        run_full_install
        ;;

    mihomo)
        install_deps &&
        install_mihomo &&
        install_zashboard_ui &&
        finalize_install
        ;;

    hev-tunnel)
        install_hev_tunnel
        ;;

    magitrickle)
        install_magitrickle &&
        configure_magitrickle
        ;;

    -v|--version)
        echo "$SCRIPT_VERSION"
        ;;

    *)
        echo "Использование:"
        echo "$0 [mihomo|hev-tunnel|magitrickle]"
        exit 1
        ;;

esac
