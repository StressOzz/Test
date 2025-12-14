#!/bin/sh

### НАСТРОЙКИ
API="https://api.cloudflareclient.com/v0i1909051800"
CONF_DIR="/etc/wireguard"
CONF_FILE="$CONF_DIR/warp.conf"
RETRIES=3
TIMEOUT=20

echo "== Cloudflare WARP для OpenWrt =="
echo

### ПРОВЕРКА ЗАВИСИМОСТЕЙ
echo "Проверка зависимостей…"
opkg update >/dev/null 2>&1
opkg install wireguard-tools jq ca-bundle >/dev/null 2>&1

command -v wg >/dev/null || { echo "wg не найден"; exit 1; }
command -v jq >/dev/null || { echo "jq не найден"; exit 1; }
command -v curl >/dev/null || { echo "curl не найден"; exit 1; }

### КЛЮЧИ
PRIV_KEY="${1:-$(wg genkey)}"
PUB_KEY="${2:-$(echo "$PRIV_KEY" | wg pubkey)}"

### CURL ФУНКЦИИ
ins() {
	curl --fail -s \
		--connect-timeout 10 \
		--max-time "$TIMEOUT" \
		-H 'user-agent:' \
		-H 'content-type: application/json' \
		-X "$1" \
		"$API/$2" \
		"${@:3}"
}

sec() {
	ins "$1" "$2" -H "authorization: Bearer $3" "${@:4}"
}

### РЕГИСТРАЦИЯ С РЕТРАЯМИ
echo "Регистрация WARP…"

i=1
while [ $i -le $RETRIES ]; do
	RESPONSE="$(ins POST reg -d "{
		\"install_id\":\"\",
		\"tos\":\"$(date -u +%FT%T.000Z)\",
		\"key\":\"$PUB_KEY\",
		\"fcm_token\":\"\",
		\"type\":\"ios\",
		\"locale\":\"en_US\"
	}")" && break

	echo "Попытка $i не удалась, повтор…"
	i=$((i+1))
	sleep 2
done

[ -z "$RESPONSE" ] && {
	echo "Ошибка: Cloudflare не ответил"
	exit 1
}

echo "$RESPONSE" | jq . >/dev/null 2>&1 || {
	echo "Ошибка: ответ не JSON"
	echo "$RESPONSE"
	exit 1
}

ID="$(echo "$RESPONSE" | jq -r '.result.id')"
TOKEN="$(echo "$RESPONSE" | jq -r '.result.token')"

[ "$ID" = "null" ] || [ "$TOKEN" = "null" ] && {
	echo "Ошибка: не получен ID или TOKEN"
	echo "$RESPONSE"
	exit 1
}

### АКТИВАЦИЯ WARP
RESPONSE="$(sec PATCH "reg/$ID" "$TOKEN" -d '{"warp_enabled":true}')"

echo "$RESPONSE" | jq . >/dev/null 2>&1 || {
	echo "Ошибка активации WARP"
	echo "$RESPONSE"
	exit 1
}

PEER_PUB="$(echo "$RESPONSE" | jq -r '.result.config.peers[0].public_key')"
IPV4="$(echo "$RESPONSE" | jq -r '.result.config.interface.addresses.v4')"
IPV6="$(echo "$RESPONSE" | jq -r '.result.config.interface.addresses.v6')"

### СОЗДАНИЕ КОНФИГА
mkdir -p "$CONF_DIR"

cat > "$CONF_FILE" <<EOF
[Interface]
PrivateKey = $PRIV_KEY
Address = $IPV4, $IPV6
DNS = 1.1.1.1, 1.0.0.1
MTU = 1280

[Peer]
PublicKey = $PEER_PUB
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500
PersistentKeepalive = 25
EOF

### ГОТОВО
echo
echo "================ ГОТОВО ================"
echo "Конфиг сохранён: $CONF_FILE"
echo
cat "$CONF_FILE"
echo "========================================"
echo
echo "Запуск:"
echo "  wg-quick up warp"
echo
echo "Остановка:"
echo "  wg-quick down warp"
echo
