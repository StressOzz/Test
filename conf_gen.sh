#!/bin/sh

set -e

echo "Установка зависимостей…"

opkg update
opkg install wireguard-tools jq wget ca-bundle

API="https://api.cloudflareclient.com/v0i1909051800"

# Генерация ключей
PRIV_KEY="${1:-$(wg genkey)}"
PUB_KEY="${2:-$(echo "$PRIV_KEY" | wg pubkey)}"

ins() {
	curl -s \
		-H 'user-agent:' \
		-H 'content-type: application/json' \
		-X "$1" \
		"$API/$2" \
		"${@:3}"
}

sec() {
	ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"
}

echo "Регистрация WARP…"

RESPONSE="$(ins POST reg -d "{
	\"install_id\":\"\",
	\"tos\":\"$(date -u +%FT%T.000Z)\",
	\"key\":\"$PUB_KEY\",
	\"fcm_token\":\"\",
	\"type\":\"ios\",
	\"locale\":\"en_US\"
}")"

ID="$(echo "$RESPONSE" | jq -r '.result.id')"
TOKEN="$(echo "$RESPONSE" | jq -r '.result.token')"

RESPONSE="$(sec PATCH "reg/$ID" "$TOKEN" -d '{"warp_enabled":true}')"

PEER_PUB="$(echo "$RESPONSE" | jq -r '.result.config.peers[0].public_key')"
IPV4="$(echo "$RESPONSE" | jq -r '.result.config.interface.addresses.v4')"
IPV6="$(echo "$RESPONSE" | jq -r '.result.config.interface.addresses.v6')"

CONF_PATH="/etc/wireguard/warp.conf"
mkdir -p /etc/wireguard

cat > "$CONF_PATH" <<EOF
[Interface]
PrivateKey = $PRIV_KEY
Address = $IPV4, $IPV6
DNS = 1.1.1.1,1.0.0.1
MTU = 1280

[Peer]
PublicKey = $PEER_PUB
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500
PersistentKeepalive = 25
EOF

echo
echo "Конфиг сохранён:"
echo "$CONF_PATH"
echo

echo "Содержимое:"
echo "---------------------------"
cat "$CONF_PATH"
echo "---------------------------"

echo
echo "Теперь можно подключить:"
echo "wg-quick up warp"
