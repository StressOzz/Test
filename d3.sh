#!/bin/sh
set -eu

GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${GREEN}-->${CYAN} $*${NC}"; }

# Определяем пакетный менеджер
PKG_REMOVE=""
if command -v apk >/dev/null 2>&1; then
    PKG_REMOVE="apk del"
else
    PKG_REMOVE="opkg remove"
fi

log "Stop and disable services"
for svc in mihomo hev-socks5-tunnel magitrickle; do
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc stop >/dev/null 2>&1 || true
    [ -x /etc/init.d/$svc ] && /etc/init.d/$svc disable >/dev/null 2>&1 || true
done

log "Remove binary/files"
rm -f /usr/bin/mihomo /etc/init.d/mihomo /etc/mihomo.arch 2>/dev/null || true
rm -rf /etc/mihomo /etc/hev-socks5-tunnel /etc/magitrickle 2>/dev/null || true
rm -f /etc/config/hev-socks5-tunnel /etc/config/hev-socks5-tunnel-opkg /tmp/magitrickleconfigbackup.yaml 2>/dev/null || true

log "Remove LuCI files"
rm -f /usr/share/luci/menu.d/luci-app-mihomo.json 2>/dev/null || true
rm -f /usr/share/rpcd/acl.d/luci-app-mihomo.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/mihomo 2>/dev/null || true
rm -f /usr/share/luci/menu.d/luci-app-magitrickle.json 2>/dev/null || true
rm -rf /www/luci-static/resources/view/magitrickle 2>/dev/null || true

log "Clean UCI configs"
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

log "Clean policy routing"
# Удаляем стандартные fwmark и кастомные таблицы
ip rule del fwmark 0x1 lookup 100 2>/dev/null || true
ip rule del fwmark 0x1 lookup 200 2>/dev/null || true
ip route flush table 100 2>/dev/null || true
ip route flush table 200 2>/dev/null || true
ip route flush cache 2>/dev/null || true

log "Clean nftables (Mihomo/Magi leftovers)"
# Все таблицы, цепочки, цепочки с MT_/Mihomo в имени
for tbl in $(nft list tables 2>/dev/null | awk '{print $2}'); do
    for chain in $(nft list chains $tbl 2>/dev/null | awk '{print $2}'); do
        case "$chain" in
            *Mihomo*|*MT_*|*srcnat_Mihomo*|*accept_to_Mihomo*|*reject_to_Mihomo*|*postnat*|*postrouting_hook*)
                log "Deleting chain $tbl/$chain"
                nft delete chain $tbl $chain 2>/dev/null || true
                ;;
        esac
    done
    # Удаляем таблицу полностью, если в ней остались только Magi цепочки
    if nft list chains $tbl 2>/dev/null | grep -qE 'Mihomo|MT_'; then
        log "Flushing and deleting table $tbl"
        nft flush table $tbl 2>/dev/null || true
        nft delete table $tbl 2>/dev/null || true
    fi
done

log "Clear LuCI cache"
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1 || true
/etc/init.d/uhttpd restart >/dev/null 2>&1 || true

log "Reload firewall and network"
/etc/init.d/firewall restart >/dev/null 2>&1 || true
/etc/init.d/network restart >/dev/null 2>&1 || true

log "Done. Internet should work immediately."
