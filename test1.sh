#!/bin/sh

API="https://santa-atmo.ru/warp/warp.php"

echo "Получаем данные..."

response="$(curl -fsSL "$API")" || {
    echo "Ошибка: не удалось получить данные."
    exit 1
}

echo "$response" | jq empty >/dev/null 2>&1 || {
    echo "Ошибка: получен некорректный JSON."
    exit 1
}

read -r DEVICE_ID PRIVATE_KEY PEER_PUBLIC_KEY CLIENT_IPV4 CLIENT_IPV6 LICENSE ENDPOINT_HOST ENDPOINT_V4 ENDPOINT_V6 <<EOF
$(echo "$response" | jq -r '
[
    .result.id,
    .result.key,
    .result.config.peers[0].public_key,
    .result.config.interface.addresses.v4,
    .result.config.interface.addresses.v6,
    .result.account.license,
    .result.config.peers[0].endpoint.host,
    .result.config.peers[0].endpoint.v4,
    .result.config.peers[0].endpoint.v6
] | @tsv')
EOF

echo "Device ID      : $DEVICE_ID"
echo "Private Key    : $PRIVATE_KEY"
echo "Peer PublicKey : $PEER_PUBLIC_KEY"
echo "IPv4           : $CLIENT_IPV4"
echo "IPv6           : $CLIENT_IPV6"
echo "License        : $LICENSE"
echo "Endpoint Host  : $ENDPOINT_HOST"
echo "Endpoint IPv4  : $ENDPOINT_V4"
echo "Endpoint IPv6  : $ENDPOINT_V6"
