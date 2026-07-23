#!/bin/sh
set -eu

CF_API_VERSION="v0a1922"
CF_DIRECT="https://api.cloudflareclient.com"

CF_UA="okhttp/3.12.1"
CF_CLIENT_VER="a-6.3-1922"

WORKER_URL="${WORKER_URL:-https://wgcli.vercel.app}"

OUT="warp-awg.conf"

WARP_ENDPOINT="engage.cloudflareclient.com:4500"

Jc=4
Jmin=40
Jmax=70
H1=1
H2=2
H3=3
H4=4
S1=0
S2=0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT


reg_url() {
    if [ -n "$WORKER_URL" ]; then
        printf '%s/api/%s' "${WORKER_URL%/}" "$1"
    else
        printf '%s/%s/%s' "$CF_DIRECT" "$CF_API_VERSION" "$1"
    fi
}


command -v jq >/dev/null || {
    echo "Нужен jq"
    exit 1
}


if command -v awg >/dev/null 2>&1; then
    GEN=awg
else
    GEN=wg
fi


echo "[+] Генерация ключей..."

PRIVATE_KEY="$("$GEN" genkey)"
PUBLIC_KEY="$(printf '%s\n' "$PRIVATE_KEY" | "$GEN" pubkey)"


echo "[+] Регистрация WARP..."

TOS="$(date -u +%Y-%m-%dT%H:%M:%S.000000000Z)"

curl -fsSL \
    -X POST "$(reg_url reg)" \
    -H "User-Agent: $CF_UA" \
    -H "CF-Client-Version: $CF_CLIENT_VER" \
    -H "Content-Type: application/json" \
    -d "{
        \"key\":\"$PUBLIC_KEY\",
        \"install_id\":\"\",
        \"fcm_token\":\"\",
        \"model\":\"PC\",
        \"locale\":\"en_US\",
        \"tos\":\"$TOS\",
        \"type\":\"PC\"
    }" \
    -o "$TMP/reg.json"


ID="$(jq -r '.id' "$TMP/reg.json")"
TOKEN="$(jq -r '.token' "$TMP/reg.json")"


curl -fsSL \
    "$(reg_url reg/$ID)" \
    -H "Authorization: Bearer $TOKEN" \
    -H "User-Agent: $CF_UA" \
    -H "CF-Client-Version: $CF_CLIENT_VER" \
    -o "$TMP/warp.json"


PEER="$(jq -r '.config.peers[0].public_key' "$TMP/warp.json")"

IP4="$(jq -r '.config.interface.addresses.v4' "$TMP/warp.json")"
IP6="$(jq -r '.config.interface.addresses.v6' "$TMP/warp.json")"


cat > "$OUT" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IP4, $IP6
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
MTU = 1280

S1 = $S1
S2 = $S2
Jc = $Jc
Jmin = $Jmin
Jmax = $Jmax
H1 = $H1
H2 = $H2
H3 = $H3
H4 = $H4

[Peer]
PublicKey = $PEER
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = $WARP_ENDPOINT
PersistentKeepalive = 25
EOF


echo
echo "[+] Готово:"
echo "    $OUT"
