#!/bin/sh

SCRIPT_VERSION="v0.1.2-alpha"

MT_VERSION="0.5.3"
MT_PRE_APK="pre20260305232358-r1"
MT_PRE_IPK="~git20260305232358.d47bd8b3-1"

ARCH=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2)

URL_APK="https://gitlab.com/magitrickle/magitrickle/-/jobs/13378493545/artifacts/raw/.build/magitrickle_${MT_VERSION}_${MT_PRE_APK}_openwrt_${ARCH}.apk"
URL_IPK="https://gitlab.com/magitrickle/magitrickle/-/jobs/13378493545/artifacts/raw/.build/magitrickle_${MT_VERSION}${MT_PRE_IPK}_openwrt_${ARCH}.ipk"

MIHOMO_INSTALL_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/bin/mihomo"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "${GREEN}=== $* ===${NC}"; }
log_done()  { echo -e "${GREEN}$*${NC}"; }
step_fail() { echo -e "${RED}[FAIL]${NC}"; exit 1; }

USE_APK=0
if command -v apk > /dev/null 2>&1; then
    USE_APK=1
fi

manage_pkg() {
    local action="$1"
    shift
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

detect_mihomo_arch() {
    local arch
    arch=$(uname -m)
    local endian_byte
    endian_byte=$(hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null || echo "0")

    case "$arch" in
        x86_64)        echo "amd64" ;;
        i?86)          echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*)        echo "armv7" ;;
        armv5*|armv4*) echo "armv5" ;;
        mips*)
            local fpu
            fpu=$(grep -c "FPU" /proc/cpuinfo 2>/dev/null || echo 0)
            local floattype="softfloat"
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

install_deps() {
    log_info "Установка зависимостей..."

    if [ "$USE_APK" -eq 1 ]; then
        log_info "Обновление списков пакетов..."
		apk update >/dev/null 2>&1 || { log_error "apk update не удался"; return 1; }
        apk add ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl >/dev/null 2>&1 || {
            log_error "Ошибка установки зависимостей"
            return 1
        }

    else
        log_info "Обновление списков пакетов..."
        opkg update >/dev/null 2>&1 || { log_error "opkg update не удался"; return 1; }

        opkg install ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl libcurl4 ca-bundle >/dev/null 2>&1 || {
            log_error "Ошибка установки зависимостей"
            return 1
        }
    fi
    log_info "Зависимости установлены."
}

install_mihomo() {
REQ_TMP_KB=16000
REQ_ROOT_KB=18000

AVAIL_TMP_KB=$(df -k /tmp | awk 'NR==2{print $4}')
INSTALL_DIR_PATH=$(dirname "$MIHOMO_BIN")
AVAIL_ROOT_KB=$(df -k "$INSTALL_DIR_PATH" | awk 'NR==2{print $4}')

if [ "$AVAIL_TMP_KB" -lt "$REQ_TMP_KB" ]; then
    log_error "Недостаточно места в /tmp: $((AVAIL_TMP_KB/1024)) MB (нужно $((REQ_TMP_KB/1024)) MB)"
    return 1
fi

if [ "$AVAIL_ROOT_KB" -lt "$REQ_ROOT_KB" ]; then
    log_error "Недостаточно места: $((AVAIL_ROOT_KB/1024)) MB (нужно $((REQ_ROOT_KB/1024)) MB)"
fi

[ -f /etc/init.d/mihomo ] && /etc/init.d/mihomo stop 2>/dev/null

[ -z "${MIHOMO_ARCH+x}" ] && MIHOMO_ARCH=$(detect_mihomo_arch)
echo "--> Архитектура: $(uname -m) -> файл: $MIHOMO_ARCH"

mkdir -p "$MIHOMO_INSTALL_DIR" \
         /etc/mihomo/{proxy-providers,rule-providers,rule-files,UI}

echo "$MIHOMO_ARCH" > /etc/mihomo/.arch

echo "--> Получение последней версии..."
RELEASE_TAG=$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MetaCubeX/mihomo/releases/latest | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)

[ -z "$RELEASE_TAG" ] && { log_error "Не удалось определить версию."; return 1; }

echo "--> Последняя версия: $RELEASE_TAG"

FILENAME="mihomo-linux-${MIHOMO_ARCH}-${RELEASE_TAG}.gz"
URL="https://github.com/MetaCubeX/mihomo/releases/download/${RELEASE_TAG}/${FILENAME}"
TMP="/tmp/mihomo.gz"

log_info "Скачивание $FILENAME"
echo "--> URL: $URL"

curl -Lf --retry 3 --retry-delay 2 "$URL" -o "$TMP" >/dev/null 2>&1 || { log_error "Ошибка скачивания."; return 1; }

echo "--> Распаковка..."
gunzip -c "$TMP" > "$MIHOMO_BIN" 2>/dev/null || { log_error "Ошибка распаковки."; rm -f "$TMP"; return 1; }

chmod +x "$MIHOMO_BIN"
rm -f "$TMP"

echo "--> Проверка ядра..."
"$MIHOMO_BIN" -v >/dev/null 2>&1 || { log_error "Ядро не запускается."; return 1; }

}

