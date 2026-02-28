#!/bin/sh
set -eu

log() { echo "[UNINSTALL] $*"; }

log "0) Stop/disable services (ignore errors)"
[ -x /etc/init.d/mihomo ] && /etc/init.d/mihomo stop >/dev/null 2>&1 || true
[ -x /etc/init.d/mihomo ] && /etc/init.d/mihomo disable >/dev/null 2>&1 || true

[ -x /etc/init.d/hev-socks5-tunnel ] && /etc/init.d/hev-socks5-tunnel stop >/dev/null 2>&1 || true
[ -x /etc/init.d/hev-socks5-tunnel ] && /etc/init.d/hev-socks5-tunnel disable >/dev/null 2>&1 || true

[ -x /etc/init.d/magitrickle ] && /etc/init.d/magitrickle stop >/dev/null 2>&1 || true
[ -x /etc/init.d/magitrickle ] && /etc/init.d/magitrickle disable >/dev/null 2>&1 || true


log "1) Remove Mihomo (bin + configs + init)"
rm -f  /usr/bin/mihomo /etc/init.d/mihomo /etc/mihomo.arch 2>/dev/null || true
rm -rf /etc/mihomo 2>/dev/null || true


log "2) Remove LuCI files created by installer"
rm -f  /usr/share/luci/menu.d/luci-app-mihomo.json 2>/dev/null || true
rm -f  /usr/share/rpcd/acl.d/luci-app-mihomo.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/mihomo 2>/dev/null || true

rm -f  /usr/share/luci/menu.d/luci-app-magitrickle.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/magitrickle 2>/dev/null || true
rm -f  /www/luci-static/resources/view/magitrickle/magitrickle.js 2>/dev/null || true


log "3) Remove Hev-socks5-tunnel runtime dir + /etc/config leftovers"
rm -rf /etc/hev-socks5-tunnel 2>/dev/null || true
rm -f  /etc/config/hev-socks5-tunnel /etc/config/hev-socks5-tunnel-opkg 2>/dev/null || true


log "4) Remove MagiTrickle dir + tmp backup"
rm -rf /etc/magitrickle 2>/dev/null || true
rm -f  /tmp/magitrickleconfigbackup.yaml 2>/dev/null || true


log "5) Clean UCI entries added by installer"
uci -q delete network.Mihomo || true
uci -q delete firewall.Mihomo || true
uci -q delete firewall.lantoMihomo || true
uci -q commit network || true
uci -q commit firewall || true

# installer creates/edits: hev-socks5-tunnel.config.* then commits [file:1]
uci -q delete hev-socks5-tunnel.config || true
uci -q commit hev-socks5-tunnel || true


log "6) Remove packages (best-effort)"
opkg remove hev-socks5-tunnel >/dev/null 2>&1 || true
opkg remove magitricklemod >/dev/null 2>&1 || true
opkg remove magitrickle >/dev/null 2>&1 || true


log "7) Clear LuCI cache + restart web/rpc"
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

log "8) Reload network/firewall (because installer added them)"
/etc/init.d/network reload >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true

log "Done."
