#!/bin/sh

REPO="xyzmean/splify"
API="https://api.github.com/repos/$REPO/releases/latest"
CF_API_VERSION="v0a1922"
CF_DIRECT="https://api.cloudflareclient.com"
CF_UA="okhttp/3.12.1"
CF_CLIENT_VER="a-6.3-1922"
WORKER_URL="${WORKER_URL:-https://wgcli.vercel.app}"
WARP_EP="engage.cloudflareclient.com:4500"
WARP_IFACE="warp0"
TMP="$(mktemp -d /tmp/splify.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
AWG_JC=4
AWG_JMIN=40
AWG_JMAX=70
AWG_H1=1
AWG_H2=2
AWG_H3=3
AWG_H4=4
AWG_S1=0
AWG_S2=0
AWG_I1="<b 0xce000000010897a297ecc34cd6dd000044d0ec2e2e1ea2991f467ace4222129b5a098823784694b4897b9986ae0b7280135fa85e196d9ad980b150122129ce2a9379531b0fd3e871ca5fdb883c369832f730e272d7b8b74f393f9f0fa43f11e510ecb2219a52984410c204cf875585340c62238e14ad04dff382f2c200e0ee22fe743b9c6b8b043121c5710ec289f471c91ee414fca8b8be8419ae8ce7ffc53837f6ade262891895f3f4cecd31bc93ac5599e18e4f01b472362b8056c3172b513051f8322d1062997ef4a383b01706598d08d48c221d30e74c7ce000cdad36b706b1bf9b0607c32ec4b3203a4ee21ab64df336212b9758280803fcab14933b0e7ee1e04a7becce3e2633f4852585c567894a5f9efe9706a151b615856647e8b7dba69ab357b3982f554549bef9256111b2d67afde0b496f16962d4957ff654232aa9e845b61463908309cfd9de0a6abf5f425f577d7e5f6440652aa8da5f73588e82e9470f3b21b27b28c649506ae1a7f5f15b876f56abc4615f49911549b9bb39dd804fde182bd2dcec0c33bad9b138ca07d4a4a1650a2c2686acea05727e2a78962a840ae428f55627516e73c83dd8893b02358e81b524b4d99fda6df52b3a8d7a5291326e7ac9d773c5b43b8444554ef5aea104a738ed650aa979674bbed38da58ac29d87c29d387d80b526065baeb073ce65f075ccb56e47533aef357dceaa8293a523c5f6f790be90e4731123d3c6152a70576e90b4ab5bc5ead01576c68ab633ff7d36dcde2a0b2c68897e1acfc4d6483aaaeb635dd63c96b2b6a7a2bfe042f6aed82e5363aa850aace12ee3b1a93f30d8ab9537df483152a5527faca21efc9981b304f11fc95336f5b9637b174c5a0659e2b22e159a9fed4b8e93047371175b1d6d9cc8ab745f3b2281537d1c75fb9451871864efa5d184c38c185fd203de206751b92620f7c369e031d2041e152040920ac2c5ab5340bfc9d0561176abf10a147287ea90758575ac6a9f5ac9f390d0d5b23ee12af583383d994e22c0cf42383834bcd3ada1b3825a0664d8f3fb678261d57601ddf94a8a68a7c273a18c08aa99c7ad8c6c42eab67718843597ec9930457359dfdfbce024afc2dcf9348579a57d8d3490b2fa99f278f1c37d87dad9b221acd575192ffae1784f8e60ec7cee4068b6b988f0433d96d6a1b1865f4e155e9fe020279f434f3bf1bd117b717b92f6cd1cc9bea7d45978bcc3f24bda631a36910110a6ec06da35f8966c9279d130347594f13e9e07514fa370754d1424c0a1545c5070ef9fb2acd14233e8a50bfc5978b5bdf8bc1714731f798d21e2004117c61f2989dd44f0cf027b27d4019e81ed4b5c31db347c4a3a4d85048d7093cf16753d7b0d15e078f5c7a5205dc2f87e330a1f716738dce1c6180e9d02869b5546f1c4d2748f8c90d9693cba4e0079297d22fd61402dea32ff0eb69ebd65a5d0b687d87e3a8b2c42b648aa723c7c7daf37abcc4bb85caea2ee8f55bec20e913b3324ab8f5c3304f820d42ad1b9f2ffc1a3af9927136b4419e1e579ab4c2ae3c776d293d397d575df181e6cae0a4ada5d67ecea171cca3288d57c7bbdaee3befe745fb7d634f70386d873b90c4d6c6596bb65af68f9e5121e67ebf0d89d3c909ceedfb32ce9575a7758ff080724e1ab5d5f43074ecb53a479af21ed03d7b6899c36631c0166f9d47e5e1d4528a5d3d3f744029c4b1c190cbfbad06f5f83f7ad0429fa9a2719c56ffe3783460e166de2d8>"

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mВнимание:\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

