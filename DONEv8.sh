#!/bin/sh
# ============================================================
#  OPENWRT DNS/NTP HARDENING — Zapret Manager style
#  v8.0
# ============================================================

# ---------- colors / ui helpers (busybox ash safe) ----------
C_RESET="\033[0m"
C_RED="\033[1;31m"
C_GREEN="\033[1;32m"
C_YELLOW="\033[1;33m"
C_BLUE="\033[1;34m"
C_CYAN="\033[1;36m"
C_BOLD="\033[1m"

log()  { printf "${C_CYAN}[*]${C_RESET} %s\n" "$1"; }
ok()   { printf "${C_GREEN}[✓]${C_RESET} %s\n" "$1"; }
warn() { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$1"; }
err()  { printf "${C_RED}[✗]${C_RESET} %s\n" "$1"; }
step() { printf "\n${C_BOLD}${C_BLUE}══ %s ══${C_RESET}\n" "$1"; }

banner() {
cat << 'BANNER'

  ███████╗ █████╗ ██████╗ ██████╗ ███████╗████████╗
  ╚══███╔╝██╔══██╗██╔══██╗██╔══██╗██╔════╝╚══██╔══╝
    ███╔╝ ███████║██████╔╝██████╔╝█████╗     ██║
   ███╔╝  ██╔══██║██╔═══╝ ██╔══██╗██╔══╝     ██║
  ███████╗██║  ██║██║     ██║  ██║███████╗   ██║
  ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝  ╚═╝╚══════╝   ╚═╝
        DNS / NTP HARDENING SETUP  •  v8.0
BANNER
}

banner
STATUS_LOG="/tmp/zapret_setup_status.log"
: > "$STATUS_LOG"
add_status() { echo "$1" >> "$STATUS_LOG"; }

# ============================================================
step "0/13  Environment check"
# ============================================================
if command -v apk >/dev/null 2>&1; then
    PKG="apk"; CA_PKG="ca-certificates"
elif command -v opkg >/dev/null 2>&1; then
    PKG="opkg"; CA_PKG="ca-bundle"
else
    err "No supported package manager (apk/opkg) found"; exit 1
fi
MISSING=0
for util in uci sed grep awk nslookup; do
    command -v "$util" >/dev/null 2>&1 || { err "Missing required utility: $util"; MISSING=1; }
done
[ "$MISSING" = "1" ] && exit 1
mkdir -p /etc/dnsmasq.d /etc/sysctl.d /etc/hotplug.d/ntp
ok "Environment OK (package manager: $PKG)"

# ============================================================
step "0b/13  Config backup"
# ============================================================
BACKUP_DIR="/etc/zapret-backups"
mkdir -p "$BACKUP_DIR"
BACKUP_FILE="$BACKUP_DIR/uci-backup-$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$BACKUP_FILE" -C /etc config 2>/dev/null \
    && ok "UCI config backed up to $BACKUP_FILE" \
    || warn "Could not create backup (continuing anyway)"

# ============================================================
step "1/13  MTU fix"
# ============================================================
uci -q set firewall.@defaults[0].mtu_fix='1'
WAN_SECTION=$(uci show firewall 2>/dev/null | grep -m1 "\.name='wan'" | cut -d. -f1,2)
if [ -n "$WAN_SECTION" ]; then
    uci -q set "${WAN_SECTION}.mtu_fix=1"
    ok "MTU fix applied to $WAN_SECTION"
else
    warn "No firewall zone named 'wan' found — skipped zone-level mtu_fix"
fi

# ============================================================
step "2/13  NTP redirect (DHCP option 42 + DNAT)"
# ============================================================
LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null)
if [ -z "$LAN_IP" ] || [ "$LAN_IP" = "0.0.0.0" ]; then
    LAN_IP="192.168.1.1"
    warn "LAN IP not found, defaulting to $LAN_IP"
fi

# rebuild dhcp_option list, stripping any stale "42,*" entries (idempotent)
OLD_OPTS=$(uci -q get dhcp.lan.dhcp_option 2>/dev/null)
uci -q delete dhcp.lan.dhcp_option 2>/dev/null
if [ -n "$OLD_OPTS" ]; then
    for opt in $OLD_OPTS; do
        case "$opt" in
            42,*) : ;;   # drop stale option-42 entries
            *) uci add_list dhcp.lan.dhcp_option="$opt" ;;
        esac
    done
