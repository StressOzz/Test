#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"
WHITE="\033[1;37m"
BLUE="\033[0;34m"
GRAY='\033[38;5;239m'
DGRAY="\033[38;5;244m"

CONF="/root/WARP.conf"
IFNAME="AWG"

echo -e "\n${MAGENTA}Устанавливаем AWG + интерфейс${NC}"
echo -e "${GREEN}Обновляем список пакетов${NC}"
opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; exit; }
PKGARCH=$(opkg print-architecture | awk 'BEGIN {max=0} {if ($3 > max) {max = $3; arch = $2}} END {print arch}')
TARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f1)
SUBTARGET=$(ubus call system board | jsonfilter -e '@.release.target' | cut -d '/' -f2)
VERSION=$(ubus call system board | jsonfilter -e '@.release.version')
PKGPOSTFIX="_v${VERSION}_${PKGARCH}_${TARGET}_${SUBTARGET}.ipk"
BASE_URL="https://github.com/FreeRKN/awg-openwrt/releases/download/"
AWG_DIR="/tmp/amneziawg"
mkdir -p "$AWG_DIR"
install_pkg() {
local pkgname=$1
local filename="${pkgname}${PKGPOSTFIX}"
local url="${BASE_URL}v${VERSION}/${filename}"
    if wget -O "$AWG_DIR/$filename" "$url" >/dev/null 2>&1 ; then
        echo -e "${CYAN}Устанавливаем ${NC}$pkgname"
        if ! opkg install "$AWG_DIR/$filename" >/dev/null 2>&1 ; then
            echo -e "\n${RED}Ошибка установки $pkgname!${NC}\n"
           exit
        fi
    else
        echo -e "\n${RED}Ошибка! Не удалось скачать $filename${NC}\n"
        exit
    fi
}
install_pkg "kmod-amneziawg"
install_pkg "amneziawg-tools"
install_pkg "luci-proto-amneziawg"
install_pkg "luci-i18n-amneziawg-ru" >/dev/null 2>&1 || echo -e "${RED}Внимание: русская локализация не установлена (не критично)${NC}"
rm -rf "$AWG_DIR"
echo -e "${YELLOW}Перезапускаем сеть! Подождите...${NC}"
/etc/init.d/network restart >/dev/null 2>&1
sleep 10
echo -e "AmneziaWG ${GREEN}установлен!${NC}"

echo -e "${MAGENTA}Устанавливаем интерфейс AWG${NC}"
IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"
if grep -q "config interface '$IF_NAME'" /etc/config/network; then
echo -e "${RED}Интерфейс ${NC}$IF_NAME${RED} уже существует${NC}"
else
echo -e "${CYAN}Добавляем интерфейс ${NC}$IF_NAME"
uci batch <<EOF
set network.$IF_NAME=interface
set network.$IF_NAME.proto=$PROTO
set network.$IF_NAME.device=$DEV_NAME
commit network
EOF
fi
echo -e "${CYAN}Перезапускаем сеть${NC}"
/etc/init.d/network restart
/etc/init.d/firewall restart
/etc/init.d/uhttpd restart
echo -e "${GREEN}Интерфейс ${NC}$IF_NAME${GREEN} создан и активирован!${NC}"

sleep 10