# ──────────────────────────── 1. environment checks ────────────────────────
[ "$(id -u)" = "0" ] || err "запустите от root."

PKG_MANAGER=""
PKG_EXT=""
if command -v apk >/dev/null 2>&1; then
    PKG_MANAGER="apk"
    PKG_EXT="apk"
elif command -v opkg >/dev/null 2>&1; then
    PKG_MANAGER="opkg"
    PKG_EXT="ipk"
else
    err "не найден пакетный менеджер (apk/opkg). Нужен OpenWrt."
fi

command -v wget  >/dev/null 2>&1 || err "не найден wget."

if [ "$PKG_MANAGER" = "opkg" ]; then
    if ! opkg list-installed 2>/dev/null | grep -q "^nftables "; then
        say "nftables не найден. Пробую установить…"
        opkg update >/dev/null 2>&1 || true
        opkg install nftables >/dev/null 2>&1 || warn "Не удалось установить nftables — splify-firewall может не работать."
    fi
fi

for _dep in curl jq; do
  if ! command -v "$_dep" >/dev/null 2>&1; then
    say "Ставлю зависимость: $_dep…"
    if [ "$PKG_MANAGER" = "apk" ]; then
        apk add "$_dep" >/dev/null 2>&1 || err "не удалось установить $_dep (apk add $_dep)."
    else
        opkg update >/dev/null 2>&1 || true
        opkg install "$_dep" >/dev/null 2>&1 || err "не удалось установить $_dep (opkg install $_dep)."
    fi
  fi
done

