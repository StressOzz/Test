#!/bin/sh
set -u

GREEN='\\033[0;32m' RED='\\033[0;31m' NC='\\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_step()  { echo -e "${GREEN}=== $* ===${NC}"; }
log_done()  { echo -e "${GREEN}$*${NC}"; }

is_pkg_installed() { opkg list-installed | grep -q "^$1 "; }

main() {
    clear
    log_done "ПОЛНАЯ ЧИСТКА ВСЕХ КАТАЛОГОВ"
    echo ""

    log_step "Сервисы off"
    for svc in mihomo hev-socks5-tunnel magitrickle; do
        /etc/init.d/$svc stop 2>/dev/null
        /etc/init.d/$svc disable 2>/dev/null
    done

    log_step "Пакеты rm"
    for pkg in hev-socks5-tunnel magitrickle_mod magitrickle kmod-nft-tproxy; do
        is_pkg_installed $pkg && opkg remove $pkg >/dev/null 2>&1 && echo "  $pkg ✓"
    done

    log_step "ВСЕ /etc/ каталоги/файлы"
    rm -rf /etc/{mihomo,hev-socks5-tunnel,magitrickle}
    rm -rf /etc/config/{hev-socks5-tunnel,mihomo}
    rm -f /etc/config/hev-socks5-tunnel /etc/magitrickle/state/config.yaml*

    # LuCI + init.d + bin
    rm -rf /www/luci-static/resources/view/{mihomo,magitrickle}
    rm -f /usr/bin/mihomo
    rm -f /etc/init.d/{mihomo,hev-socks5-tunnel,magitrickle}
    rm -f /usr/share/luci/menu.d/luci-app-{mihomo,magitrickle}.json
    rm -f /usr/share/rpcd/acl.d/luci-app-mihomo.json

    # 4. LuCI КЭШ
    log_step "LuCI чистка"
    rm -rf /tmp/luci-*
    /etc/init.d/rpcd restart >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1

    echo ""
    log_done "ВСЁ УДАЛЕНО! Интернет жив. Reboot? (y/N)"
    read -r ans
    case $ans in y|Y) reboot;; esac
}

main