install_hev_tunnel() {
    log_info "Установка hev-socks5-tunnel..."

    if [ "$USE_APK" -eq 1 ]; then
        apk cache clean
        apk add hev-socks5-tunnel >/dev/null 2>&1
    else
        manage_pkg install hev-socks5-tunnel >/dev/null 2>&1
    fi

    rm -f /etc/hev-socks5-tunnel/main.yml
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml <<'EOF'
tunnel:
  name: Mihomo
  mtu: 8500
  multi-queue: false
  ipv4: 198.18.0.1
socks5:
  port: 7890
  address: 127.0.0.1
  udp: 'udp'
EOF
    chmod 600 /etc/hev-socks5-tunnel/main.yml

    echo "--> Очистка старых настроек UCI..."
    uci delete network.Mihomo 2>/dev/null || true

    local fw_section
    for fw_section in $(uci show firewall 2>/dev/null \
            | grep -E "\.name='Mihomo'" \
            | sed "s/\.name.*//"); do
        uci delete "$fw_section" 2>/dev/null || true
    done

    for fw_section in $(uci show firewall 2>/dev/null \
            | grep -E "\.(src|dest)='Mihomo'" \
            | sed -E "s/\.(src|dest).*//"); do
        uci delete "$fw_section" 2>/dev/null || true
    done

    uci delete firewall.Mihomo 2>/dev/null || true
    uci delete firewall.lan_to_Mihomo 2>/dev/null || true
    uci commit firewall
    /etc/init.d/firewall restart 2>/dev/null || true
    sleep 1

    echo "--> Настройка UCI-сервиса hev-socks5-tunnel..."
    uci set hev-socks5-tunnel.config.enabled='1'
    uci set hev-socks5-tunnel.config.configfile='/etc/hev-socks5-tunnel/main.yml'
    uci commit hev-socks5-tunnel
    /etc/init.d/hev-socks5-tunnel restart
    sleep 2

    echo "--> Настройка сетевого интерфейса..."
    uci set network.Mihomo=interface
    uci set network.Mihomo.proto='none'
    uci set network.Mihomo.device='Mihomo'
    uci commit network
    /etc/init.d/network reload

    echo "--> Настройка firewall..."
    local FW_ZONE
    FW_ZONE=$(uci add firewall zone)
    uci set "firewall.${FW_ZONE}.name=Mihomo"
    uci set "firewall.${FW_ZONE}.input=REJECT"
    uci set "firewall.${FW_ZONE}.output=REJECT"
    uci set "firewall.${FW_ZONE}.forward=REJECT"
    uci set "firewall.${FW_ZONE}.masq=1"
    uci set "firewall.${FW_ZONE}.mtu_fix=1"
    uci add_list "firewall.${FW_ZONE}.network=Mihomo"

    local FW_FWD
    FW_FWD=$(uci add firewall forwarding)
    uci set "firewall.${FW_FWD}.src=lan"
    uci set "firewall.${FW_FWD}.dest=Mihomo"

    uci commit firewall
    /etc/init.d/firewall restart
}


install_magitrickle() {
	log_info "Установка MagiTrickle..."

    local CONFIG_PATH="/etc/magitrickle/state/config.yaml"
    local BACKUP_PATH="/tmp/magitrickle_config_backup.yaml"

    [ -f "$CONFIG_PATH" ] && cp "$CONFIG_PATH" "$BACKUP_PATH"

    if [ "$USE_APK" -eq 1 ]; then
        apk del magitrickle >/dev/null 2>&1 || true
    else
        opkg remove magitrickle >/dev/null 2>&1 || true
    fi

if [ "$USE_APK" -eq 1 ]; then
    FILE=/tmp/magitrickle.apk
    curl -Lf --retry 3 --retry-delay 2 -o "$FILE" "$URL_APK" >/dev/null 2>&1 || exit 1
    apk add --allow-untrusted "$FILE" >/dev/null 2>&1 || exit 1
else
    FILE=/tmp/magitrickle.ipk
    curl -Lf --retry 3 --retry-delay 2 -o "$FILE" "$URL_IPK" >/dev/null 2>&1 || exit 1
    opkg install "$FILE" >/dev/null 2>&1 || exit 1
fi

rm -f "$FILE"

	echo "--> Установка списка для MagiTrickle..."
	confGIT="https://raw.githubusercontent.com/StressOzz/Use_WARP_on_OpenWRT/refs/heads/main/files/MagiTrickle/configAD.yaml"
	wget -q -O "$CONFIG_PATH" "$confGIT" || {
    echo -e "${RED}Не удалось скачать список!${NC}"
    return 1
	}
	echo "--> Запуск MagiTrickle..."
	/etc/init.d/magitrickle enable >/dev/null 2>&1
	/etc/init.d/magitrickle reload  >/dev/null 2>&1
	/etc/init.d/magitrickle start >/dev/null 2>&1
	/etc/init.d/magitrickle restart >/dev/null 2>&1


}

finalize_install() {
    echo "--> Выставление прав доступа..."
    chmod -R 755 /www/luci-static/resources/view/mihomo 2>/dev/null || true
    find /www/luci-static/resources/view/mihomo -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod 644 /www/luci-static/resources/view/magitrickle/magitrickle.js 2>/dev/null || true

    echo "--> Очистка кэша LuCI и перезапуск сервисов..."
    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/
    /etc/init.d/rpcd restart > /dev/null 2>&1
    /etc/init.d/uhttpd restart > /dev/null 2>&1
}

main() {
    clear
	log_done "Скрипт установки Mixomo OpenWRT $SCRIPT_VERSION"
	log_done "        от Internet Helper (StressOzz Remix)"
    echo ""

    log_step "[1/5] Установка зависимостей"
    install_deps || step_fail
    echo ""

    log_step "[2/5] Установка Mihomo"
    install_mihomo || step_fail
    echo ""

    log_step "[3/5] Установка Hev-Socks5-Tunnel"
    install_hev_tunnel || step_fail
    echo ""

    log_step "[4/5] Установка MagiTrickle"
    install_magitrickle || step_fail
    echo ""

    log_step "[5/5] Завершение"
    finalize_install || step_fail
    echo ""

    log_step "Установка Mixomo OpenWRT $SCRIPT_VERSION прошла успешно!"
}

main
