#!/bin/sh

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

clear

echo -e "${YELLOW}Проверяем зависимости...${NC}"
echo -e "${YELLOW}Обновляем пакеты...${NC}"

if ! opkg update >/dev/null 2>&1; then
  echo -e "\n${RED}Ошибка обновления пакетов!${NC}"
  exit 1
fi

for pkg in wireguard-tools curl jq coreutils-base64; do
  if ! opkg list-installed 2>/dev/null | grep -qF "^$pkg "; then
    echo -e "${GREEN}Устанавливаем:${NC} $pkg"
    opkg install "$pkg" >/dev/null 2>&1 || {
      echo -e "\n${RED}Ошибка установки ${NC}$pkg"
      exit 1
    }
  fi
done

echo -e "${YELLOW}Генерируем ключи...${NC}"
priv="$(wg genkey)"
pub="$(printf "%s" "$priv" | wg pubkey)"

API_PATH="v0i1909051800"
API_HOST="api.cloudflareclient.com"
API_IPS="162.159.137.105 162.159.138.105"  # IP для Client orchestration API [page:2]

curl_json() {
  method="$1"; path="$2"; shift 2

  for ip in $API_IPS; do
    tmp_body="/tmp/warp_api_body.$$"
    tmp_meta="/tmp/warp_api_meta.$$"

    # -k НЕ используем: нам важна нормальная TLS-валидация
    curl -sS \
      --connect-timeout 5 --max-time 20 \
      --resolve "${API_HOST}:443:${ip}" \
      -o "$tmp_body" \
      -D "$tmp_meta" \
      -H "User-Agent: okhttp/3.12.1" \
      -H "Content-Type: application/json" \
      -X "$method" "https://${API_HOST}/${API_PATH}/${path}" "$@" \
      2>/tmp/warp_api_err.$$ 

    rc=$?

    http_code="$(awk 'toupper($1) ~ /^HTTP\// {c=$2} END{print c}' "$tmp_meta" 2>/dev/null)"
    body="$(cat "$tmp_body" 2>/dev/null)"

    rm -f "$tmp_body" "$tmp_meta"

    if [ $rc -ne 0 ]; then
      echo -e "${RED}curl ошибка${NC} (ip=${ip}, rc=${rc}):"
      cat /tmp/warp_api_err.$$ 2>/dev/null
      rm -f /tmp/warp_api_err.$$
      continue
    fi
    rm -f /tmp/warp_api_err.$$

    if [ -n "$http_code" ] && [ "$http_code" != "200" ]; then
      echo -e "${RED}HTTP не 200${NC} (ip=${ip}, code=${http_code}):"
      echo "$body"
      continue
    fi

    # Проверим что это JSON, и что там есть ожидаемые поля
    echo "$body" | jq -e '.' >/dev/null 2>&1 || {
      echo -e "${RED}Не JSON ответ${NC} (ip=${ip}):"
      echo "$body"
      continue
    }

    echo "$body"
    return 0
  done

  # Если дошли сюда — не получилось ни через один IP
  echo "{}"
  return 1
}

ins() {
  curl_json "$@"
}

sec() {
  method="$1"; path="$2"; token="$3"; shift 3
  ins "$method" "$path" -H "Authorization: Bearer $token" "$@"
}

echo -e "${GREEN}Регистрируем устройство в Cloudflare...${NC}"

response="$(ins POST "reg" \
  -d "{\"install_id\":\"\",\"tos\":\"$(date -u +%FT%TZ)\",\"key\":\"${pub}\",\"fcm_token\":\"\",\"type\":\"ios\",\"locale\":\"en_US\"}")"

id="$(echo "$response" | jq -r '.result.id // empty' 2>/dev/null)"
token="$(echo "$response" | jq -r '.result.token // empty' 2>/dev/null)"

if [ -z "$id" ] || [ -z "$token" ]; then
  echo -e "${RED}Ошибка регистрации:${NC}"
  echo "$response"
  exit 1
fi

echo -e "${GREEN}Активируем WARP...${NC}"

response="$(sec PATCH "reg/${id}" "$token" -d '{"warp_enabled":true}')"

peer_pub="$(echo "$response" | jq -r '.result.config.peers[0].public_key // empty')"
client_ipv4="$(echo "$response" | jq -r '.result.config.interface.addresses.v4 // empty')"
client_ipv6="$(echo "$response" | jq -r '.result.config.interface.addresses.v6 // empty')"

if [ -z "$peer_pub" ] || [ -z "$client_ipv4" ] || [ -z "$client_ipv6" ]; then
  echo -e "\n${RED}Ошибка получения конфигурации${NC}"
  echo "$response"
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
Endpoint = engage.cloudflareclient.com:4500
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
