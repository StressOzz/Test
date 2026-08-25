#!/bin/sh
# lib/common.sh — общие функции Mixomo Installer (стиль Zapret Manager)
# Подключается всеми остальными lib/*.sh, отдельно не запускается.

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_online() { echo -e "${GREEN}[ONLINE]${NC} $*"; }
log_warn()   { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_done()   { echo -e "${GREEN}$*${NC}"; }
step_fail()  { echo -e "${RED}[FAIL]${NC}"; exit 1; }

USE_APK=0
command -v apk >/dev/null 2>&1 && USE_APK=1

manage_pkg() {
    action="$1"; shift
    if [ "$USE_APK" -eq 1 ]; then
        case "$action" in
            update)  apk update ;;
            install) apk add "$@" ;;
            remove)  apk del "$@" ;;
        esac
    else
        case "$action" in
            update)  opkg update ;;
            install) opkg install "$@" ;;
            remove)  opkg remove "$@" ;;
        esac
    fi
}

# Скачивание файла с перебором зеркал/источников и повторами.
# Использование: download_file <куда_сохранить> <url1> [url2 url3 ...]
download_file() {
    _dest="$1"; shift
    for _url in "$@"; do
        if curl -Lf -s --connect-timeout 5 --max-time 30 --retry 3 --retry-delay 2 -o "$_dest" "$_url" \
           || wget -q -T 10 -O "$_dest" "$_url"; then
            [ -s "$_dest" ] && return 0
        fi
    done
    return 1
}

# Получение тега последнего релиза GitHub без обращения к API (обходит рейт-лимиты).
# Использование: get_latest_tag "owner/repo"
get_latest_tag() {
    curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/$1/releases/latest" \
        | grep -oE 'v?[0-9]+\.[0-9]+\.[0-9]+' | head -1
}

detect_mihomo_arch() {
    arch=$(uname -m)
    endian_byte=$(hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null || echo "0")
    case "$arch" in
        x86_64)
            grep -q avx2 /proc/cpuinfo && echo "amd64" || echo "amd64-compatible" ;;
        i?86)          echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*)        echo "armv7" ;;
        armv5*|armv4*) echo "armv5" ;;
        mips*)
            fpu=$(grep -c FPU /proc/cpuinfo 2>/dev/null || echo 0)
            floattype="softfloat"
            [ "$fpu" -gt 0 ] && floattype="hardfloat"
            if [ "$endian_byte" = "1" ]; then
                echo "mipsle-${floattype}"
            else
                echo "mips-${floattype}"
            fi
            ;;
        riscv64) echo "riscv64" ;;
        *)
            log_error "Архитектура $arch не распознана"
            exit 1
            ;;
    esac
}

verify_required_deps() {
    missing=0

    command -v curl >/dev/null 2>&1 || { log_error "Пакет curl не найден!"; missing=1; }

    if [ ! -f /etc/ssl/certs/ca-certificates.crt ] && [ ! -f /etc/ssl/certs/ca-bundle.crt ]; then
        log_error "Пакет ca-certificates не найден!"
        missing=1
    fi

    if [ ! -c /dev/net/tun ]; then
        modprobe tun >/dev/null 2>&1 || true
        [ -c /dev/net/tun ] || { log_error "В ядре нет поддержки TUN (/dev/net/tun)!"; missing=1; }
    fi

    [ "$missing" -eq 0 ]
}

install_deps() {
    log_online "Установка зависимостей"
    _log="/tmp/install_deps.log"

    if [ "$USE_APK" -eq 1 ]; then
        apk update > "$_log" 2>&1 || true
        _avail=$(grep -o '[0-9]* distinct packages available' "$_log" | grep -o '^[0-9]*')
        if [ -z "$_avail" ] || [ "$_avail" -eq 0 ]; then
            log_warn "apk update не вернул доступных пакетов, повторная попытка..."
            sleep 3
            apk update > "$_log" 2>&1 || true
            _avail=$(grep -o '[0-9]* distinct packages available' "$_log" | grep -o '^[0-9]*')
            if [ -z "$_avail" ] || [ "$_avail" -eq 0 ]; then
                log_error "apk update завершился без доступных пакетов:"
                cat "$_log"; rm -f "$_log"
                return 1
            fi
        fi
        apk add unzip ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl >> "$_log" 2>&1 || true
    else
        if ! opkg update > "$_log" 2>&1; then
            log_error "Ошибка обновления списков пакетов (opkg update):"
            cat "$_log"; rm -f "$_log"
            return 1
        fi
        opkg install unzip ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl libcurl4 ca-bundle >> "$_log" 2>&1 || true
    fi

    rm -f "$_log"

    verify_required_deps || { log_error "Не удалось подтвердить наличие обязательных компонентов!"; return 1; }
}
