#!/bin/sh

URLS="
https://wgcli.vercel.app
https://santa-atmo.ru/warp/warp.php
https://warp-gen.vercel.app/generate-config
https://config-generator-warp.vercel.app/warp6s
https://config-generator-warp.vercel.app/warp4s
https://config-generator-warp.vercel.app/warps
https://warp-generator.vercel.app/api/warp
https://dulcet-fox-556b08.netlify.app/api/warp
https://warp-config-generator-theta.vercel.app/api/warp
https://generator-warp-config.vercel.app/warp4s?dns=1.1.1.1%2C%201.0.0.1%2C%202606%3A4700%3A4700%3A%3A1111%2C%202606%3A4700%3A4700%3A%3A1001&allowedIPs=0.0.0.0%2F0%2C%20%3A%3A%2F0
https://valokda-amnezia.vercel.app/api/warp
"

for URL in $URLS; do
    echo
    echo "========================================"
    echo "$URL"
    echo "========================================"

    response="$(curl -fsSL --max-time 15 "$URL" 2>/dev/null)"

    if [ -z "$response" ]; then
        echo "Ошибка получения данных."
        continue
    fi

    echo "$response" | jq empty >/dev/null 2>&1 || {
        echo "Ответ не является JSON."
        continue
    }

    echo "✓ JSON получен"

    jq -r '
        {
            id: .result.id,
            key: .result.key,
            peer_public_key: .result.config.peers[0].public_key,
            ipv4: .result.config.interface.addresses.v4,
            ipv6: .result.config.interface.addresses.v6,
            endpoint_host: .result.config.peers[0].endpoint.host,
            endpoint_v4: .result.config.peers[0].endpoint.v4,
            endpoint_v6: .result.config.peers[0].endpoint.v6,
            license: .result.account.license
        }
        | to_entries[]
        | "\(.key): \(.value // "-")"
    ' <<EOF
$response
EOF

done
