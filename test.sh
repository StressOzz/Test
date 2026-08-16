#!/bin/sh
# ==========================================
# Splify2 Manager
# steer / steer-extended : https://github.com/xyzmean/steer
# splify2                : https://github.com/xyzmean/splify2
# AmneziaWG               : https://github.com/Slava-Shchipunov/awg-openwrt
# ==========================================

SPLIFY2_MANAGER_VERSION="1.1"

GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"

TMP="/tmp/splify2_manager"; mkdir -p "$TMP"
PACKAGES_UPDATED=0

REPO_STEER="xyzmean/steer"
REPO_UI="xyzmean/splify2"
REPO_AWG="Slava-Shchipunov/awg-openwrt"

WARP_IFACE="warp0"
TMP_SPL="/tmp/warp_reg"

AWG_JC=4; AWG_JMIN=40; AWG_JMAX=70; AWG_H1=1; AWG_H2=2; AWG_H3=3; AWG_H4=4; AWG_S1=0; AWG_S2=0
AWG_I1="<b 0xce000000010897a297ecc34cd6dd000044d0ec2e2e1ea2991f467ace4222129b5a098823784694b4897b9986ae0b7280135fa85e196d9ad980b150122129ce2a9379531b0fd3e871ca5fdb883c369832f730e272d7b8b74f393f9f0fa43f11e510ecb2219a52984410c204cf875585340c62238e14ad04dff382f2c200e0ee22fe743b9c6b8b043121c5710ec289f471c91ee414fca8b8be8419ae8ce7ffc53837f6ade262891895f3f4cecd31bc93ac5599e18e4f01b472362b8056c3172b513051f8322d1062997ef4a383b01706598d08d48c221d30e74c7ce000cdad36b706b1bf9b0607c32ec4b3203a4ee21ab64df336212b9758280803fcab14933b0e7ee1e04a7becce3e2633f4852585c567894a5f9efe9706a151b615856647e8b7dba69ab357b3982f554549bef9256111b2d67afde0b496f16962d4957ff654232aa9e845b61463908309cfd9de0a6abf5f425f577d7e5f6440652aa8da5f73588e82e9470f3b21b27b28c649506ae1a7f5f15b876f56abc4615f49911549b9bb39dd804fde182bd2dcec0c33bad9b138ca07d4a4a1650a2c2686acea05727e2a78962a840ae428f55627516e73c83dd8893b02358e81b524b4d99fda6df52b3a8d7a5291326e7ac9d773c5b43b8444554ef5aea104a738ed650aa979674bbed38da58ac29d87c29d387d80b526065baeb073ce65f075ccb56e47533aef357dceaa8293a523c5f6f790be90e4731123d3c6152a70576e90b4ab5bc5ead01576c68ab633ff7d36dcde2a0b2c68897e1acfc4d6483aaaeb635dd63c96b2b6a7a2bfe042f6aed82e5363aa850aace12ee3b1a93f30d8ab9537df483152a5527faca21efc9981b304f11fc95336f5b9637b174c5a0659e2b22e159a9fed4b8e93047371175b1d6d9cc8ab745f3b2281537d1c75fb9451871864efa5d184c38c185fd203de206751b92620f7c369e031d2041e152040920ac2c5ab5340bfc9d0561176abf10a147287ea90758575ac6a9f5ac9f390d0d5b23ee12af583383d994e22c0cf42383834bcd3ada1b3825a0664d8f3fb678261d57601ddf94a8a68a7c273a18c08aa99c7ad8c6c42eab67718843597ec9930457359dfdfbce024afc2dcf9348579a57d8d3490b2fa99f278f1c37d87dad9b221acd575192ffae1784f8e60ec7cee4068b6b988f0433d96d6a1b1865f4e155e9fe020279f434f3bf1bd117b717b92f6cd1cc9bea7d45978bcc3f24bda631a36910110a6ec06da35f8966c9279d130347594f13e9e07514fa370754d1424c0a1545c5070ef9fb2acd14233e8a50bfc5978b5bdf8bc1714731f798d21e2004117c61f2989dd44f0cf027b27d4019e81ed4b5c31db347c4a3a4d85048d7093cf16753d7b0d15e078f5c7a5205dc2f87e330a1f716738dce1c6180e9d02869b5546f1c4d2748f8c90d9693cba4e0079297d22fd61402dea32ff0eb69ebd65a5d0b687d87e3a8b2c42b648aa723c7c7daf37abcc4bb85caea2ee8f55bec20e913b3324ab8f5c3304f820d42ad1b9f2ffc1a3af9927136b4419e1e579ab4c2ae3c776d293d397d575df181e6cae0a4ada5d67ecea171cca3288d57c7bbdaee3befe745fb7d634f70386d873b90c4d6c6596bb65af68f9e5121e67ebf0d89d3c909ceedfb32ce9575a7758ff080724e1ab5d5f43074ecb53a479af21ed03d7b6899c36631c0166f9d47e5e1d4528a5d3d3f744029c4b1c190cbfbad06f5f83f7ad0429fa9a2719c56ffe3783460e166de2d8>"

D() { printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')"; }
X1="68747470733a2f2f7767636c692e76657263656c2e617070"
X2="68747470733a2f2f73616e74612d61746d6f2e72752f776172702f776172702e706870"
W1="$(D "$X1")"; II="$(D "$X2")"

PAUSE() { echo -ne "Нажмите Enter..."; read -r dummy; }

# ==============================
# Окружение
# ==============================
[ -f /etc/openwrt_release ] || { echo -e "${RED}Это не OpenWrt!${NC}"; exit 1; }

ARCH="$(grep DISTRIB_ARCH /etc/openwrt_release | cut -d"'" -f2)"
OWRTREL="$(grep '^DISTRIB_RELEASE=' /etc/openwrt_release | cut -d"'" -f2)"
ARCHAWG="${ARCH}_$(grep DISTRIB_TARGET /etc/openwrt_release | cut -d"'" -f2 | tr '/' '_')"

if ! command -v apk >/dev/null 2>&1; then
	echo -e "${RED}Этот скрипт требует OpenWrt 24.10+ с пакетным менеджером apk${NC}"
	exit 1
fi
INSTALL="apk add --allow-untrusted"
UPDATE="apk update"
DELETE="apk del"

if ! curl --version >/dev/null 2>&1; then
	clear; echo -e "curl ${RED}отсутствует${NC}"; echo -e "\n${MAGENTA}Устанавливаем ${NC}curl"
	$UPDATE >/dev/null 2>&1 && PACKAGES_UPDATED=1
	$INSTALL curl >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить curl!${NC}\n"; PAUSE; }
fi

update_packages() { [ "$PACKAGES_UPDATED" = "1" ] && return 0; echo -e "${CYAN}Обновляем список пакетов${NC}"; $UPDATE >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка обновления списка пакетов!${NC}\n"; return 1; }; PACKAGES_UPDATED=1; }

# get_ver: как в оригинальном Zapret Manager — без API, через редирект releases/latest
get_ver() { URL="$1"; OUT_FILE="$2"; NAME="$3"; RESULT=$(curl -sIL --connect-timeout 3 --max-time 5 --retry 1 -w "%{url_effective}" -o /dev/null "$URL" 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$RESULT" ]; then echo -e "$NAME: ${RED}ошибка получения версии${NC}"; return 1; fi
VERSION="${RESULT##*/}"; VERSION="${VERSION#v}"
if [ -z "$VERSION" ]; then echo -e "$NAME: ${RED}не удалось извлечь версию${NC}"; return 1; fi
echo "$VERSION" > "$OUT_FILE"; echo -e "$NAME: ${GREEN}$VERSION${NC}"; }

pkg_installed() { apk info -e "$1" >/dev/null 2>&1; }
local_pkg_ver() { apk info -v 2>/dev/null | grep -E "^${1}[0-9]" | sed -E "s/^${1}//; s/-r[0-9]+\$//"; }

# ==============================
# Собираем версии (один раз при старте, как в оригинале)
# ==============================
clear; echo -e "${CYAN}Собираем версии:${NC}"
TMP_VER_STEER="/tmp/steer_version"; TMP_VER_UI="/tmp/splify2_version"
get_ver "https://github.com/${REPO_STEER}/releases/latest" "$TMP_VER_STEER" "steer" &
get_ver "https://github.com/${REPO_UI}/releases/latest" "$TMP_VER_UI" "splify2" &
wait
LATEST_STEER=""; LATEST_UI=""
[ -s "$TMP_VER_STEER" ] && LATEST_STEER="$(cat "$TMP_VER_STEER")"
[ -s "$TMP_VER_UI" ] && LATEST_UI="$(cat "$TMP_VER_UI")"

# ==============================
# AmneziaWG
# ==============================
install_awg() {
	if pkg_installed amneziawg-tools && pkg_installed luci-proto-amneziawg && pkg_installed kmod-amneziawg; then
		echo -e "AmneziaWG ${GREEN}уже установлен${NC}"
		return 0
	fi

	echo -e "\n${MAGENTA}Устанавливаем AmneziaWG${NC}"
	update_packages || return 1

	BASE="https://github.com/${REPO_AWG}/releases/download/v${OWRTREL}"
	F_KMOD="kmod-amneziawg_v${OWRTREL}_${ARCHAWG}.apk"
	F_TOOLS="amneziawg-tools_v${OWRTREL}_${ARCHAWG}.apk"
	F_LUCI="luci-proto-amneziawg_v${OWRTREL}_${ARCHAWG}.apk"
	F_RU="luci-i18n-amneziawg-ru_v${OWRTREL}_${ARCHAWG}.apk"

	for F in "$F_KMOD" "$F_TOOLS" "$F_LUCI" "$F_RU"; do
		echo -e "${CYAN}Скачиваем ${NC}$F"
		curl -fL "$BASE/$F" -o "$TMP/$F" 2>/dev/null || { echo -e "\n${RED}Не удалось скачать:\n${NC}$BASE/$F\n"; PAUSE; return 1; }
	done

	echo -e "${CYAN}Устанавливаем ${NC}AmneziaWG"
	for F in "$F_KMOD" "$F_TOOLS" "$F_LUCI" "$F_RU"; do
		$INSTALL "$TMP/$F" >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить:\n${NC}$F\n"; PAUSE; return 1; }
	done
	rm -f "$TMP"/*.apk
	echo -e "AmneziaWG ${GREEN}установлен!${NC}"
}

# ==============================
# WARP: генерация + интерфейс + firewall
# ==============================
setup_warp() {
	FORCE="${1:-0}"

	if [ "$FORCE" != "1" ] && [ -n "$(uci -q get "network.$WARP_IFACE.private_key" 2>/dev/null)" ]; then
		echo -e "Интерфейс $WARP_IFACE ${GREEN}уже настроен${NC}, пропускаем генерацию"
		return 0
	fi

	echo -e "\n${MAGENTA}Генерируем WARP${NC}"
	mkdir -p "$TMP_SPL"
	REG="$TMP_SPL/reg.json"; rm -f "$REG"
	WARP_EP="engage.cloudflareclient.com:4500"
	PRIV=""; WARP_PEER=""; WARP_V4=""; WARP_V6=""

	echo -e "${CYAN}Используем основной метод${NC}"
	if curl -fsSL --max-time 30 "$II" -o "$REG" 2>/dev/null && grep -q '"public_key"' "$REG"; then
		PRIV=$(grep -o '"key"[[:space:]]*:[[:space:]]*"[^"]*"' "$REG" | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
		WARP_PEER=$(grep -o '"public_key"[[:space:]]*:[[:space:]]*"[^"]*"' "$REG" | head -n1 | sed 's/.*:[[:space:]]*"//;s/"$//')
		WARP_V4=$(grep -o '"v4"[[:space:]]*:[[:space:]]*"[^"]*"' "$REG" | sed -n '2p' | sed 's/.*:[[:space:]]*"//;s/"$//')
		WARP_V6=$(grep -o '"v6"[[:space:]]*:[[:space:]]*"[^"]*"' "$REG" | sed -n '2p' | sed 's/.*:[[:space:]]*"//;s/"$//')
	fi

	if [ -z "$PRIV" ] || [ -z "$WARP_PEER" ] || [ -z "$WARP_V4" ]; then
		echo -e "${YELLOW}Основной метод недоступен, переключаемся на запасной${NC}"
		NEED=""
		command -v jq >/dev/null 2>&1 || NEED="$NEED jq"
		command -v wg >/dev/null 2>&1 || NEED="$NEED wireguard-tools"
		if [ -n "$NEED" ]; then
			echo -e "${CYAN}Ставим зависимости${NC}"
			update_packages || return 1
			$INSTALL $NEED >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка установки зависимостей${NC}\n"; PAUSE; return 1; }
		fi

		if command -v awg >/dev/null 2>&1; then GEN=awg; else GEN=wg; fi
		PRIV="$("$GEN" genkey 2>/dev/null)"
		PUB="$(printf '%s\n' "$PRIV" | "$GEN" pubkey 2>/dev/null)"
		TOS="$(date -u +%Y-%m-%dT%H:%M:%S.000000000Z)"

		echo -e "${CYAN}Регистрируем устройство (резервный сервер)${NC}"
		curl -fsSL --max-time 30 -X POST "${W1%/}/api/reg" \
			-H "Content-Type: application/json" -H "Accept: application/json" \
			-d "{\"key\":\"$PUB\",\"install_id\":\"\",\"fcm_token\":\"\",\"model\":\"PC\",\"locale\":\"en_US\",\"tos\":\"$TOS\",\"type\":\"Android\"}" \
			-o "$REG" >/dev/null 2>&1

		if jq -e '.config.peers[0].public_key' "$REG" >/dev/null 2>&1; then
			WARP_PEER="$(jq -r '.config.peers[0].public_key' "$REG")"
			WARP_V4="$(jq -r '.config.interface.addresses.v4' "$REG")"
			WARP_V6="$(jq -r '.config.interface.addresses.v6 // empty' "$REG")"
		else
			if ! curl -fsSL --max-time 60 "$II" -o "$REG" >/dev/null 2>&1; then
				echo -e "\n${RED}Не удалось получить WARP${NC}\n"; PAUSE; return 1
			fi
			if ! jq -e '.result.config.peers[0].public_key' "$REG" >/dev/null 2>&1; then
				echo -e "\n${RED}Резервный источник вернул неверный формат${NC}\n"; PAUSE; return 1
			fi
			PRIV="$(jq -r '.result.key' "$REG")"
			WARP_PEER="$(jq -r '.result.config.peers[0].public_key' "$REG")"
			WARP_V4="$(jq -r '.result.config.interface.addresses.v4' "$REG")"
			WARP_V6="$(jq -r '.result.config.interface.addresses.v6 // empty' "$REG")"
		fi

		[ -n "$WARP_PEER" ] && [ "$WARP_PEER" != "null" ] || { echo -e "\n${RED}Нет peer public_key${NC}\n"; PAUSE; return 1; }
		[ -n "$WARP_V4" ] && [ "$WARP_V4" != "null" ] || { echo -e "\n${RED}Нет IPv4${NC}\n"; PAUSE; return 1; }
	fi
	echo -e "WARP ${GREEN}сгенерирован!${NC}"

	echo -e "\n${MAGENTA}Создаём интерфейс ${NC}$WARP_IFACE"
	[ -n "$(uci -q get "network.$WARP_IFACE")" ] && ifdown "$WARP_IFACE" >/dev/null 2>&1

	uci -q set "network.$WARP_IFACE=interface"
	uci set "network.$WARP_IFACE.proto=amneziawg"
	uci set "network.$WARP_IFACE.private_key=$PRIV"
	uci -q delete "network.$WARP_IFACE.addresses"
	uci add_list "network.$WARP_IFACE.addresses=$WARP_V4"
	[ -n "$WARP_V6" ] && uci add_list "network.$WARP_IFACE.addresses=$WARP_V6"
	uci -q delete "network.$WARP_IFACE.dns"
	uci add_list "network.$WARP_IFACE.dns=8.8.8.8"
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
	while [ -n "$(uci -q get "network.@${_pt}[0]")" ]; do uci -q delete "network.@${_pt}[0]"; done
	uci add network "$_pt" >/dev/null
	uci set "network.@${_pt}[-1].public_key=$WARP_PEER"
	uci -q delete "network.@${_pt}[-1].allowed_ips"
	uci add_list "network.@${_pt}[-1].allowed_ips=0.0.0.0/0"
	uci add_list "network.@${_pt}[-1].allowed_ips=::/0"
	uci set "network.@${_pt}[-1].endpoint_host=${WARP_EP%:*}"
	uci set "network.@${_pt}[-1].endpoint_port=${WARP_EP##*:}"
	uci set "network.@${_pt}[-1].persistent_keepalive=25"

	uci commit network >/dev/null 2>&1
	/etc/init.d/rpcd restart >/dev/null 2>&1
	/etc/init.d/uhttpd restart >/dev/null 2>&1
	rm -rf /tmp/luci-* >/dev/null 2>&1
	ip link del "$WARP_IFACE" >/dev/null 2>&1
	killall netifd >/dev/null 2>&1
	sleep 3
	ifup "$WARP_IFACE" >/dev/null 2>&1
	sleep 3
	echo -e "Интерфейс $WARP_IFACE ${GREEN}создан и поднят${NC}"

	printf '%s\n' \
		"[Interface]" \
		"PrivateKey = $PRIV" \
		"Address = $WARP_V4${WARP_V6:+, $WARP_V6}" \
		"DNS = 8.8.8.8, 8.8.4.4, 2001:4860:4860::8888, 2001:4860:4860::8844" \
		"MTU = 1280" \
		"S1 = $AWG_S1" "S2 = $AWG_S2" "Jc = $AWG_JC" "Jmin = $AWG_JMIN" "Jmax = $AWG_JMAX" \
		"H1 = $AWG_H1" "H2 = $AWG_H2" "H3 = $AWG_H3" "H4 = $AWG_H4" "I1 = $AWG_I1" "" \
		"[Peer]" \
		"PublicKey = $WARP_PEER" \
		"AllowedIPs = 0.0.0.0/0, ::/0" \
		"Endpoint = $WARP_EP" \
		"PersistentKeepalive = 25" > /root/WARP.conf
	echo -e "Файл сохранён в ${NC}/root/WARP.conf"

	echo -e "\n${MAGENTA}Настраиваем firewall${NC}"
	if ! uci show firewall | grep -q "\.name='$WARP_IFACE'"; then
		uci add firewall zone >/dev/null
		uci set firewall.@zone[-1].name="$WARP_IFACE"
		uci set firewall.@zone[-1].input='REJECT'
		uci set firewall.@zone[-1].output='ACCEPT'
		uci set firewall.@zone[-1].forward='REJECT'
		uci set firewall.@zone[-1].masq='1'
		uci set firewall.@zone[-1].mtu_fix='1'
		uci add_list firewall.@zone[-1].network="$WARP_IFACE"
	fi

	_has_fwd=0; _fi=0
	while [ -n "$(uci -q get "firewall.@forwarding[$_fi]")" ]; do
		if [ "$(uci -q get "firewall.@forwarding[$_fi].src")" = "lan" ] && [ "$(uci -q get "firewall.@forwarding[$_fi].dest")" = "$WARP_IFACE" ]; then _has_fwd=1; break; fi
		_fi=$((_fi + 1))
	done
	if [ "$_has_fwd" = "0" ]; then
		uci add firewall forwarding >/dev/null
		uci set firewall.@forwarding[-1].src='lan'
		uci set firewall.@forwarding[-1].dest="$WARP_IFACE"
	fi

	uci commit firewall >/dev/null 2>&1
	/etc/init.d/firewall restart >/dev/null 2>&1
	echo -e "Firewall ${GREEN}настроен!${NC}"

	# ВАЖНО: сети нужно время подняться после перезапуска firewall/netifd,
	# иначе следующие шаги (скачивание пакетов) могут оборваться
	echo -e "\n${YELLOW}Ждём поднятия сети после перенастройки firewall...${NC}"
	sleep 5
	PAUSE
}

regen_warp() {
	clear
	echo -e "${MAGENTA}Перегенерация WARP${NC}\n"
	if ! pkg_installed amneziawg-tools; then
		echo -e "${RED}AmneziaWG не установлен, сначала выполните установку (пункт 1)${NC}\n"
		PAUSE; return 1
	fi
	setup_warp 1
}

show_warp_info() {
	clear
	echo -e "${MAGENTA}WARP.conf${NC}\n"
	if [ -f /root/WARP.conf ]; then cat /root/WARP.conf; else echo -e "${RED}Файл /root/WARP.conf не найден${NC}"; fi
	echo; PAUSE
}

# ==============================
# steer
# ==============================
install_steer_engine() {
	LOCAL_EXT="$(local_pkg_ver "steer-extended-")"
	LOCAL_BASE="$(local_pkg_ver "steer-")"

	if [ -z "$LATEST_STEER" ]; then echo -e "${RED}Не удалось получить версию steer${NC}"; return 1; fi

	if [ "$LOCAL_EXT" = "$LATEST_STEER" ]; then
		echo -e "steer-extended ${GREEN}уже последней версии ($LOCAL_EXT)${NC}"
		return 0
	fi

	if [ -n "$LOCAL_EXT" ]; then
		echo -e "${YELLOW}Обновляем steer-extended: $LOCAL_EXT → $LATEST_STEER${NC}"
	elif [ -n "$LOCAL_BASE" ]; then
		echo -e "${YELLOW}Найден базовый steer $LOCAL_BASE, заменяем на steer-extended${NC}"
		$DELETE steer >/dev/null 2>&1
	else
		echo -e "\n${MAGENTA}Устанавливаем steer-extended${NC}"
	fi

	FILE="steer-extended-${LATEST_STEER}-1_${ARCH}.apk"
	URL="https://github.com/${REPO_STEER}/releases/download/v${LATEST_STEER}/${FILE}"
	echo -e "${CYAN}Скачиваем ${NC}$FILE"
	curl -fL "$URL" -o "$TMP/$FILE" || { echo -e "\n${RED}Не удалось скачать:\n${NC}$URL\n"; PAUSE; return 1; }

	echo -e "${CYAN}Устанавливаем ${NC}steer-extended"
	$INSTALL "$TMP/$FILE" >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить steer-extended${NC}\n"; rm -f "$TMP/$FILE"; PAUSE; return 1; }
	rm -f "$TMP/$FILE"

	/etc/init.d/rpcd restart >/dev/null 2>&1
	[ -x /etc/init.d/steer ] && /etc/init.d/steer enable >/dev/null 2>&1
	echo -e "steer-extended $LATEST_STEER ${GREEN}установлен!${NC}"
}

# ==============================
# splify2 (UI)
# ==============================
install_splify2_ui() {
	LOCAL_VER="$(local_pkg_ver "luci-app-splify2-")"

	if [ -z "$LATEST_UI" ]; then echo -e "${RED}Не удалось получить версию splify2${NC}"; return 1; fi

	if [ "$LOCAL_VER" = "$LATEST_UI" ] && [ -n "$LOCAL_VER" ]; then
		echo -e "splify2 ${GREEN}уже последней версии ($LOCAL_VER)${NC}"
		return 0
	fi

	if [ -n "$LOCAL_VER" ]; then
		echo -e "${YELLOW}Обновляем splify2: $LOCAL_VER → $LATEST_UI${NC}"
	else
		echo -e "\n${MAGENTA}Устанавливаем splify2${NC}"
	fi

	FILE="luci-app-splify2-${LATEST_UI}-1_noarch.apk"
	URL="https://github.com/${REPO_UI}/releases/download/v${LATEST_UI}/${FILE}"
	echo -e "${CYAN}Скачиваем ${NC}$FILE"
	curl -fL "$URL" -o "$TMP/$FILE" || { echo -e "\n${RED}Не удалось скачать:\n${NC}$URL\n"; PAUSE; return 1; }

	echo -e "${CYAN}Устанавливаем ${NC}splify2"
	$INSTALL "$TMP/$FILE" >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить splify2${NC}\n"; rm -f "$TMP/$FILE"; PAUSE; return 1; }
	rm -f "$TMP/$FILE"

	/etc/init.d/rpcd restart >/dev/null 2>&1
	echo -e "splify2 $LATEST_UI ${GREEN}установлен!${NC}"
}

# ==============================
# spec.json
# ==============================
integrate_steer_spec() {
	echo -e "\n${MAGENTA}Записываем /etc/steer/spec.json${NC}"
	mkdir -p /etc/steer

	cat > /etc/steer/spec.json <<'EOF'
{"schema":1,"outputs":{"warp0":{"name":"warp0","kind":"interface","devices":["warp0"],"on_fail":"direct"}},"channels":[{"name":"правило1","match":{"prefixes_files":["/etc/steer/lists/telegram.lst","/etc/steer/lists/whatsapp.lst","/etc/steer/lists/meta.lst","/etc/steer/lists/discord.lst","/etc/steer/lists/twitter_x.lst","/etc/steer/lists/google.lst","/etc/steer/lists/rkn.lst"],"domains_files":["/etc/steer/lists/domains/svc_telegram.lst","/etc/steer/lists/domains/svc_meta.lst","/etc/steer/lists/domains/svc_discord.lst","/etc/steer/lists/domains/svc_twitter.lst","/etc/steer/lists/domains/svc_google_meet.lst","/etc/steer/lists/domains/svc_google_play.lst","/etc/steer/lists/domains/geoblock.lst","/etc/steer/lists/domains/block.lst"],"mode":"fakeip"},"out":"warp0"}]}
EOF

	echo -e "${CYAN}Перезапускаем службы${NC}"
	command -v steer >/dev/null 2>&1 && steer apply >/dev/null 2>&1
	/etc/init.d/steer restart >/dev/null 2>&1
	/etc/init.d/rpcd restart >/dev/null 2>&1
	echo -e "spec.json ${GREEN}применён и службы перезапущены!${NC}"
}

# ==============================
# Полная установка
# ==============================
install_all() {
	clear
	echo -e "${MAGENTA}Установка splify2${NC}\n"
	install_awg           || { PAUSE; return 1; }
	setup_warp             || { PAUSE; return 1; }
	install_steer_engine  || { PAUSE; return 1; }
	install_splify2_ui    || { PAUSE; return 1; }
	integrate_steer_spec

	echo -e "\nВсё ${GREEN}установлено!${NC}"
	echo -e "${YELLOW}Тоннель:${NC} $WARP_IFACE"
	echo -e "${YELLOW}Проверьте:${NC} LuCI → Сервисы → splify2\n"
	PAUSE
}

# ==============================
# Удаление
# ==============================
uninstall_all() {
	clear
	echo -e "${MAGENTA}Удаление splify2${NC}\n"

	if ! pkg_installed luci-app-splify2 && ! pkg_installed steer && ! pkg_installed steer-extended; then
		echo -e "${YELLOW}splify2 не установлен${NC}\n"; PAUSE; return 0
	fi

	echo -e "${CYAN}Останавливаем службы${NC}"
	[ -x /etc/init.d/steer ] && /etc/init.d/steer stop >/dev/null 2>&1

	echo -e "${CYAN}Удаляем пакеты${NC}"
	$DELETE luci-app-splify2 >/dev/null 2>&1
	$DELETE steer-extended >/dev/null 2>&1
	$DELETE steer >/dev/null 2>&1

	echo -e "${CYAN}Удаляем конфигурацию${NC}"
	rm -rf /etc/steer /etc/splify2 /var/lib/steer /var/lib/splify2
	uci -q delete splify2 2>/dev/null && uci commit splify2 2>/dev/null

	/etc/init.d/rpcd restart >/dev/null 2>&1
	echo -e "splify2 ${GREEN}удалён!${NC}"

	echo -ne "\n${YELLOW}Также удалить интерфейс $WARP_IFACE, AmneziaWG и /root/WARP.conf? (${NC}y/N${YELLOW}): ${NC}"
	read -r ans
	case "$ans" in
		y|Y)
			echo -e "\n${CYAN}Удаляем интерфейс $WARP_IFACE${NC}"
			ifdown "$WARP_IFACE" >/dev/null 2>&1
			uci -q delete "network.$WARP_IFACE"
			_pt="amneziawg_$WARP_IFACE"
			while [ -n "$(uci -q get "network.@${_pt}[0]")" ]; do uci -q delete "network.@${_pt}[0]"; done
			uci commit network >/dev/null 2>&1

			_zi=0
			while [ -n "$(uci -q get "firewall.@zone[$_zi]")" ]; do
				if [ "$(uci -q get "firewall.@zone[$_zi].name")" = "$WARP_IFACE" ]; then uci -q delete "firewall.@zone[$_zi]"; else _zi=$((_zi + 1)); fi
			done
			_fi=0
			while [ -n "$(uci -q get "firewall.@forwarding[$_fi]")" ]; do
				if [ "$(uci -q get "firewall.@forwarding[$_fi].dest")" = "$WARP_IFACE" ]; then uci -q delete "firewall.@forwarding[$_fi]"; else _fi=$((_fi + 1)); fi
			done
			uci commit firewall >/dev/null 2>&1
			/etc/init.d/network restart >/dev/null 2>&1
			/etc/init.d/firewall restart >/dev/null 2>&1
			sleep 5

			echo -e "${CYAN}Удаляем пакеты AmneziaWG${NC}"
			$DELETE luci-proto-amneziawg >/dev/null 2>&1
			$DELETE luci-i18n-amneziawg-ru >/dev/null 2>&1
			$DELETE amneziawg-tools >/dev/null 2>&1
			$DELETE kmod-amneziawg >/dev/null 2>&1

			rm -f /root/WARP.conf
			echo -e "WARP и AmneziaWG ${GREEN}удалены!${NC}"
			;;
		*) echo -e "\n${YELLOW}WARP / AmneziaWG оставлены без изменений${NC}" ;;
	esac
	echo; PAUSE
}

# ==============================
# Главное меню
# ==============================
show_menu() {
	clear
	echo -e "╔══════════════════════════════╗\n║  ${BLUE}Splify2 Manager${NC}              ║\n╚══════════════════════════════╝\n"

	LOCAL_EXT="$(local_pkg_ver "steer-extended-")"
	LOCAL_UI="$(local_pkg_ver "luci-app-splify2-")"
	AWG_OK=0; pkg_installed amneziawg-tools && pkg_installed kmod-amneziawg && AWG_OK=1
	WARP_OK=0; [ -n "$(uci -q get "network.$WARP_IFACE.private_key" 2>/dev/null)" ] && WARP_OK=1

	# --- статус ---
	if [ -n "$LOCAL_EXT" ]; then
		if [ "$LOCAL_EXT" = "$LATEST_STEER" ]; then echo -e "${YELLOW}steer:${NC}     ${GREEN}$LOCAL_EXT${NC}"
		else echo -e "${YELLOW}steer:${NC}     ${RED}$LOCAL_EXT (версия устарела)${NC}"; fi
	else
		echo -e "${YELLOW}steer:${NC}     ${RED}не установлен${NC}"
	fi
	if [ -n "$LOCAL_UI" ]; then
		if [ "$LOCAL_UI" = "$LATEST_UI" ]; then echo -e "${YELLOW}splify2:${NC}   ${GREEN}$LOCAL_UI${NC}"
		else echo -e "${YELLOW}splify2:${NC}   ${RED}$LOCAL_UI (версия устарела)${NC}"; fi
	else
		echo -e "${YELLOW}splify2:${NC}   ${RED}не установлен${NC}"
	fi
	[ "$AWG_OK" = "1" ] && echo -e "${YELLOW}AmneziaWG:${NC} ${GREEN}установлен${NC}" || echo -e "${YELLOW}AmneziaWG:${NC} ${RED}не установлен${NC}"
	[ "$WARP_OK" = "1" ] && echo -e "${YELLOW}$WARP_IFACE:${NC}      ${GREEN}настроен${NC}" || echo -e "${YELLOW}$WARP_IFACE:${NC}      ${RED}не настроен${NC}"

	# --- активный пункт 1 (как Z_ACTION_TEXT в оригинале) ---
	if [ -z "$LOCAL_EXT" ] && [ -z "$LOCAL_UI" ] && [ "$AWG_OK" = "0" ]; then
		ACTION_TEXT="Установить"
	elif { [ -n "$LATEST_STEER" ] && [ "$LOCAL_EXT" != "$LATEST_STEER" ]; } || { [ -n "$LATEST_UI" ] && [ "$LOCAL_UI" != "$LATEST_UI" ]; } || [ "$AWG_OK" = "0" ] || [ "$WARP_OK" = "0" ]; then
		ACTION_TEXT="Обновить / доустановить"
	else
		ACTION_TEXT="Переустановить"
	fi

	echo -e "\n${CYAN}1) ${GREEN}$ACTION_TEXT${NC} splify2"
	echo -e "${CYAN}2) ${GREEN}Удалить${NC} splify2"
	echo -e "${CYAN}3) ${GREEN}WARP.conf${NC}"
	echo -e "${CYAN}4) ${GREEN}Перегенерировать${NC} WARP"
	echo -ne "${CYAN}Enter) ${GREEN}Выход${NC}\n\n${YELLOW}Выберите пункт:${NC} "
	read -r choice
	case "$choice" in
		1) install_all ;;
		2) uninstall_all ;;
		3) show_warp_info ;;
		4) regen_warp ;;
		*) echo; exit 0 ;;
	esac
}

while true; do show_menu; done
