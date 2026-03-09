#!/bin/sh
set -eu

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}-->${CYAN} $*${NС}"; }

PKG_REMOVE=""
if command -v apk >/dev/null 2>&1; then
    PKG_REMOVE="apk del"
else
    PKG_REMOVE="opkg remove"
fi

log "Stop/disable services"
for svc in mihomo hev-socks5-tunnel magitrickle; do
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc stop >/dev/null 2>&1 || true
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc disable >/dev/null 2>&1 || true
done

log "Remove Mihomo"
rm -f /usr/bin/mihomo /etc/init.d/mihomo /etc/mihomo.arch 2>/dev/null || true
rm -rf /etc/mihomo 2>/dev/null || true

log "Remove LuCI files"
rm -f /usr/share/luci/menu.d/luci-app-mihomo.json 2>/dev/null || true
rm -f /usr/share/rpcd/acl.d/luci-app-mihomo.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/mihomo 2>/dev/null || true

rm -f /usr/share/luci/menu.d/luci-app-magitrickle.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/magitrickle 2>/dev/null || true

log "Remove Hev & Magi configs"
rm -rf /etc/hev-socks5-tunnel 2>/dev/null || true
rm -f /etc/config/hev-socks5-tunnel /etc/config/hev-socks5-tunnel-opkg 2>/dev/null || true
rm -rf /etc/magitrickle 2>/dev/null || true
rm -f /tmp/magitrickleconfigbackup.yaml 2>/dev/null || true

log "Clean UCI"
uci -q delete network.Mihomo || true
uci -q delete firewall.Mihomo || true
uci -q delete firewall.lan_to_Mihomo || true
uci -q delete firewall.lantoMihomo || true
uci -q delete hev-socks5-tunnel || true
uci -q delete hev-socks5-tunnel.config || true

uci -q commit network || true
uci -q commit firewall || true
uci -q commit hev-socks5-tunnel || true

log "Remove packages"
$PKG_REMOVE hev-socks5-tunnel >/dev/null 2>&1 || true
$PKG_REMOVE magitrickle_mod >/dev/null 2>&1 || true
$PKG_REMOVE magitrickle >/dev/null 2>&1 || true
$PKG_REMOVE kmod-nft-tproxy >/dev/null 2>&1 || true

log "Clear LuCI cache"
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

log "Reload network/firewall"
/etc/init.d/network restart >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true

log "Done."
