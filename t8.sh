#!/bin/sh
set -eu

MIHOMO_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_INIT="/etc/init.d/mihomo"

log() { echo "[UNINSTALL] $*"; }

log "1) Stop/disable services"
[ -x "$MIHOMO_INIT" ] && "$MIHOMO_INIT" stop >/dev/null 2>&1 || true
[ -x "$MIHOMO_INIT" ] && "$MIHOMO_INIT" disable >/dev/null 2>&1 || true

[ -x /etc/init.d/hev-socks5-tunnel ] && /etc/init.d/hev-socks5-tunnel stop >/dev/null 2>&1 || true
[ -x /etc/init.d/hev-socks5-tunnel ] && /etc/init.d/hev-socks5-tunnel disable >/dev/null 2>&1 || true

[ -x /etc/init.d/magitrickle ] && /etc/init.d/magitrickle stop >/dev/null 2>&1 || true
[ -x /etc/init.d/magitrickle ] && /etc/init.d/magitrickle disable >/dev/null 2>&1 || true

log "2) Remove Mihomo files"
rm -f "$MIHOMO_BIN" 2>/dev/null || true
rm -rf "$MIHOMO_DIR" 2>/dev/null || true
rm -f /etc/mihomo.arch 2>/dev/null || true
rm -f "$MIHOMO_INIT" 2>/dev/null || true

log "3) Remove LuCI files created by script"
rm -f /usr/share/luci/menu.d/luci-app-mihomo.json 2>/dev/null || true
rm -f /usr/share/rpcd/acl.d/luci-app-mihomo.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/mihomo 2>/dev/null || true

rm -f /usr/share/luci/menu.d/luci-app-magitrickle.json 2>/dev/null || true
rm -f /www/luci-static/resources/view/magitrickle/magitrickle.js 2>/dev/null || true

log "4) Remove hev-socks5-tunnel runtime config"
rm -f /etc/hev-socks5-tunnel/main.yml 2>/dev/null || true
rmdir /etc/hev-socks5-tunnel 2>/dev/null || true

log "5) Remove MagiTrickle configs"
rm -f /etc/magitrickle/state/config.yaml 2>/dev/null || true
rm -f /etc/magitrickle/state/config.yaml.backup 2>/dev/null || true
rm -f /tmp/magitrickleconfigbackup.yaml 2>/dev/null || true
rmdir /etc/magitrickle/state 2>/dev/null || true
rmdir /etc/magitrickle 2>/dev/null || true

log "6) Clean UCI objects added by script (network/firewall/hev-socks5-tunnel)"
uci -q delete network.Mihomo || true
uci -q delete firewall.Mihomo || true
uci -q delete firewall.lantoMihomo || true
uci -q commit network || true
uci -q commit firewall || true

# Полностью удалить конфиг-пакет hev-socks5-tunnel из UCI
# (в s3.sh он создаётся/правится через: uci set hev-socks5-tunnel.config.* ; commit) [file:1]
uci -q delete hev-socks5-tunnel.config || true
uci -q commit hev-socks5-tunnel || true

log "7) Remove /etc/config leftovers you listed"
rm -f /etc/config/hev-socks5-tunnel 2>/dev/null || true
rm -f /etc/config/hev-socks5-tunnel-opkg 2>/dev/null || true

log "8) Remove packages (best-effort)"
opkg remove hev-socks5-tunnel >/dev/null 2>&1 || true
opkg remove magitricklemod >/dev/null 2>&1 || true
opkg remove magitrickle >/dev/null 2>&1 || true

log "9) Clear LuCI caches and restart key daemons"
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true
/etc/init.d/network reload >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true

log "Done."