echo -e "Проверяем зависимости..."

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
I1 = <b 0xc7000000010809a1ed4edbbe7615000044d017a61a0d774f04290f119e701ef0035df2b0ed571b0b575e6a07246b856eb6ec036fef07f1e07b861251ad737abeb67e64be714c1dcd865312b1b6c35c089c997aeb5c18f808696fe97289513945d84ca846467603e94e44224877f2c1d3261e4ac18740be4bd064369c94fc08978d99b54bf615250998639010c1284248e1d73004b81fcb20b559d8a17eced7eab3964b5b88ca7a3b8579fc8c1c934189e77143b4ac434138114b1048651b56545b87acbef0952763538f3ddeb37cfc6d58b4881c3b719d7ff78f6ee1324a2914a32381c05a64c700466d280be007253bb030d179c4f1b3dc221e1974e2ee6d6e2b9e8d709159b5ef22e1783dbba845c20ca1c83b066c73835920ad70b806df0aee0351e3fc9ab1e42e8b2a30fe235ff0612eee19744949cecee0463b76514ad90c1f7ceaa557c18586ab561d49482e73c85d0143785da14a441bf82f78783b61cccd44aecb1947516e79b5ca5a6b3a8aed6040fae0eeabdc55a88dc19ade832d99fca90c7a629cacc07192d7e47e3c6a271b95b0ea3392562a06a1cab79f40ea92916ebee197b7b5f14b251824e1ed20ff2ca80b1f03a43e45157589bc61b978e97851025b3b7ccc17d291e1cb60fe48a5c26829dce11dd23c2e73265a9ebf8617c985e4fee4681e863f990061f4dea465a7d2524bd0edcf4b48d4b8f25fc359b15babd2637284a4774077dca60091f1a781cfee1bef9713dd5943a579d7470bc5970542fbb27fdf77880a8d8751b1f642c7a3f019a05ab94bf63d3525ef34e9290b5c8d477f2714e6d6e3e4d35c1983f5e16fda57fcdf071b513f8f088dbe8d5a97577d17a5383a496c3f313adfdd47c962bbaebd6aa13b46439eb742622c29ca067db0ec1853064c3cbbffe0a215a19fce47d49703ed58ebbd89721172d256d1cf30188106fb2f863186511401fad54d087aa2fb3d1b85768db386bd7102e8060ac157bac011acdcdae2799b9aee1467c3424013455bd028fcaacdc3c77d28ea199967d617ea7d0d0815f3cc407934a76d1293dccba210d1709a13e5dd67c9ba47cd113f5bdd740358eff13164159fd09bc2f7ec6cfa64d9df7e2e2f88706b0ff3a92ccf6f078456cfe0bdd89292cfe2680badc1eac9f7d36efe8eb6912c7b164508d13e6c0911c15f73c233cbe4fc70ff2ade1e1be4bbb738e0939159e2078a9438f05b756a003371f4861481c38f1cdd2d7b06deb62869e9fe79a8abaa920646fa2e8fa28f0d80c136376c7b56046bae4c05c0cdf64efb8c47bbfc5a1a4c0b045061ef0d71618e0d206a1d7f245fd5c03191b152673ba8dff8e1b8de7c50234a93cba91e3888adb228cc02beded4b1c0946797d3ef02dec2edb6ad0ac21f89f4be364c317da7c22440e9f358d512203f4b7ab20388af68b8915d0152db2c8a0687bfaea870f7529bb92a22b35bd79bc6d490591406346ecd78342ee3563c4883a8251679691c2d4e963397e24653520795511b018915374c954bddb940a9d7a16d1c8bd798fc7dbfb0599a7074e13f87e14efa8d511bb2579ec029b1bda18fe971b30fbe19e986ff2686a69bf3f1bb929de93ae70345ebca998b11e0a2b41890cba628d8f6e7c4e94790735e5299b4ff07cd3080f7d53c9cbe1911d2cd5925b3213e033c272506a87886cf761a283a779564d3241e3c28f632e166b5d756e1786ce077614c4444e3f2aed5decb3613b925ea3e558c21d4faf8ba54edd0f3a5d4>

[Peer]
PublicKey = bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = engage.cloudflareclient.com:880
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
sleep 10
echo "Готово."



