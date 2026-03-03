#!/bin/sh
set -eu

log() { echo "[UNINSTALL] $*"; }

log "0) Stop/disable services"
for svc in mihomo hev-socks5-tunnel magitrickle; do
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc stop >/dev/null 2>&1 || true
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc disable >/dev/null 2>&1 || true
done

log "1) Remove Mihomo"
rm -f  /usr/bin/mihomo /etc/init.d/mihomo /etc/mihomo.arch 2>/dev/null || true
rm -rf /etc/mihomo 2>/dev/null || true

log "2) Remove LuCI files"
rm -f  /usr/share/luci/menu.d/luci-app-mihomo.json 2>/dev/null || true
rm -f  /usr/share/rpcd/acl.d/luci-app-mihomo.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/mihomo 2>/dev/null || true

rm -f  /usr/share/luci/menu.d/luci-app-magitrickle.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/magitrickle 2>/dev/null || true

log "3) Remove Hev & Magi configs"
rm -rf /etc/hev-socks5-tunnel 2>/dev/null || true
rm -f  /etc/config/hev-socks5-tunnel /etc/config/hev-socks5-tunnel-opkg 2>/dev/null || true
rm -rf /etc/magitrickle 2>/dev/null || true
rm -f  /tmp/magitrickleconfigbackup.yaml 2>/dev/null || true

log "4) Clean UCI"
uci -q delete network.Mihomo || true
uci -q delete firewall.Mihomo || true
uci -q delete firewall.lan_to_Mihomo || true
uci -q delete firewall.lantoMihomo || true
uci -q delete hev-socks5-tunnel || true
uci -q delete hev-socks5-tunnel.config || true

uci -q commit network || true
uci -q commit firewall || true
uci -q commit hev-socks5-tunnel || true

log "5) Remove packages"
opkg remove hev-socks5-tunnel >/dev/null 2>&1 || true
opkg remove magitrickle_mod >/dev/null 2>&1 || true
opkg remove magitrickle >/dev/null 2>&1 || true
opkg remove kmod-nft-tproxy >/dev/null 2>&1 || true

log "6) Clear LuCI cache"
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

log "7) Reload network/firewall"
/etc/init.d/network restart >/dev/null 2>&1 || true
/etc/init.d/firewall restart >/dev/null 2>&1 || true

log "Done."