fi
uci add_list dhcp.lan.dhcp_option="42,$LAN_IP"
ok "DHCP option 42 (NTP) set to $LAN_IP"

# only remove redirect rules WE created (matched by name), never touch unrelated rules
for sec in $(uci show firewall 2>/dev/null | grep -E "\.name='(Redirect-NTP|Intercept-NTP)'" | cut -d. -f2 | cut -d= -f1); do
    uci -q delete firewall."$sec"
done
uci -q delete firewall.redirect_ntp 2>/dev/null
uci set firewall.redirect_ntp=redirect
uci set firewall.redirect_ntp.name='Redirect-NTP'
uci set firewall.redirect_ntp.src='lan'
uci set firewall.redirect_ntp.proto='udp'
uci set firewall.redirect_ntp.src_dport='123'
uci set firewall.redirect_ntp.dest_port='123'
uci set firewall.redirect_ntp.target='DNAT'
uci commit firewall
if /etc/init.d/firewall reload 2>/dev/null || /etc/init.d/firewall restart 2>/dev/null; then
    ok "Firewall NTP redirect active"
else
    warn "Firewall reload/restart failed — check manually"
fi

# ============================================================
step "3/13  Go runtime tuning"
# ============================================================
f_tg="/etc/init.d/tg-ws-proxy-go"; f_ts="/etc/init.d/tailscale"
if [ -f "$f_tg" ] && grep -q "procd_open_instance" "$f_tg"; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_tg"
    sed -i '/procd_open_instance/a\    procd_set_param env GOMAXPROCS=1 GOMEMLIMIT=50MiB' "$f_tg"
    ok "tg-ws-proxy-go tuned"
else
    warn "tg-ws-proxy-go not found — skipped"
fi
if [ -f "$f_ts" ] && grep -q "procd_open_instance" "$f_ts"; then
    sed -i '/GOMAXPROCS/d; /GOMEMLIMIT/d; /GOGC/d' "$f_ts"
    sed -i '/procd_open_instance/a\    procd_set_param env GOMEMLIMIT=85MiB' "$f_ts"
    ok "tailscale tuned"
else
    warn "tailscale init script not found — skipped"
fi

# ============================================================
step "4/13  Cron cleanup"
# ============================================================
if [ -f /etc/crontabs/root ]; then
    cp /etc/crontabs/root /etc/crontabs/root.bak
    sed -i '/dnsmasq/d; /https-dns-proxy/d; /tailscale/d' /etc/crontabs/root
    ok "Stale cron entries removed (backup: root.bak)"
else
    warn "No root crontab found — skipped"
fi

# ============================================================
step "5/13  NTP servers"
# ============================================================
uci set system.ntp=timeserver
uci set system.ntp.enabled='1'
uci -q delete system.ntp.server
for srv in 162.159.200.1 216.239.35.0 89.109.251.21 92.255.126.1 194.190.168.1 129.250.35.250; do
    uci add_list system.ntp.server="$srv"
done
uci commit system
ok "NTP server list updated"

# ============================================================
step "6/13  https-dns-proxy package"
# ============================================================
if ! command -v https-dns-proxy >/dev/null 2>&1; then
    log "Installing https-dns-proxy..."
    case "$PKG" in
        apk)  apk update >/dev/null 2>&1; apk add https-dns-proxy $CA_PKG >/dev/null 2>&1 ;;
        opkg) opkg update >/dev/null 2>&1; opkg install https-dns-proxy $CA_PKG >/dev/null 2>&1 ;;
    esac
    if command -v https-dns-proxy >/dev/null 2>&1; then
        ok "https-dns-proxy installed"
    else
        err "Failed to install https-dns-proxy — aborting"
        exit 1
    fi
else
    ok "https-dns-proxy already installed"
fi

# ============================================================
step "7/13  DoH resolver instances"
# ============================================================
while uci -q delete https-dns-proxy.@https-dns-proxy[0]; do :; done
uci -q delete https-dns-proxy.config 2>/dev/null
uci set https-dns-proxy.config='main'
uci set https-dns-proxy.config.update_dnsmasq='0'

i=0
for url in \
    'https://cloudflare-dns.com/dns-query' \
    'https://freedns.controld.com/uncensored' \
    'https://unicast.censurfridns.dk/dns-query' \
    'https://dns.google/dns-query' \
    'https://dns.digitale-gesellschaft.ch/dns-query'; do
    port=$((5053 + i)); i=$((i + 1))
    uci add https-dns-proxy https-dns-proxy >/dev/null
    uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url="$url"
    uci set https-dns-proxy.@https-dns-proxy[-1].listen_port="$port"
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='1.1.1.1'
    uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='8.8.8.8'