install_splify() {
  if command -v splify-ctl >/dev/null 2>&1 || [ -x /usr/local/sbin/splify-ctl ]; then
    say "splify уже установлен."
    return 0
  fi
  say "Ищу последний релиз splify…"
  META="$TMP/meta.json"
  wget -qO "$META" "$API" || err "не удалось получить данные релиза (нет интернета?)."
  URLS="$(tr ',' '\n' <"$META" | sed -n 's/.*"browser_download_url": *"\([^"]*\.'$PKG_EXT'\)".*/\1/p')"
  [ -n "$URLS" ] || err "в последнем релизе нет .$PKG_EXT. Возможно, релиз ещё не собран."

  say "Скачиваю пакеты…"
  for u in $URLS; do
    case "$u" in
      *splify*) wget -qO "$TMP/${u##*/}" "$u" || err "не удалось скачать $u" ;;
    esac
  done
  for pkg in splify- luci-app-splify- luci-i18n-splify-ru-; do
    ls "$TMP/$pkg"*.$PKG_EXT >/dev/null 2>&1 || err "в релизе не хватает пакета $pkg*.$PKG_EXT"
  done

  say "Устанавливаю splify…"
  if [ "$PKG_MANAGER" = "apk" ]; then
    apk add --allow-untrusted "$TMP"/*.$PKG_EXT || err "apk add не выполнился."
  else
    opkg install "$TMP"/*.$PKG_EXT || err "opkg install не выполнился."
  fi

  rm -f /tmp/luci-indexcache* /tmp/luci-modulecache* 2>/dev/null || true
  /etc/init.d/rpcd reload 2>/dev/null || /etc/init.d/rpcd restart 2>/dev/null || true
  for s in splify splify-agent; do
    if [ -x "/etc/init.d/$s" ] && "/etc/init.d/$s" enabled 2>/dev/null; then
      "/etc/init.d/$s" restart 2>/dev/null || true
    fi
  done
}

# ──────────────────────────── 3. install AmneziaWG ──────────────────────────
install_awg() {
  _awg_installed=0
  if [ "$PKG_MANAGER" = "apk" ]; then
    apk info -e kmod-amneziawg >/dev/null 2>&1 && _awg_installed=1
  else
    opkg list-installed 2>/dev/null | grep -q "^kmod-amneziawg " && _awg_installed=1
  fi

  if [ "$_awg_installed" = "1" ]; then
    say "AmneziaWG (kmod) уже установлен."
  else
    say "AmneziaWG не найден — устанавливаю поддержку…"
    if wget -qO "$TMP/awg-install.sh" \
        "https://raw.githubusercontent.com/Slava-Shchipunov/awg-openwrt/refs/heads/master/amneziawg-install.sh"; then
      sh "$TMP/awg-install.sh" -n -e \
        || warn "AmneziaWG: установка не удалась — WARP-туннель не поднимется без kmod."
    else
      err "Не удалось скачать установщик AmneziaWG (нет WARP без него)."
    fi
  fi

  if ! lsmod 2>/dev/null | grep -q '^amneziawg '; then
    modprobe amneziawg 2>/dev/null \
      || insmod "/lib/modules/$(uname -r)/amneziawg.ko" 2>/dev/null \
      || warn "amneziawg: не удалось загрузить kmod — может потребоваться перезагрузка."
  fi
  command -v awg >/dev/null 2>&1 || command -v wg >/dev/null 2>&1 \
    || err "не найден awg/wg — невозможно сгенерировать ключи WARP."
}

# ──────────────────────────── 4. register Cloudflare WARP ───────────────────
reg_url() {
  if [ -n "$WORKER_URL" ]; then
    printf '%s/api/%s' "${WORKER_URL%/}" "$1"
  else
    printf '%s/%s/%s' "$CF_DIRECT" "$CF_API_VERSION" "$1"
  fi
}

find_best_endpoint() {
  say "Подбираем лучший WARP эндпоинт (исключая DME)…"
  _prefixes="188.114.96. 188.114.97. 188.114.98. 188.114.99. 162.159.192. 162.159.193. 162.159.195. 8.34.146. 8.39.214. 8.39.204. 8.6.112. 8.35.211. 8.39.125. 8.47.69."
  
  _candidates=$(awk -v prefixes="$_prefixes" 'BEGIN {
      srand();
      n = split(prefixes, arr, " ");
      for (i=0; i<100; i++) {
          idx = int(rand() * n) + 1;
          last = int(rand() * 256);
          print arr[idx] last;
      }
  }')
  
  _pings="$TMP/warp_pings"
  _count=0
  for ip in $_candidates; do
    (
      if trace_data=$(curl -s --connect-timeout 2 -w "\n%{time_total}" -H "Host: trace.cloudflare.com" "http://${ip}/cdn-cgi/trace"); then
        colo=$(echo "$trace_data" | awk -F'=' '$1=="colo"{print $2}')
        case "$colo" in
          DME) exit 0 ;;
          "")  exit 0 ;;
        esac
        ping_ms=$(echo "$trace_data" | tail -n 1 | awk '{printf "%d", $1 * 1000}')
        [ -n "$ping_ms" ] && echo "$ping_ms $ip $colo" >> "$_pings"
      fi
    ) &
    _count=$((_count + 1))
    [ $((_count % 20)) -eq 0 ] && wait
  done
  wait
  
  if [ -s "$_pings" ]; then
    _best=$(sort -n "$_pings" | head -n 1)
    _best_ping=$(echo "$_best" | awk '{print $1}')
    _best_ip=$(echo "$_best" | awk '{print $2}')
    _best_colo=$(echo "$_best" | awk '{print $3}')
    say "Выбран эндпоинт: $_best_ip (colo: $_best_colo, ping: ${_best_ping}ms)"
    WARP_EP="${_best_ip}:500"
  else
    warn "Не удалось найти подходящий эндпоинт среди 100 проверенных."
    warn "Часть ресурсов может не работать! Устанавливаем эндпоинт по умолчанию."
    WARP_EP="engage.cloudflareclient.com:500"
  fi
}

register_warp() {
  say "Регистрирую устройство Cloudflare WARP…"
  [ -n "$WORKER_URL" ] \
    && say "Через прокси: $WORKER_URL" \
    || warn "WORKER_URL не задан — пробую api.cloudflareclient.com напрямую (может быть заблокирован)."

  if command -v awg >/dev/null 2>&1; then GEN=awg; else GEN=wg; fi
  PRIV="$("$GEN" genkey)"
  PUB="$(printf '%s\n' "$PRIV" | "$GEN" pubkey)"
  TOS="$(date -u +%Y-%m-%dT%H:%M:%S.000000000Z)"

  REG="$TMP/reg.json"
  curl -fsSL --max-time 30 -X POST "$(reg_url reg)" \
    -H "User-Agent: $CF_UA" \
    -H "CF-Client-Version: $CF_CLIENT_VER" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d "{\"key\":\"$PUB\",\"install_id\":\"\",\"fcm_token\":\"\",\"model\":\"PC\",\"locale\":\"en_US\",\"tos\":\"$TOS\",\"type\":\"Android\"}" \
    -o "$REG" \
    || err "регистрация WARP не удалась. Если API заблокирован вашим провайдером — задайте WORKER_URL (см. contrib/warp-api-proxy-vercel)."

  REG_ID="$(jq -r '.id'    "$REG")"
  REG_TOK="$(jq -r '.token' "$REG")"
  [ -n "$REG_ID" ] && [ "$REG_ID" != "null" ] || err "WARP: нет id в ответе."
  [ -n "$REG_TOK" ] && [ "$REG_TOK" != "null" ] || err "WARP: нет token в ответе."

  WARP="$TMP/warp.json"
  if ! jq -e '.config.peers[0].public_key' "$REG" >/dev/null 2>&1; then
    if ! curl -fsSL --max-time 30 -X GET "$(reg_url "reg/$REG_ID")" \
          -H "User-Agent: $CF_UA" \
          -H "CF-Client-Version: $CF_CLIENT_VER" \
          -H "Accept: application/json" \
          -H "Authorization: Bearer $REG_TOK" \
          -o "$WARP" 2>/dev/null; then
      cp "$REG" "$WARP"
    fi
  else
    cp "$REG" "$WARP"
  fi

  WARP_PEER="$(jq -r '.config.peers[0].public_key'               "$WARP")"
  WARP_V4="$(jq -r '.config.interface.addresses.v4'               "$WARP")"
  WARP_V6="$(jq -r '.config.interface.addresses.v6 // ""'         "$WARP")"
  [ -n "$WARP_PEER" ] && [ "$WARP_PEER" != "null" ] || err "WARP: нет peer public_key в ответе."
  [ -n "$WARP_V4" ]   && [ "$WARP_V4"   != "null" ] || err "WARP: нет client IPv4 в ответе."

  case "$WARP_V4" in
    */*) : ;;
    *)   WARP_V4="$WARP_V4/32" ;;
  esac
  if [ -n "$WARP_V6" ]; then
    case "$WARP_V6" in
      */*) : ;;
      *)   WARP_V6="$WARP_V6/128" ;;
    esac
  fi

  say "WARP зарегистрирован: $WARP_V4${WARP_V6:+, $WARP_V6}"
}

# ──────────────────────────── 5. create warp0 interface ─────────────────────
create_warp_iface() {
  if [ -n "$(uci -q get "network.$WARP_IFACE")" ]; then
    say "Интерфейс $WARP_IFACE уже существует — перенастраиваю."
    ifdown "$WARP_IFACE" >/dev/null 2>&1 || true
  fi

  say "Создаю интерфейс $WARP_IFACE (AmneziaWG + WARP)…"
  uci -q set "network.$WARP_IFACE=interface"
  uci set "network.$WARP_IFACE.proto=amneziawg"
  uci set "network.$WARP_IFACE.private_key=$PRIV"
  uci -q delete "network.$WARP_IFACE.addresses" || true
  uci add_list "network.$WARP_IFACE.addresses=$WARP_V4"
  [ -n "$WARP_V6" ] && uci add_list "network.$WARP_IFACE.addresses=$WARP_V6"
  uci -q delete "network.$WARP_IFACE.dns" || true
  uci add_list "network.$WARP_IFACE.dns=1.1.1.1"
  uci set "network.$WARP_IFACE.mtu=1280"
  uci set "network.$WARP_IFACE.route_allowed_ips=0"

  uci set "network.$WARP_IFACE.awg_jc=$AWG_JC"
  uci set "network.$WARP_IFACE.awg_jmin=$AWG_JMIN"
  uci set "network.$WARP_IFACE.awg_jmax=$AWG_JMAX"
  uci set "network.$WARP_IFACE.awg_h1=$AWG_H1"
  uci set "network.$WARP_IFACE.awg_h2=$AWG_H2"
  uci set "network.$WARP_IFACE.awg_h3=$AWG_H3"
  uci set "network.$WARP_IFACE.awg_h4=$AWG_H4"
  uci set "network.$WARP_IFACE.awg_s1=$AWG_S1"
  uci set "network.$WARP_IFACE.awg_s2=$AWG_S2"
  uci set "network.$WARP_IFACE.awg_i1=$AWG_I1"

  _pt="amneziawg_$WARP_IFACE"
  while [ -n "$(uci -q get "network.@${_pt}[0]")" ]; do uci -q delete "network.@${_pt}[0]" || true; done
  uci add network "$_pt" >/dev/null
  uci set "network.@${_pt}[-1].public_key=$WARP_PEER"
  uci -q delete "network.@${_pt}[-1].allowed_ips" || true
  uci add_list "network.@${_pt}[-1].allowed_ips=0.0.0.0/0"
  uci add_list "network.@${_pt}[-1].allowed_ips=::/0"
  uci set "network.@${_pt}[-1].endpoint_host=${WARP_EP%:*}"
  uci set "network.@${_pt}[-1].endpoint_port=${WARP_EP##*:}"
  uci set "network.@${_pt}[-1].persistent_keepalive=25"

  uci commit network
  /etc/init.d/network restart
  
  ifup "$WARP_IFACE" >/dev/null 2>&1 || warn "ifup $WARP_IFACE не удался — проверьте в LuCI."
}

# ──────────────────────────── 6. register endpoint in splify ────────────────
register_in_splify() {
  _ei=0
  while [ -n "$(uci -q get "splify.@endpoint[$_ei]" 2>/dev/null)" ]; do
    _ei_if="$(uci -q get "splify.@endpoint[$_ei].iface" 2>/dev/null)"
    if [ -n "$_ei_if" ] && [ -z "$(uci -q get "network.$_ei_if" 2>/dev/null)" ]; then
      say "Удаляю фантомный endpoint $_ei_if (нет такого интерфейса в network)."
      uci -q delete "splify.@endpoint[$_ei]" || true
    else
      _ei=$((_ei + 1))
    fi
  done
  uci commit splify

  if grep -q "option iface '$WARP_IFACE'" /etc/config/splify 2>/dev/null; then
    say "endpoint $WARP_IFACE уже зарегистрирован в splify."
  else
    say "Регистрирую $WARP_IFACE как endpoint splify (приоритет 1)…"
    cat >>/etc/config/splify <<EOF

config endpoint
	option iface '$WARP_IFACE'
	option priority '1'
	option type 'wg'
EOF
  fi
  if command -v splify-apply >/dev/null 2>&1; then
    splify-apply >/dev/null 2>&1 || warn "splify-apply завершился с ошибкой — см. Сервисы → splify."
  fi
  [ -x /etc/init.d/splify ] && { /etc/init.d/splify enabled 2>/dev/null || /etc/init.d/splify enable; }
  /etc/init.d/splify restart 2>/dev/null || true
}

# ──────────────────────────── 7. firewall zone ──────────────────────────────
setup_firewall() {
  if [ ! -x /usr/local/sbin/splify-firewall ]; then
    warn "splify-firewall не найден — создайте зону для $WARP_IFACE вручную (masq + lan→зона)."
    return 0
  fi
  say "Создаю firewall-зону для $WARP_IFACE…"
  if /usr/local/sbin/splify-firewall check "$WARP_IFACE" >/dev/null 2>&1; then
    say "Firewall-зона для $WARP_IFACE уже настроена."
  else
    /usr/local/sbin/splify-firewall fix "$WARP_IFACE" \
      || warn "splify-firewall fix не удался — проверьте зону для $WARP_IFACE в Сеть → Firewall."
  fi
}

 ──────────────────────────── main ──────────────────────────────────────────
install_splify
sleep 5
install_awg
sleep 5
register_warp
sleep 5
find_best_endpoint
sleep 5
create_warp_iface
sleep 5
register_in_splify
sleep 5
setup_firewall
sleep 5
/etc/init.d/splify restart; /etc/init.d/splify-agent restart
sleep 5
say "Готово! Настроен обфусцированный WARP-туннель $WARP_IFACE + splify routing."
printf '  • Туннель:   %s (AmneziaWG + WARP, endpoint %s)\n' "$WARP_IFACE" "$WARP_EP"
printf '  • Адрес:     %s%s\n' "$WARP_V4" "${WARP_V6:+, $WARP_V6}"
printf '  • Endpoint:  Сервисы → splify → Главная (нажмите «Включить», если ещё не включён)\n'
printf '  • Тюнинг:    Сервисы → splify → Дополнительно (режим, kill switch, списки)\n'
