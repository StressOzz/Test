#!/bin/sh

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"

[ -f "$IN" ] || { echo "ERR: no $IN"; exit 1; }

trim() { echo "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

yaml_escape() {
  # escape \ and " for YAML double-quoted scalars
  # shellcheck disable=SC2001
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

get_kv() {
  # $1 section (Interface|Peer), $2 key
  awk -v sec="[$1]" -v key="$2" '
    BEGIN{insec=0}
    $0 ~ /^\[/{insec=($0==sec)}
    insec && $0 ~ "^[ \t]*"key"[ \t]*=" {
      sub(/^[^=]*=/,""); gsub(/\r/,""); gsub(/^[ \t]+|[ \t]+$/,"");
      print; exit
    }
  ' "$IN"
}

# ---- read values ----
PRIVATEKEY="$(get_kv Interface PrivateKey)"
ADDRESS="$(get_kv Interface Address)"
MTU="$(get_kv Interface MTU)"

S1="$(get_kv Interface S1)"
S2="$(get_kv Interface S2)"
JC="$(get_kv Interface Jc)"
JMIN="$(get_kv Interface Jmin)"
JMAX="$(get_kv Interface Jmax)"
H1="$(get_kv Interface H1)"
H2="$(get_kv Interface H2)"
H3="$(get_kv Interface H3)"
H4="$(get_kv Interface H4)"
I1="$(get_kv Interface I1)"

PUBLICKEY="$(get_kv Peer PublicKey)"
ALLOWEDIPS="$(get_kv Peer AllowedIPs)"
ENDPOINT="$(get_kv Peer Endpoint)"
KEEPALIVE="$(get_kv Peer PersistentKeepalive)"

# ---- normalize ----
IPV4="$(trim "$(echo "$ADDRESS" | cut -d',' -f1)")"
IPV6="$(trim "$(echo "$ADDRESS" | cut -d',' -f2 2>/dev/null)")"

SERVER="$(echo "$ENDPOINT" | cut -d':' -f1)"
PORT="$(echo "$ENDPOINT" | cut -d':' -f2)"

AL1="$(trim "$(echo "$ALLOWEDIPS" | cut -d',' -f1)")"
AL2="$(trim "$(echo "$ALLOWEDIPS" | cut -d',' -f2 2>/dev/null)")"

# Имя как в вашем 2-м примере: WARP + последние 6 символов от PublicKey без спецсимволов
# (Можно заменить на фиксированное NAME="WARP")
SUF="$(echo "$PUBLICKEY" | tr -cd 'a-zA-Z0-9' | tail -c 7 2>/dev/null | head -c 6)"
[ -n "$SUF" ] && NAME="WARP$SUF" || NAME="WARP"

# defaults for amnezia fields if empty
[ -n "$S1" ] || S1=0
[ -n "$S2" ] || S2=0
[ -n "$JC" ] || JC=0
[ -n "$JMIN" ] || JMIN=0
[ -n "$JMAX" ] || JMAX=0
[ -n "$H1" ] || H1=0
[ -n "$H2" ] || H2=0
[ -n "$H3" ] || H3=0
[ -n "$H4" ] || H4=0

# ---- write from scratch ----
mkdir -p "$(dirname "$OUT")" || exit 1

{
cat <<EOF
mixed-port: 7890
allow-lan: false
tcp-concurrent: true
mode: rule
log-level: info
ipv6: false
external-controller: 0.0.0.0:9090
external-ui: ui
external-ui-url: https://github.com/MetaCubeX/metacubexd/releases/latest/download/compressed-dist.tgz
secret:
unified-delay: true
profile:
  store-selected: true
  store-fake-ip: true

proxy-groups:
  - name: GLOBAL
    type: select
    proxies:
      - $NAME
      - REJECT

rules:
  - "MATCH,GLOBAL"

proxies:
  - name: $NAME
    type: wireguard
    server: $SERVER
    port: $PORT
    private-key: "$(yaml_escape "$PRIVATEKEY")"
    udp: true
    ip: $IPV4
EOF

# ipv6 optional
if [ -n "$IPV6" ]; then
  echo "    ipv6: $IPV6"
fi

cat <<EOF
    public-key: "$(yaml_escape "$PUBLICKEY")"
    allowed-ips:
      - "$AL1"
EOF

if [ -n "$AL2" ]; then
  echo "      - \"$AL2\""
fi

[ -n "$MTU" ] && echo "    mtu: $MTU"
[ -n "$KEEPALIVE" ] && echo "    persistent-keepalive: $KEEPALIVE"

cat <<EOF
    amnezia-wg-option:
      s1: $S1
      s2: $S2
      jc: $JC
      jmin: $JMIN
      jmax: $JMAX
      h1: $H1
      h2: $H2
      h3: $H3
      h4: $H4
EOF

if [ -n "$I1" ]; then
  echo "      i1: \"$(yaml_escape "$I1")\""
fi
} > "$OUT"

chmod 0644 "$OUT"
echo "OK: $OUT written"
