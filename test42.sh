#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'
MAGENTA="\033[1;35m"
CYAN="\033[1;36m"

clear

chose_endpoint() {

echo -e "${CYAN}Получаем список Endpoint...${NC}"

EP_LIST="$(curl -fsSL https://raw.githubusercontent.com/STR97/STRUGOV/refs/heads/main/end%20point)" || {
    echo -e "${RED}Не удалось загрузить список Endpoint${NC}"
    exit 1
}

echo
echo -e "${MAGENTA}Выберите страну:${NC}"

i=1

while IFS='|' read -r name ep; do

    case "$name" in
        *Текущая*) country="Россия    " ;;
        *Нидерланд*) country="Нидерланды" ;;
        *Америка*) country="Америка   " ;;
        *Сингапур*) country="Сингапур  " ;;
        *Латвия*) country="Латвия    " ;;
        *Герман*) country="Германия  " ;;
        *Литва*) country="Литва     " ;;
        *Финлянд*) country="Финляндия" ;;
        *) country="$name" ;;
    esac

    host="${ep%%:*}"

    ping_ms="$(ping -c1 -W1 "$host" 2>/dev/null | awk -F'/' 'END{print $5}')"
    [ -z "$ping_ms" ] && ping_ms="TimeOut"

    # Один пробел перед номером для 1–9
    printf "%2d) %s | %s ms\n" "$i" "$country" "$ping_ms"

    i=$((i+1))

done <<EOF
$EP_LIST
EOF

echo
printf "${CYAN}Введите номер:${NC} "
read num

ENDPOINT="$(echo "$EP_LIST" | sed -n "${num}p" | cut -d'|' -f2)"

if [ -z "$ENDPOINT" ]; then
    ENDPOINT="engage.cloudflareclient.com:4500"
fi

echo
}



echo -e "${MAGENTA}Генерируем WARP.conf${NC}"

if command -v apk >/dev/null 2>&1; then
PKG="apk"
elif command -v opkg >/dev/null 2>&1; then
PKG="opkg"
else
echo -e "${RED}Не найден пакетный менеджер!${NC}"
exit 1
fi

echo -e "${CYAN}Обновляем пакеты...${NC}"

if [ "$PKG" = "apk" ]; then
apk update >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка обновления пакетов!${NC}"
exit 1
}
else
opkg update >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка обновления пакетов!${NC}"
exit 1
}
fi

install_pkg() {
pkg="$1"

if [ "$PKG" = "apk" ]; then
apk info -e "$pkg" >/dev/null 2>&1 && return
echo -e "${GREEN}Устанавливаем:${NC} $pkg"
apk add "$pkg" >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка установки${NC} $pkg"
exit 1
}
else
opkg list-installed 2>/dev/null | grep -qF "^$pkg " && return
echo -e "${GREEN}Устанавливаем:${NC} $pkg"
opkg install "$pkg" >/dev/null 2>&1 || {
echo -e "\n${RED}Ошибка установки${NC} $pkg"
exit 1
}
fi
}

echo -e "${CYAN}Проверяем зависимости...${NC}"

for pkg in wireguard-tools curl jq coreutils-base64; do
install_pkg "$pkg"
done

echo -e "${YELLOW}Генерируем ключи...${NC}"
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

echo -e "${CYAN}Регистрируем устройство в Cloudflare...${NC}"

response=$(ins POST "reg" \
-d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")

id=$(echo "$response" | jq -r '.result.id')
token=$(echo "$response" | jq -r '.result.token')

if [ -z "$id" ] || [ "$id" = "null" ]; then
echo -e "${RED}Ошибка регистрации${NC} $response"
exit 1
fi

################################################################################################
chose_endpoint
################################################################################################

echo -e "${GREEN}Активируем WARP...${NC}"

response=$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')

peer_pub=$(echo "$response" | jq -r '.result.config.peers[0].public_key')
client_ipv4=$(echo "$response" | jq -r '.result.config.interface.addresses.v4')
client_ipv6=$(echo "$response" | jq -r '.result.config.interface.addresses.v6')

if [ -z "$peer_pub" ] || [ "$peer_pub" = "null" ]; then
echo -e "\n${RED}Ошибка получения конфигурации${NC}"
exit 1
fi

conf=$(cat <<EOF
[Interface]
PrivateKey = ${priv}
Address = ${client_ipv4}, ${client_ipv6}
DNS = 1.1.1.1, 2606:4700:4700::1111
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
I1 = <b 0x5245474953544552207369703a676f6f676c652e636f6d205349502f322e300d0a5669613a205349502f322e302f554450203139322e3136382e3132312e36323a353036303b6272616e63683d7a39684734624b6635633762313765616462303238333334346136633033610d0a4d61782d466f7277617264733a2037300d0a546f3a203c7369703a7573657240676f6f676c652e636f6d3e0d0a46726f6d3a203c7369703a7573657240676f6f676c652e636f6d3e3b7461673d323938376135316463353839613831650d0a43616c6c2d49443a2036313663363636333036613366393361336665636635663233366239386431360d0a435365713a20312052454749535445520d0a436f6e746163743a203c7369703a75736572403139322e3136382e34352e3139303a353036303e0d0a557365722d4167656e743a205a6f6970657220352e302e300d0a457870697265733a20363139310d0a436f6e74656e742d4c656e6774683a20300d0a0d0a>

[Peer]
PublicKey = ${peer_pub}
AllowedIPs = 0.0.0.0/0, ::/0
Endpoint = ${ENDPOINT}
PersistentKeepalive = 25
EOF
)

echo
echo -e "${GREEN}========== ${YELLOW}WARP CONFIG${GREEN} ==========${NC}"
echo "$conf"
echo -e "${GREEN}=================================${NC}"
echo

echo "$conf" > /root/WARP.conf
echo -e "${YELLOW}Файл сохранён:${NC} /root/WARP.conf"
