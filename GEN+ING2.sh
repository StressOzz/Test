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
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111, 2606:4700:4700::1001
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
I1 = <b 0xc70000000108ce1bf31eec7d93360000449e227e4596ed7f75c4d35ce31880b4133107c822c6355b51f0d7c1bba96d5c210a48aca01885fed0871cfc37d59137d73b506dc013bb4a13c060ca5b04b7ae215af71e37d6e8ff1db235f9fe0c25cb8b492471054a7c8d0d6077d430d07f6e87a8699287f6e69f54263c7334a8e144a29851429bf2e350e519445172d36953e96085110ce1fb641e5efad42c0feb4711ece959b72cc4d6f3c1e83251adb572b921534f6ac4b10927167f41fe50040a75acef62f45bded67c0b45b9d655ce374589cad6f568b8475b2e8921ff98628f86ff2eb5bcce6f3ddb7dc89e37c5b5e78ddc8d93a58896e530b5f9f1448ab3b7a1d1f24a63bf981634f6183a21af310ffa52e9ddf5521561760288669de01a5f2f1a4f922e68d0592026bbe4329b654d4f5d6ace4f6a23b8560b720a5350691c0037b10acfac9726add44e7d3e880ee6f3b0d6429ff33655c297fee786bb5ac032e48d2062cd45e305e6d8d8b82bfbf0fdbc5ec09943d1ad02b0b5868ac4b24bb10255196be883562c35a713002014016b8cc5224768b3d330016cf8ed9300fe6bf39b4b19b3667cddc6e7c7ebe4437a58862606a2a66bd4184b09ab9d2cd3d3faed4d2ab71dd821422a9540c4c5fa2a9b2e6693d411a22854a8e541ed930796521f03a54254074bc4c5bca152a1723260e7d70a24d49720acc544b41359cfc252385bda7de7d05878ac0ea0343c77715e145160e6562161dfe2024846dfda3ce99068817a2418e66e4f37dea40a21251c8a034f83145071d93baadf050ca0f95dc9ce2338fb082d64fbc8faba905cec66e65c0e1f9b003c32c943381282d4ab09bef9b6813ff3ff5118623d2617867e25f0601df583c3ac51bc6303f79e68d8f8de4b8363ec9c7728b3ec5fcd5274edfca2a42f2727aa223c557afb33f5bea4f64aeb252c0150ed734d4d8eccb257824e8e090f65029a3a042a51e5cc8767408ae07d55da8507e4d009ae72c47ddb138df3cab6cc023df2532f88fb5a4c4bd917fafde0f3134be09231c389c70bc55cb95a779615e8e0a76a2b4d943aabfde0e394c985c0cb0376930f92c5b6998ef49ff4a13652b787503f55c4e3d8eebd6e1bc6db3a6d405d8405bd7a8db7cefc64d16e0d105a468f3d33d29e5744a24c4ac43ce0eb1bf6b559aed520b91108cda2de6e2c4f14bc4f4dc58712580e07d217c8cca1aaf7ac04bab3e7b1008b966f1ed4fba3fd93a0a9d3a27127e7aa587fbcc60d548300146bdc126982a58ff5342fc41a43f83a3d2722a26645bc961894e339b953e78ab395ff2fb854247ad06d446cc2944a1aefb90573115dc198f5c1efbc22bc6d7a74e41e666a643d5f85f57fde81b87ceff95353d22ae8bab11684180dd142642894d8dc34e402f802c2fd4a73508ca99124e428d67437c871dd96e506ffc39c0fc401f666b437adca41fd563cbcfd0fa22fbbf8112979c4e677fb533d981745cceed0fe96da6cc0593c430bbb71bcbf924f70b4547b0bb4d41c94a09a9ef1147935a5c75bb2f721fbd24ea6a9f5c9331187490ffa6d4e34e6bb30c2c54a0344724f01088fb2751a486f425362741664efb287bce66c4a544c96fa8b124d3c6b9eaca170c0b530799a6e878a57f402eb0016cf2689d55c76b2a91285e2273763f3afc5bc9398273f5338a06d>

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

echo -e "Меняем конфигурацию в Podkop"
    # Создаём / меняем /etc/config/podkop
    cat <<EOF >/etc/config/podkop
config settings 'settings'
	option dns_type 'udp'
	option dns_server '8.8.8.8'
	option bootstrap_dns_server '77.88.8.8'
	option dns_rewrite_ttl '60'
	list source_network_interfaces 'br-lan'
	option enable_output_network_interface '0'
	option enable_badwan_interface_monitoring '0'
	option enable_yacd '0'
	option disable_quic '0'
	option update_interval '1d'
	option download_lists_via_proxy '0'
	option dont_touch_dhcp '0'
	option config_path '/etc/sing-box/config.json'
	option cache_path '/tmp/sing-box/cache.db'
	option exclude_ntp '0'
	option shutdown_correctly '0'

config section 'main'
	option connection_type 'vpn'
	option interface 'AWG'
	option domain_resolver_enabled '0'
	option user_domain_list_type 'disabled'
	option user_subnet_list_type 'disabled'
	option mixed_proxy_enabled '0'
	list community_lists 'russia_inside'
	list community_lists 'hodca'
EOF

echo -e "AWG интегрирован в Podkop."
echo -e "Запускаем Podkop"
podkop enable >/dev/null 2>&1
echo -e "Применяем конфигурацию"
podkop reload >/dev/null 2>&1
podkop restart >/dev/null 2>&1
echo -e "Обновляем списки"
podkop list_update >/dev/null 2>&1
echo -e "Перезапускаем сервис"
podkop restart >/dev/null 2>&1
echo -e "Podkop готов к работе!\n"
