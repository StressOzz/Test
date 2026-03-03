#!/bin/sh
set -e

MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_ETC="/etc/mihomo"
MIHOMO_SERVICE="/etc/init.d/mihomo"

log(){ printf '%s\n' "$*"; }
err(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_openwrt(){
    . /etc/openwrt_release 2>/dev/null || err "Это не OpenWrt"
    MAJOR="${DISTRIB_RELEASE%%.*}"
    [ "$MAJOR" -lt 22 ] && err "Требуется OpenWrt 22.03+"
}

check_space(){
    TMP_FREE=$(df -k /tmp | awk 'NR==2{print $4}')
    ROOT_FREE=$(df -k / | awk 'NR==2{print $4}')
    [ "$TMP_FREE" -lt 16000 ] && err "Мало места в /tmp"
    [ "$ROOT_FREE" -lt 24000 ] && err "Мало места в rootfs"
}

detect_arch(){
    case "$DISTRIB_ARCH" in
        x86_64) echo "amd64" ;;
        i386|i686) echo "386" ;;
        aarch64*) echo "arm64" ;;
        arm_*) echo "armv7" ;;
        mipsel_*) echo "mipsle-softfloat" ;;
        mips_*) echo "mips-softfloat" ;;
        riscv64*) echo "riscv64" ;;
        *) err "Архитектура $DISTRIB_ARCH не поддерживается" ;;
    esac
}

install_base_deps(){
    log "Установка зависимостей..."
    opkg update >/dev/null
    opkg install kmod-nft-tproxy kmod-tun curl libcurl4 ca-bundle ca-certificates \
        hev-socks5-tunnel wireguard-tools jq coreutils-base64 >/dev/null
}

install_mihomo(){

    ARCH="$(detect_arch)"
    TAG=$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MetaCubeX/mihomo/releases/latest | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$TAG" ] && err "Не удалось определить версию Mihomo"

    FILE="mihomo-linux-${ARCH}-${TAG}.gz"
    URL="https://github.com/MetaCubeX/mihomo/releases/download/${TAG}/${FILE}"

    log "Скачивание Mihomo $TAG"
    curl -Lf "$URL" -o /tmp/mihomo.gz
    gunzip -c /tmp/mihomo.gz > "$MIHOMO_BIN"
    chmod +x "$MIHOMO_BIN"
    rm -f /tmp/mihomo.gz

    "$MIHOMO_BIN" -v >/dev/null 2>&1 || err "Mihomo не запускается"

    mkdir -p "$MIHOMO_ETC"/{proxy-providers,rule-providers,rule-files,UI}

cat > "$MIHOMO_SERVICE" <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
BIN="/usr/bin/mihomo"
DIR="/etc/mihomo"
CONF="/etc/mihomo/config.yaml"
start_service(){
    [ -x "$BIN" ] || return 1
    [ -s "$CONF" ] || return 1
    procd_open_instance
    procd_set_param command "$BIN" -d "$DIR" -f "$CONF"
    procd_set_param respawn
    procd_close_instance
}
EOF

    chmod +x "$MIHOMO_SERVICE"
    "$MIHOMO_SERVICE" enable >/dev/null 2>&1
}

configure_hev(){

mkdir -p /etc/hev-socks5-tunnel
cat > /etc/hev-socks5-tunnel/main.yml <<EOF
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

uci -q delete network.Mihomo
uci set network.Mihomo=interface
uci set network.Mihomo.proto='none'
uci set network.Mihomo.device='Mihomo'
uci commit network

uci -q delete firewall.Mihomo
uci -q delete firewall.lan_to_Mihomo

uci set firewall.Mihomo=zone
uci set firewall.Mihomo.name='Mihomo'
uci set firewall.Mihomo.input='REJECT'
uci set firewall.Mihomo.output='REJECT'
uci set firewall.Mihomo.forward='REJECT'
uci set firewall.Mihomo.masq='1'
uci set firewall.Mihomo.mtu_fix='1'
uci add_list firewall.Mihomo.network='Mihomo'

uci set firewall.lan_to_Mihomo=forwarding
uci set firewall.lan_to_Mihomo.src='lan'
uci set firewall.lan_to_Mihomo.dest='Mihomo'
uci commit firewall

/etc/init.d/network reload >/dev/null 2>&1
/etc/init.d/firewall restart >/dev/null 2>&1
/etc/init.d/hev-socks5-tunnel enable >/dev/null 2>&1
/etc/init.d/hev-socks5-tunnel restart >/dev/null 2>&1
}

install_magitrickle(){

ARCH="$DISTRIB_ARCH"
IPK="magitrickle_0.5.2-2_openwrt_${ARCH}.ipk"
URL="https://gitlab.com/api/v4/projects/69165954/packages/generic/magitrickle/0.5.2/$IPK"

curl -Lf "$URL" -o /tmp/$IPK
opkg install /tmp/$IPK >/dev/null
rm -f /tmp/$IPK

/etc/init.d/magitrickle enable >/dev/null 2>&1
/etc/init.d/magitrickle restart >/dev/null 2>&1
}

install_warp(){

log "Генерация WARP (AWG режим)..."

priv="$(wg genkey)"
pub="$(printf "%s" "$priv" | wg pubkey)"

api="https://api.cloudflareclient.com/v0i1909051800"

response=$(curl -s -H "User-Agent: okhttp/3.12.1" -H "Content-Type: application/json" \
-X POST "$api/reg" \
-d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")

id=$(echo "$response" | jq -r '.result.id')
token=$(echo "$response" | jq -r '.result.token')
[ -z "$id" ] || [ "$id" = "null" ] && err "Ошибка регистрации WARP"

response=$(curl -s -H "Authorization: Bearer $token" \
-X PATCH "$api/reg/${id}" -d '{"warp_enabled":true}')

peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6')

[ -z "$peer_pub" ] || [ "$peer_pub" = "null" ] && err "Ошибка получения WARP"

cat > /root/WARP.conf <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${client_ipv4}, ${client_ipv6}
DNS = 1.1.1.1, 2606:4700:4700::1111
MTU = 1280
S1 = 0
S2 = 0
Jc = 4
Jmin = 40
Jmax = 70
H1 = 1
H2 = 2
H3 = 3
H4 = 4
I1 = <b 0x5245474953544552207369703a676f6f676c652e636f6d205349502f322e300d0a...>

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:4500
PersistentKeepalive = 25
EOF

chmod 600 /root/WARP.conf
}


require_openwrt
check_space
install_base_deps
install_mihomo
configure_hev
install_magitrickle
install_warp

log ""
log "ВСЁ ГОТОВО."
log "Mihomo + HEV + MagiTrickle + WARP (AWG) установлены."