echo -e "\n${MAGENTA}Установка Podkop${NC}"

    REPO="https://api.github.com/repos/itdoginfo/podkop/releases/latest"
    DOWNLOAD_DIR="/tmp/podkop"

    PKG_IS_APK=0
    command -v apk >/dev/null 2>&1 && PKG_IS_APK=1

    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR"

    msg() {
        if [ -n "$2" ]; then
            printf "\033[32;1m%s \033[37;1m%s\033[0m\n" "$1" "$2"
        else
            printf "\033[32;1m%s\033[0m\n" "$1"
        fi
    }

    pkg_is_installed () {
        local pkg_name="$1"
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk list --installed | grep -q "$pkg_name"
        else
            opkg list-installed | grep -q "$pkg_name"
        fi
    }

    pkg_remove() {
        local pkg_name="$1"
        msg "Удаляем" "$pkg_name..."
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk del "$pkg_name" >/dev/null 2>&1
        else
            opkg remove --force-depends "$pkg_name" >/dev/null 2>&1
        fi
    }

    pkg_list_update() {
        msg "Обновляем список пакетов..."
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk update >/dev/null 2>&1
        else
            opkg update >/dev/null 2>&1
        fi
    }

    pkg_install() {
        local pkg_file="$1"
        msg "Устанавливаем" "$(basename "$pkg_file")"
        if [ "$PKG_IS_APK" -eq 1 ]; then
            apk add --allow-untrusted "$pkg_file" >/dev/null 2>&1
        else
            opkg install "$pkg_file" >/dev/null 2>&1
        fi
    }

    # Проверка системы
    MODEL=$(cat /tmp/sysinfo/model 2>/dev/null || echo "не определено")
    AVAILABLE_SPACE=$(df /overlay | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=26000
	
[ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ] && { 
    msg "Недостаточно свободного места"
    exit
}

nslookup google.com >/dev/null 2>&1 || { 
    msg "DNS не работает"
	exit
}


    if pkg_is_installed https-dns-proxy; then
        msg "Обнаружен конфликтный пакет" "https-dns-proxy. Удаляем..."
        pkg_remove luci-app-https-dns-proxy
        pkg_remove https-dns-proxy
        pkg_remove luci-i18n-https-dns-proxy*
    fi

    # Проверка sing-box
    if pkg_is_installed "^sing-box"; then
        sing_box_version=$(sing-box version | head -n 1 | awk '{print $3}')
        required_version="1.12.4"
        if [ "$(echo -e "$sing_box_version\n$required_version" | sort -V | head -n 1)" != "$required_version" ]; then
            msg "sing-box устарел. Удаляем..."
            service podkop stop >/dev/null 2>&1
            pkg_remove sing-box
        fi
    fi

    /usr/sbin/ntpd -q -p 194.190.168.1 -p 216.239.35.0 -p 216.239.35.4 -p 162.159.200.1 -p 162.159.200.123 >/dev/null 2>&1

pkg_list_update || { 
    msg "Не удалось обновить список пакетов"
	exit
}


    # Шаблон скачивания
    if [ "$PKG_IS_APK" -eq 1 ]; then
        grep_url_pattern='https://[^"[:space:]]*\.apk'
    else
        grep_url_pattern='https://[^"[:space:]]*\.ipk'
    fi

    download_success=0
    urls=$(wget -qO- "$REPO" 2>/dev/null | grep -o "$grep_url_pattern")
    for url in $urls; do
        filename=$(basename "$url")
        filepath="$DOWNLOAD_DIR/$filename"
        msg "Скачиваем" "$filename"
        if wget -q -O "$filepath" "$url" >/dev/null 2>&1 && [ -s "$filepath" ]; then
            download_success=1
        else
            msg "Ошибка скачивания" "$filename"
        fi
    done

[ $download_success -eq 0 ] && { 
    msg "Нет успешно скачанных пакетов"
	exit
}

    # Установка пакетов
    for pkg in podkop luci-app-podkop; do
        file=$(ls "$DOWNLOAD_DIR" | grep "^$pkg" | head -n 1)
        [ -n "$file" ] && pkg_install "$DOWNLOAD_DIR/$file"
    done

    # Русский интерфейс
    ru=$(ls "$DOWNLOAD_DIR" | grep "luci-i18n-podkop-ru" | head -n 1)
    if [ -n "$ru" ]; then
        if pkg_is_installed luci-i18n-podkop-ru; then
            msg "Обновляем русский язык..." "$ru"
            pkg_remove luci-i18n-podkop* >/dev/null 2>&1
            pkg_install "$DOWNLOAD_DIR/$ru"
        else
			pkg_install "$DOWNLOAD_DIR/$ru"

        fi
    fi

    # Очистка
    rm -rf "$DOWNLOAD_DIR"

    echo -e "Podkop ${GREEN}успешно установлен!${NC}\n"
    sleep 10



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
	option log_level 'warn'
	option exclude_ntp '0'
	option shutdown_correctly '0'

config section 'main'
	option connection_type 'vpn'
	option interface 'AWG'
	option domain_resolver_enabled '0'
	option user_domain_list_type 'disabled'
	option user_subnet_list_type 'disabled'
	option mixed_proxy_enabled '0'
	list community_lists 'telegram'
EOF

echo -e "AWG ${GREEN}интегрирован в ${NC}Podkop${GREEN}.${NC}"
echo -e "${CYAN}Запускаем ${NC}Podkop${NC}"
podkop restart >/dev/null 2>&1
echo -e "Podkop ${GREEN}готов к работе!${NC}\n"

/etc/init.d/network restart
sleep 10
echo "Готово."
