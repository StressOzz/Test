#!/bin/sh
CONF="/root/WARP.conf"
IFNAME="AWG"

echo "Проверяем зависимости..."

for pkg in wireguard-tools curl jq coreutils-base64; do
    if ! opkg list-installed | grep -q "^$pkg "; then
        echo "Устанавливаем $pkg..."
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
DNS = 1.1.1.1, 8.8.8.8
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
I1 = <b 0x12345>

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:4500
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


CONF="/root/WARP.conf"
IFNAME="AWG"

[ ! -f "$CONF" ] && { echo "WARP.conf не найден"; exit 1; }

echo "Читаем $CONF ..."

get_val() {
    grep "^$1" "$CONF" | head -n1 | sed "s/.*= //"
}

PRIVATE_KEY="$(get_val PrivateKey)"
ADDRESS_LINE="$(get_val Address)"
DNS_LINE="$(get_val DNS)"
JC="$(get_val Jc)"
JMIN="$(get_val Jmin)"
JMAX="$(get_val Jmax)"
S1="$(get_val S1)"
S2="$(get_val S2)"
H1="$(get_val H1)"
H2="$(get_val H2)"
H3="$(get_val H3)"
H4="$(get_val H4)"
I1="$(get_val I1)"

PUBLIC_KEY="$(grep -A5 "\[Peer\]" "$CONF" | grep PublicKey | sed 's/.*= //')"
ALLOWED_IPS="$(grep -A5 "\[Peer\]" "$CONF" | grep AllowedIPs | sed 's/.*= //')"
ENDPOINT="$(grep -A5 "\[Peer\]" "$CONF" | grep Endpoint | sed 's/.*= //')"
KEEPALIVE="$(grep -A5 "\[Peer\]" "$CONF" | grep PersistentKeepalive | sed 's/.*= //')"

IPV4="$(echo "$ADDRESS_LINE" | cut -d',' -f1 | xargs)"
IPV6="$(echo "$ADDRESS_LINE" | cut -d',' -f2 | xargs)"

DNS1="$(echo "$DNS_LINE" | cut -d',' -f1 | xargs)"
DNS2="$(echo "$DNS_LINE" | cut -d',' -f2 | xargs)"

ENDPOINT_HOST="$(echo "$ENDPOINT" | cut -d':' -f1)"
ENDPOINT_PORT="$(echo "$ENDPOINT" | cut -d':' -f2)"

echo "Удаляем старый интерфейс $IFNAME если есть..."
uci -q delete network.$IFNAME
uci -q delete network.amneziawg_$IFNAME

echo "Создаём интерфейс $IFNAME ..."

uci set network.$IFNAME="interface"
uci set network.$IFNAME.proto="amneziawg"
uci set network.$IFNAME.private_key="$PRIVATE_KEY"
uci add_list network.$IFNAME.addresses="$IPV4"
uci add_list network.$IFNAME.addresses="$IPV6"
uci set network.$IFNAME.awg_jc="$JC"
uci set network.$IFNAME.awg_jmin="$JMIN"
uci set network.$IFNAME.awg_jmax="$JMAX"
uci set network.$IFNAME.awg_s1="$S1"
uci set network.$IFNAME.awg_s2="$S2"
uci set network.$IFNAME.awg_h1="$H1"
uci set network.$IFNAME.awg_h2="$H2"
uci set network.$IFNAME.awg_h3="$H3"
uci set network.$IFNAME.awg_h4="$H4"
uci set network.$IFNAME.awg_i1="$I1"
uci add_list network.$IFNAME.dns="$DNS1"
uci add_list network.$IFNAME.dns="$DNS2"

uci set network.amneziawg_$IFNAME="amneziawg_$IFNAME"
uci set network.amneziawg_$IFNAME.description="WARP.conf"
uci set network.amneziawg_$IFNAME.public_key="$PUBLIC_KEY"

for ip in $(echo "$ALLOWED_IPS" | tr ',' ' '); do
    uci add_list network.amneziawg_$IFNAME.allowed_ips="$(echo $ip | xargs)"
done

uci set network.amneziawg_$IFNAME.persistent_keepalive="$KEEPALIVE"
uci set network.amneziawg_$IFNAME.endpoint_host="$ENDPOINT_HOST"
uci set network.amneziawg_$IFNAME.endpoint_port="$ENDPOINT_PORT"

uci commit network

echo
echo "Интерфейс создан. Перезапускаем сеть..."
/etc/init.d/network restart

echo "Готово."