done
uci add https-dns-proxy https-dns-proxy >/dev/null
uci set https-dns-proxy.@https-dns-proxy[-1].resolver_url='https://common.dot.dns.yandex.net/dns-query'
uci set https-dns-proxy.@https-dns-proxy[-1].listen_port='5058'
uci add_list https-dns-proxy.@https-dns-proxy[-1].bootstrap_dns='77.88.8.8'
uci commit https-dns-proxy
ok "6 DoH resolver instances configured (ports 5053-5058)"

# ============================================================
step "8/13  Telemetry blocklist"
# ============================================================
cat << 'BLOCKLIST' > /etc/dnsmasq.d/telemetry.conf
address=/vortex.data.microsoft.com/
address=/vortex-win.data.microsoft.com/
address=/settings-win.data.microsoft.com/
address=/watson.telemetry.microsoft.com/
address=/telemetry.microsoft.com/
address=/crashlytics.com/
address=/app-measurement.com/
BLOCKLIST
ok "Telemetry blocklist written"

# ============================================================
step "9/13  dnsmasq TLD split"
# ============================================================
uci -q delete dhcp.balancer 2>/dev/null
while uci -q delete dhcp.@dnsmasq[0].server; do :; done
uci -q delete dhcp.@dnsmasq[0].address 2>/dev/null
uci -q delete dhcp.@dnsmasq[0].confdir 2>/dev/null
for param in min_ttl min_cache_ttl max_cache_ttl neg_ttl dnsforwardmax dns_forward_max edns_pktsz ednspacket_max; do
    uci -q delete dhcp.@dnsmasq[0].$param 2>/dev/null
done
uci add_list dhcp.@dnsmasq[0].confdir='/etc/dnsmasq.d'
uci set dhcp.@dnsmasq[0].allservers='1'
uci set dhcp.@dnsmasq[0].strictorder='0'
uci set dhcp.@dnsmasq[0].noresolv='1'
uci set dhcp.@dnsmasq[0].filter_aaaa='1'
uci set dhcp.@dnsmasq[0].cachesize='10000'
uci set dhcp.@dnsmasq[0].dnsforwardmax='1000'
uci set dhcp.@dnsmasq[0].max_cache_ttl='300'
for p in 5053 5054 5055 5056 5057; do
    uci add_list dhcp.@dnsmasq[0].server="127.0.0.1#$p"
done
uci add_list dhcp.@dnsmasq[0].server='/ru/127.0.0.1#5058'
uci add_list dhcp.@dnsmasq[0].server='/su/127.0.0.1#5058'
uci add_list dhcp.@dnsmasq[0].server='/xn--p1ai/127.0.0.1#5058'
uci set dhcp.@dnsmasq[0].quietdhcp='1'
uci set dhcp.@dnsmasq[0].boguspriv='1'
uci set dhcp.@dnsmasq[0].domainneeded='1'
uci add_list dhcp.@dnsmasq[0].address='/use-application-dns.net/'
uci add_list dhcp.@dnsmasq[0].server='/connectivitycheck.gstatic.com/8.8.8.8'
uci add_list dhcp.@dnsmasq[0].server='/connectivitycheck.samsungcloud.com/8.8.8.8'
uci commit dhcp
ok "dnsmasq configured: .ru/.su/.рф → Yandex DoH, rest → global DoH pool"

# ============================================================
step "10/13  Anti-block filters"
# ============================================================
cat << 'ANTIBLOCK' > /etc/dnsmasq.d/anti-block.conf
no-negcache
bogus-nxdomain=45.155.204.190
bogus-nxdomain=95.182.120.241
bogus-nxdomain=37.230.192.51
bogus-nxdomain=77.37.254.90
bogus-nxdomain=87.241.223.133
bogus-nxdomain=95.167.13.50
bogus-nxdomain=62.33.207.195
bogus-nxdomain=0.0.0.0
bogus-nxdomain=127.0.0.1
ANTIBLOCK
ok "Anti-block (bogus-nxdomain) filters written"

