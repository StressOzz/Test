#!/bin/sh

echo "Проверяем зависимости..."

for pkg in wireguard-tools curl jq coreutils-base64; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        echo "Устанавливаю $pkg..."
        opkg update
        opkg install $pkg || {
            echo "Ошибка установки $pkg"
            exit 1
        }
    fi
done

echo "Генерируем ключи..."
priv="$(wg genkey)"
pub="$(printf "%s" "$priv" | wg pubkey)"

api="https://api.cloudflareclient.com/v0i1909051800"

ins() {
    curl -s \
        -H "User-Agent: okhttp/3.12.1" \
        -H "Content-Type: application/json" \
        -X "$1" "$api/$2" "${@:3}"
}

sec() {
    ins "$1" "$2" -H "Authorization: Bearer $3" "${@:4}"
}

echo "Регистрируем устройство в Cloudflare..."

response=$(ins POST "reg" \
-d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")

id=$(echo "$response" | jq -r '.result.id')
token=$(echo "$response" | jq -r '.result.token')

if [ -z "$id" ] || [ "$id" = "null" ]; then
    echo "Ошибка регистрации:"
    echo "$response"
    exit 1
fi

echo "Активируем WARP..."

response=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')

peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6')

if [ -z "$peer_pub" ] || [ "$peer_pub" = "null" ]; then
    echo "Ошибка получения конфигурации"
    exit 1
fi

conf=$(cat <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${client_ipv4}, ${client_ipv6}
DNS = 1.1.1.1, 2606:4700:4700::1111
MTU = 1280

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = 162.159.192.1:500
PersistentKeepalive = 25
EOF
)

echo
echo "========== WARP CONFIG =========="
echo "$conf"
echo "================================="
echo

echo "$conf" > /root/WARP.conf
echo "Файл сохранён: /root/WARP.conf"

conf_base64=$(echo -n "$conf" | base64 | tr -d '\n')
echo
echo "Base64 (если нужно куда-то вставить):"
echo "$conf_base64"
