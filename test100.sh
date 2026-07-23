#!/bin/sh

WORKER_URL="${WORKER_URL:-https://wgcli.vercel.app}"

CF_UA="okhttp/3.12.1"
CF_CLIENT_VER="a-6.3-1922"

OUT="warp-awg.conf"

ENDPOINT="engage.cloudflareclient.com:4500"

Jc=4
Jmin=40
Jmax=70
H1=1
H2=2
H3=3
H4=4
S1=0
S2=0

TMP="$(mktemp -d /tmp/warp.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT


err() {
    echo "Ошибка: $*" >&2
    exit 1
}


command -v curl >/dev/null 2>&1 || err "Нужен curl"
command -v jq >/dev/null 2>&1 || err "Нужен jq"


if command -v awg >/dev/null 2>&1; then
    GEN="awg"
elif command -v wg >/dev/null 2>&1; then
    GEN="wg"
else
    err "Не найден awg/wg"
fi


reg_url() {
    printf '%s/api/%s' "${WORKER_URL%/}" "$1"
}


echo "[+] Генерация ключей..."

PRIVATE_KEY="$("$GEN" genkey)"
PUBLIC_KEY="$(printf '%s\n' "$PRIVATE_KEY" | "$GEN" pubkey)"


echo "[+] Регистрация WARP через прокси: $WORKER_URL"


TOS="$(date -u +%Y-%m-%dT%H:%M:%S.000000000Z)"


curl -fsSL \
    --max-time 30 \
    -X POST "$(reg_url reg)" \
    -H "User-Agent: $CF_UA" \
    -H "CF-Client-Version: $CF_CLIENT_VER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{
        \"key\":\"$PUBLIC_KEY\",
        \"install_id\":\"\",
        \"fcm_token\":\"\",
        \"model\":\"PC\",
        \"locale\":\"en_US\",
        \"tos\":\"$TOS\",
        \"type\":\"PC\"
    }" \
    -o "$TMP/reg.json" \
    || err "Не удалось зарегистрировать WARP"


ID="$(jq -r '.id' "$TMP/reg.json")"
TOKEN="$(jq -r '.token' "$TMP/reg.json")"


[ "$ID" != "null" ] || err "Нет id"
[ "$TOKEN" != "null" ] || err "Нет token"


if jq -e '.config.peers[0].public_key' "$TMP/reg.json" >/dev/null 2>&1; then
    cp "$TMP/reg.json" "$TMP/warp.json"
else

    curl -fsSL \
        --max-time 30 \
        "$(reg_url reg/$ID)" \
        -H "User-Agent: $CF_UA" \
        -H "CF-Client-Version: $CF_CLIENT_VER" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/json" \
        -o "$TMP/warp.json" \
        || err "Не удалось получить конфигурацию WARP"

fi


PEER="$(jq -r '.config.peers[0].public_key' "$TMP/warp.json")"

IP4="$(jq -r '.config.interface.addresses.v4' "$TMP/warp.json")"
IP6="$(jq -r '.config.interface.addresses.v6 // empty' "$TMP/warp.json")"


[ "$PEER" != "null" ] || err "Нет PublicKey"
[ "$IP4" != "null" ] || err "Нет IPv4"


cat > "$OUT" <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $IP4${IP6:+, $IP6}
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
Endpoint = $ENDPOINT
PersistentKeepalive = 25
EOF


echo
echo "Готово!"
echo "Конфиг создан: $OUT"
echo
cat "$OUT"