# ============================================================
step "11/13  Sysctl tuning"
# ============================================================
modprobe nf_conntrack 2>/dev/null
modprobe xt_conntrack 2>/dev/null
SYSFILE="/etc/sysctl.d/99-custom.conf"
touch "$SYSFILE"
for param in \
    "net.netfilter.nf_conntrack_max=65536" \
    "net.ipv4.tcp_fastopen=3" \
    "net.ipv4.tcp_fin_timeout=15" \
    "net.core.somaxconn=1024" \
    "net.ipv4.tcp_keepalive_time=300" \
    "net.ipv4.tcp_keepalive_intvl=15" \
    "net.ipv4.tcp_keepalive_probes=5" \
    "net.core.rmem_max=2097152" \
    "net.core.wmem_max=2097152"; do
    key=$(echo "$param" | cut -d= -f1)
    sed -i "\|^$key|d" "$SYSFILE" 2>/dev/null
    sed -i "\|^$key|d" /etc/sysctl.conf 2>/dev/null
    echo "$param" >> "$SYSFILE"
    sysctl -w "$param" >/dev/null 2>&1
done
ok "Sysctl parameters applied ($SYSFILE)"

# ============================================================
step "12/13  Hotplug NTP-step handler"
# ============================================================
rm -rf /tmp/tailscale_ntp_lock
rm -f /etc/hotplug.d/ntp/99-tailscale
cat << 'HOTPLUG' > /etc/hotplug.d/ntp/99-tailscale
#!/bin/sh
[ "$ACTION" = "step" ] || [ "$ACTION" = "stratum" ] || exit 0
UPTIME=$(cut -d. -f1 /proc/uptime)
if [ "$UPTIME" -lt 600 ]; then
    mkdir /tmp/tailscale_ntp_lock 2>/dev/null && /etc/init.d/tailscale restart >/dev/null 2>&1
fi
HOTPLUG
chmod +x /etc/hotplug.d/ntp/99-tailscale
ok "Hotplug handler installed"

# ============================================================
step "13/13  Enable & restart services"
# ============================================================
/etc/init.d/sysntpd enable 2>/dev/null
/etc/init.d/https-dns-proxy enable 2>/dev/null
/etc/init.d/dnsmasq enable 2>/dev/null
/etc/init.d/cron enable 2>/dev/null
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go enable 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale enable 2>/dev/null

/etc/init.d/sysntpd restart 2>/dev/null
/etc/init.d/https-dns-proxy restart
sleep 1
/etc/init.d/dnsmasq stop
sleep 2
/etc/init.d/dnsmasq start
/etc/init.d/cron restart 2>/dev/null
sleep 5
[ -f "$f_tg" ] && /etc/init.d/tg-ws-proxy-go restart 2>/dev/null
[ -f "$f_ts" ] && /etc/init.d/tailscale restart 2>/dev/null
ok "Services restarted"

# ============================================================
step "VERIFICATION"
# ============================================================
for dom in ya.ru chatgpt.com claude.ai youtube.com gemini.google.com; do
    ip=$(nslookup "$dom" 127.0.0.1 2>/dev/null | grep -v "127.0.0.1" | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | tail -n1)
    [ -z "$ip" ] && ip="NO_ANSWER"
    case "$ip" in
        45.155.204.190|95.182.120.241|37.230.192.51|77.37.254.90|87.241.223.133|95.167.13.50|62.33.207.195|0.0.0.0|127.0.0.1)
            warn "$dom → $ip  (STUB in response — check /etc/hosts / Zapret Manager)"
            add_status "FAIL $dom stub:$ip" ;;
        NO_ANSWER)
            err "$dom → no answer"
            add_status "FAIL $dom no_answer" ;;
        *)
            ok "$dom → $ip"
            add_status "OK $dom $ip" ;;
    esac
done

printf "\n${C_BOLD}${C_BLUE}══ SUMMARY ══${C_RESET}\n"
FAILS=$(grep -c '^FAIL' "$STATUS_LOG")
TOTAL=$(wc -l < "$STATUS_LOG")
if [ "$FAILS" = "0" ]; then
    ok "All $TOTAL domains resolved cleanly via DoH"
else
    warn "$FAILS/$TOTAL domains still show stub/blocked answers"
fi
printf "${C_CYAN}Backup:${C_RESET} %s\n" "$BACKUP_FILE"
echo ""
echo "=== DONE v8.0 ==="
echo "NOTE: /etc/hosts was NOT touched — use Zapret Manager to clean stub entries there."
