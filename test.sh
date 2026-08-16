#!/bin/sh
# ==========================================
# Splify2 Manager
# Установка/обновление/удаление:
#   steer / steer-extended  — https://github.com/xyzmean/steer
#   splify2 (LuCI UI)       — https://github.com/xyzmean/splify2
#   AmneziaWG               — https://github.com/Slava-Shchipunov/awg-openwrt
#   WARP (warp0)            — генерация ключей Cloudflare WARP + интерфейс
#
# Требования: OpenWrt 24.10+ (пакетный менеджер apk)
# ==========================================

SPLIFY2_MANAGER_VERSION="1.0"

# ==============================
# Цвета
# ==============================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
MAGENTA='\033[1;35m'
BLUE='\033[0;34m'
NC='\033[0m'

# ==============================
# Базовые переменные
# ==============================
TMP="/tmp/splify2_manager"
mkdir -p "$TMP"

API="https://api.github.com/repos"
REPO_STEER="xyzmean/steer"
REPO_UI="xyzmean/splify2"
REPO_AWG="Slava-Shchipunov/awg-openwrt"

WARP_IFACE="warp0"
TMP_WARP="/tmp/warp_reg"
PACKAGES_UPDATED=0

# WARP / AmneziaWG obfuscation-параметры (совместимы с большинством конфигов WARP+AWG)
AWG_JC=4; AWG_JMIN=40; AWG_JMAX=70; AWG_H1=1; AWG_H2=2; AWG_H3=3; AWG_H4=4; AWG_S1=0; AWG_S2=0
AWG_I1="<b 0xce000000010897a297ecc34cd6dd000044d0ec2e2e1ea2991f467ace4222129b5a098823784694b4897b9986ae0b7280135fa85e196d9ad980b150122129ce2a9379531b0fd3e871ca5fdb883c369832f730e272d7b8b74f393f9f0fa43f11e510ecb2219a52984410c204cf875585340c62238e14ad04dff382f2c200e0ee22fe743b9c6b8b043121c5710ec289f471c91ee414fca8b8be8419ae8ce7ffc53837f6ade262891895f3f4cecd31bc93ac5599e18e4f01b472362b8056c3172b513051f8322d1062997ef4a383b01706598d08d48c221d30e74c7ce000cdad36b706b1bf9b0607c32ec4b3203a4ee21ab64df336212b9758280803fcab14933b0e7ee1e04a7becce3e2633f4852585c567894a5f9efe9706a151b615856647e8b7dba69ab357b3982f554549bef9256111b2d67afde0b496f16962d4957ff654232aa9e845b61463908309cfd9de0a6abf5f425f577d7e5f6440652aa8da5f73588e82e9470f3b21b27b28c649506ae1a7f5f15b876f56abc4615f49911549b9bb39dd804fde182bd2dcec0c33bad9b138ca07d4a4a1650a2c2686acea05727e2a78962a840ae428f55627516e73c83dd8893b02358e81b524b4d99fda6df52b3a8d7a5291326e7ac9d773c5b43b8444554ef5aea104a738ed650aa979674bbed38da58ac29d87c29d387d80b526065baeb073ce65f075ccb56e47533aef357dceaa8293a523c5f6f790be90e4731123d3c6152a70576e90b4ab5bc5ead01576c68ab633ff7d36dcde2a0b2c68897e1acfc4d6483aaaeb635dd63c96b2b6a7a2bfe042f6aed82e5363aa850aace12ee3b1a93f30d8ab9537df483152a5527faca21efc9981b304f11fc95336f5b9637b174c5a0659e2b22e159a9fed4b8e93047371175b1d6d9cc8ab745f3b2281537d1c75fb9451871864efa5d184c38c185fd203de206751b92620f7c369e031d2041e152040920ac2c5ab5340bfc9d0561176abf10a147287ea90758575ac6a9f5ac9f390d0d5b23ee12af583383d994e22c0cf42383834bcd3ada1b3825a0664d8f3fb678261d57601ddf94a8a68a7c273a18c08aa99c7ad8c6c42eab67718843597ec9930457359dfdfbce024afc2dcf9348579a57d8d3490b2fa99f278f1c37d87dad9b221acd575192ffae1784f8e60ec7cee4068b6b988f0433d96d6a1b1865f4e155e9fe020279f434f3bf1bd117b717b92f6cd1cc9bea7d45978bcc3f24bda631a36910110a6ec06da35f8966c9279d130347594f13e9e07514fa370754d1424c0a1545c5070ef9fb2acd14233e8a50bfc5978b5bdf8bc1714731f798d21e2004117c61f2989dd44f0cf027b27d4019e81ed4b5c31db347c4a3a4d85048d7093cf16753d7b0d15e078f5c7a5205dc2f87e330a1f716738dce1c6180e9d02869b5546f1c4d2748f8c90d9693cba4e0079297d22fd61402dea32ff0eb69ebd65a5d0b687d87e3a8b2c42b648aa723c7c7daf37abcc4bb85caea2ee8f55bec20e913b3324ab8f5c3304f820d42ad1b9f2ffc1a3af9927136b4419e1e579ab4c2ae3c776d293d397d575df181e6cae0a4ada5d67ecea171cca3288d57c7bbdaee3befe745fb7d634f70386d873b90c4d6c6596bb65af68f9e5121e67ebf0d89d3c909ceedfb32ce9575a7758ff080724e1ab5d5f43074ecb53a479af21ed03d7b6899c36631c0166f9d47e5e1d4528a5d3d3f744029c4b1c190cbfbad06f5f83f7ad0429fa9a2719c56ffe3783460e166de2d8>"

# декодер hex-URL
D() { printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')"; }
X1="68747470733a2f2f7767636c692e76657263656c2e617070"
X2="68747470733a2f2f73616e74612d61746d6f2e72752f776172702f776172702e706870"
W1="$(D "$X1")"
II="$(D "$X2")"

PAUSE() { echo -ne "Нажмите Enter..."; read -r dummy; }

# ==============================
# Окружение OpenWrt
# ==============================
[ -f /etc/openwrt_release ] || { echo -e "${RED}✗ /etc/openwrt_release не найден. Это не OpenWrt?${NC}"; exit 1; }
. /etc/openwrt_release

ARCH="$DISTRIB_ARCH"
OWRTREL="$DISTRIB_RELEASE"
ARCHAWG="${DISTRIB_ARCH}_$(printf '%s' "$DISTRIB_TARGET" | tr '/' '_')"

case "$ARCH" in
	aarch64_cortex-a53|aarch64_generic|arm_cortex-a7_neon-vfpv4|mipsel_24kc|mips_24kc|x86_64) ;;
	*) echo -e "${YELLOW}⚠ Архитектура $ARCH не входит в список часто собираемых — сборка для неё может ещё не выйти${NC}" ;;
esac

if ! command -v apk >/dev/null 2>&1; then
	echo -e "${RED}✗ Этот скрипт требует OpenWrt 24.10+ с пакетным менеджером apk${NC}"
	echo -e "${YELLOW}На opkg-системах (23.05 и старее) splify2 не поддерживается${NC}"
	exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
	echo -e "${CYAN}Устанавливаем curl${NC}"
	apk update >/dev/null 2>&1
	apk add curl >/dev/null 2>&1
fi

# ==============================
# Вспомогательные функции
# ==============================
update_packages() {
	[ "$PACKAGES_UPDATED" = "1" ] && return 0
	echo -e "${CYAN}Обновляем список пакетов${NC}"
	apk update >/dev/null 2>&1 || { echo -e "${RED}✗ Ошибка обновления списка пакетов${NC}"; return 1; }
	PACKAGES_UPDATED=1
}

get_latest_tag() {
	# $1 = owner/repo, выводит версию без ведущей "v"
	wget -qO- "$API/$1/releases/latest" 2>/dev/null | sed -n 's/.*"tag_name": *"v\{0,1\}\([^"]*\)".*/\1/p' | head -1
}

local_pkg_ver() {
	# $1 = точный префикс пакета (например "steer-extended-")
	apk info -v 2>/dev/null | grep -E "^${1}[0-9]" | sed -E "s/^${1}//; s/-r[0-9]+\$//"
}

pkg_installed() { apk info -e "$1" >/dev/null 2>&1; }

# ==============================
# 1. AmneziaWG
# ==============================
install_awg() {
	echo -e "\n${MAGENTA}━━━ AmneziaWG ━━━${NC}"

	if pkg_installed amneziawg-tools && pkg_installed luci-proto-amneziawg && pkg_installed kmod-amneziawg; then
		echo -e "${GREEN}✓ AmneziaWG уже установлен${NC}"
		return 0
	fi

	echo -e "${CYAN}Устанавливаем пакеты AmneziaWG для OpenWrt ${NC}$OWRTREL${CYAN} / ${NC}$ARCHAWG"
	update_packages || return 1

	BASE="https://github.com/${REPO_AWG}/releases/download/v${OWRTREL}"
	F_KMOD="kmod-amneziawg_v${OWRTREL}_${ARCHAWG}.apk"
	F_TOOLS="amneziawg-tools_v${OWRTREL}_${ARCHAWG}.apk"
	F_LUCI="luci-proto-amneziawg_v${OWRTREL}_${ARCHAWG}.apk"
	F_RU="luci-i18n-amneziawg-ru_v${OWRTREL}_${ARCHAWG}.apk"

	for F in "$F_KMOD" "$F_TOOLS" "$F_LUCI" "$F_RU"; do
		echo -e "${CYAN}Скачиваем ${NC}$F"
		curl -fL "$BASE/$F" -o "$TMP/$F" 2>/dev/null || {
			echo -e "${RED}✗ Не удалось скачать $F${NC}"
			echo -e "${YELLOW}Проверьте, есть ли сборка для вашей версии OpenWrt на:${NC}"
			echo -e "${CYAN}https://github.com/${REPO_AWG}/releases${NC}"
			return 1
		}
	done

	echo -e "${CYAN}Устанавливаем ${NC}AmneziaWG"
	for F in "$F_KMOD" "$F_TOOLS" "$F_LUCI" "$F_RU"; do
		apk add --allow-untrusted "$TMP/$F" >/dev/null 2>&1 || { echo -e "${RED}✗ Не удалось установить $F${NC}"; return 1; }
	done
	rm -f "$TMP"/*.apk

	echo -e "${GREEN}✓ AmneziaWG установлен${NC}"
}

# ==============================
# 2. WARP: генерация + интерфейс warp0 + firewall
# ==============================
setup_warp() {
	FORCE="${1:-0}"
	echo -e "\n${MAGENTA}━━━ WARP ($WARP_IFACE) ━━━${NC}"

	if [ "$FORCE" != "1" ] && [ -n "$(uci -q get "network.$WARP_IFACE.private_key" 2>/dev/null)" ]; then
		echo -e "${GREEN}✓ Интерфейс $WARP_IFACE уже настроен, пропускаем генерацию${NC}"
		echo -e "${YELLOW}(для пересоздания используйте пункт меню «Перегенерировать WARP»)${NC}"
		return 0
	fi

	mkdir -p "$TMP_WARP"
	REG="$TMP_WARP/reg.json"
	rm -f "$REG"
	WARP_EP="engage.cloudflareclient.com:4500"

	echo -e "${CYAN}Регистрируем устройство в Cloudflare WARP${NC}"
	echo -e "${CYAN}Используем основной метод${NC}"

	PRIV=""; WARP_PEER=""; WARP_V4=""; WARP_V6=""

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
			apk add $NEED >/dev/null 2>&1 || { echo -e "${RED}✗ Ошибка установки зависимостей${NC}"; return 1; }
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

		if ! jq -e '.config.peers[0].public_key' "$REG" >/dev/null 2>&1; then
			if ! curl -fsSL --max-time 60 "$II" -o "$REG" >/dev/null 2>&1; then
				echo -e "${RED}✗ Не удалось получить WARP${NC}"; return 1
			fi
			if jq -e '.result.config.peers[0].public_key' "$REG" >/dev/null 2>&1; then
				PRIV="$(jq -r '.result.key' "$REG")"
				WARP_PEER="$(jq -r '.result.config.peers[0].public_key' "$REG")"
				WARP_V4="$(jq -r '.result.config.interface.addresses.v4' "$REG")"
				WARP_V6="$(jq -r '.result.config.interface.addresses.v6 // empty' "$REG")"
			fi
		else
			WARP_PEER="$(jq -r '.config.peers[0].public_key' "$REG")"
			WARP_V4="$(jq -r '.config.interface.addresses.v4' "$REG")"
			WARP_V6="$(jq -r '.config.interface.addresses.v6 // empty' "$REG")"
		fi

		[ -n "$WARP_PEER" ] && [ "$WARP_PEER" != "null" ] || { echo -e "${RED}✗ Нет peer public_key${NC}"; return 1; }
		[ -n "$WARP_V4" ] && [ "$WARP_V4" != "null" ] || { echo -e "${RED}✗ Нет IPv4${NC}"; return 1; }
	fi
	echo -e "${GREEN}✓ WARP сгенерирован${NC}"

	# ---- интерфейс warp0 ----
	echo -e "${CYAN}Создаём интерфейс ${NC}$WARP_IFACE"
	if [ -n "$(uci -q get "network.$WARP_IFACE")" ]; then
		ifdown "$WARP_IFACE" >/dev/null 2>&1
	fi

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
	echo -e "${GREEN}✓ Интерфейс $WARP_IFACE создан и поднят${NC}"

	# ---- WARP.conf в /root ----
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
	echo -e "${YELLOW}Файл сохранён в${NC} /root/WARP.conf"

	# ---- firewall-зона для warp0 ----
	echo -e "${CYAN}Настраиваем firewall${NC}"
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
		if [ "$(uci -q get "firewall.@forwarding[$_fi].src")" = "lan" ] && [ "$(uci -q get "firewall.@forwarding[$_fi].dest")" = "$WARP_IFACE" ]; then
			_has_fwd=1; break
		fi
		_fi=$((_fi + 1))
	done
	if [ "$_has_fwd" = "0" ]; then
		uci add firewall forwarding >/dev/null
		uci set firewall.@forwarding[-1].src='lan'
		uci set firewall.@forwarding[-1].dest="$WARP_IFACE"
	fi

	uci commit firewall >/dev/null 2>&1
	/etc/init.d/firewall restart >/dev/null 2>&1
	echo -e "${GREEN}✓ Firewall настроен${NC}"
}

regen_warp() {
	clear
	echo -e "${MAGENTA}━━━ Перегенерация WARP ━━━${NC}"
	if ! pkg_installed amneziawg-tools; then
		echo -e "\n${RED}✗ AmneziaWG не установлен, сначала выполните установку splify2 (пункт 1)${NC}\n"
		PAUSE; return 1
	fi
	setup_warp 1
	echo; PAUSE
}

show_warp_info() {
	clear
	echo -e "${MAGENTA}━━━ WARP.conf ━━━${NC}\n"
	if [ -f /root/WARP.conf ]; then
		cat /root/WARP.conf
	else
		echo -e "${RED}Файл /root/WARP.conf не найден${NC}"
	fi
	echo; PAUSE
}

# ==============================
# 3. Steer (движок)
# ==============================
install_steer_engine() {
	echo -e "\n${MAGENTA}━━━ Steer (движок маршрутизации) ━━━${NC}"

	echo -e "${CYAN}Получаем последнюю версию steer...${NC}"
	LATEST="$(get_latest_tag "$REPO_STEER")"
	[ -n "$LATEST" ] || { echo -e "${RED}✗ Не удалось получить версию steer (нет сети или релизов?)${NC}"; return 1; }

	LOCAL_EXT="$(local_pkg_ver "steer-extended-")"
	LOCAL_BASE="$(local_pkg_ver "steer-")"

	if [ -n "$LOCAL_EXT" ]; then
		if [ "$LOCAL_EXT" = "$LATEST" ]; then
			echo -e "${GREEN}✓ steer-extended уже последней версии ($LOCAL_EXT)${NC}"
			return 0
		fi
		echo -e "${YELLOW}steer-extended устарел: $LOCAL_EXT → $LATEST${NC}"
	elif [ -n "$LOCAL_BASE" ]; then
		echo -e "${YELLOW}Найден базовый steer $LOCAL_BASE — заменяем на steer-extended (нужен для VLESS/Reality)${NC}"
		apk del steer >/dev/null 2>&1
	else
		echo -e "${CYAN}steer не установлен — устанавливаем steer-extended${NC}"
	fi

	FILE="steer-extended-${LATEST}-1_${ARCH}.apk"
	URL="https://github.com/${REPO_STEER}/releases/download/v${LATEST}/${FILE}"

	echo -e "${YELLOW}Версия:${NC}       ${GREEN}$LATEST${NC}"
	echo -e "${YELLOW}Архитектура:${NC}  ${GREEN}$ARCH${NC}"
	echo -e "${YELLOW}Файл:${NC}         ${CYAN}$FILE${NC}"
	echo -e "${CYAN}Скачиваем...${NC}"

	if ! curl -fL "$URL" -o "$TMP/$FILE"; then
		echo -e "${RED}✗ Ошибка скачивания steer-extended${NC}"
		echo -e "${YELLOW}Возможно, сборка для $ARCH ещё не опубликована:${NC} https://github.com/${REPO_STEER}/releases"
		rm -f "$TMP/$FILE"
		return 1
	fi

	echo -e "${CYAN}Устанавливаем...${NC}"
	if ! apk add --allow-untrusted "$TMP/$FILE" >/dev/null 2>&1; then
		echo -e "${RED}✗ Ошибка установки steer-extended${NC}"
		rm -f "$TMP/$FILE"
		return 1
	fi
	rm -f "$TMP/$FILE"

	/etc/init.d/rpcd restart >/dev/null 2>&1
	[ -x /etc/init.d/steer ] && /etc/init.d/steer enable >/dev/null 2>&1

	echo -e "${GREEN}✓ steer-extended $LATEST установлен${NC}"
}

# ==============================
# 4. Splify2 (интерфейс LuCI)
# ==============================
install_splify2_ui() {
	echo -e "\n${MAGENTA}━━━ Splify2 (интерфейс) ━━━${NC}"

	echo -e "${CYAN}Получаем последнюю версию splify2...${NC}"
	LATEST="$(get_latest_tag "$REPO_UI")"
	[ -n "$LATEST" ] || { echo -e "${RED}✗ Не удалось получить версию splify2${NC}"; return 1; }

	LOCAL_VER="$(local_pkg_ver "luci-app-splify2-")"

	if [ "$LOCAL_VER" = "$LATEST" ] && [ -n "$LOCAL_VER" ]; then
		echo -e "${GREEN}✓ splify2 уже последней версии ($LOCAL_VER)${NC}"
		return 0
	fi
	if [ -n "$LOCAL_VER" ]; then
		echo -e "${YELLOW}Обновляем splify2: $LOCAL_VER → $LATEST${NC}"
	else
		echo -e "${CYAN}splify2 не установлен — устанавливаем${NC}"
	fi

	FILE="luci-app-splify2-${LATEST}-1_noarch.apk"
	URL="https://github.com/${REPO_UI}/releases/download/v${LATEST}/${FILE}"

	echo -e "${YELLOW}Версия:${NC}  ${GREEN}$LATEST${NC}"
	echo -e "${CYAN}Скачиваем...${NC}"

	if ! curl -fL "$URL" -o "$TMP/$FILE"; then
		echo -e "${RED}✗ Ошибка скачивания splify2${NC}"
		rm -f "$TMP/$FILE"
		return 1
	fi

	echo -e "${CYAN}Устанавливаем...${NC}"
	# --force-overwrite: интерфейс кладёт файлы в /www/luci-static, где при
	# переустановке apk может видеть их как «чужие»
	if ! apk add --allow-untrusted --force-overwrite "$TMP/$FILE" >/dev/null 2>&1; then
		echo -e "${RED}✗ Ошибка установки splify2${NC}"
		rm -f "$TMP/$FILE"
		return 1
	fi
	rm -f "$TMP/$FILE"

	/etc/init.d/rpcd restart >/dev/null 2>&1
	echo -e "${GREEN}✓ splify2 $LATEST установлен${NC}"
}

# ==============================
# Полная установка / обновление
# ==============================
install_all() {
	clear
	echo -e "${MAGENTA}╔══════════════════════════════════════════╗${NC}"
	echo -e "${MAGENTA}║${NC}  ${CYAN}Установка splify2: AWG + WARP + движок${NC}  ${MAGENTA}║${NC}"
	echo -e "${MAGENTA}╚══════════════════════════════════════════╝${NC}"

	install_awg          || { echo -e "\n${RED}Установка прервана на шаге AmneziaWG${NC}\n"; PAUSE; return 1; }
	setup_warp            || { echo -e "\n${RED}Установка прервана на шаге WARP${NC}\n"; PAUSE; return 1; }
	install_steer_engine || { echo -e "\n${RED}Установка прервана на шаге steer${NC}\n"; PAUSE; return 1; }
	install_splify2_ui   || { echo -e "\n${RED}Установка прервана на шаге splify2${NC}\n"; PAUSE; return 1; }

	echo -e "\n${MAGENTA}════════════════════════════════════════${NC}"
	echo -e "${GREEN}✓ Всё установлено!${NC}"
	echo -e "${YELLOW}Тоннель:${NC} $WARP_IFACE ${YELLOW}(готовый AmneziaWG-интерфейс)${NC}"
	echo -e "${YELLOW}Откройте:${NC} LuCI ${GREEN}→${NC} Сервисы ${GREEN}→${NC} splify2, выберите $WARP_IFACE как тоннель и отметьте нужные сервисы"
	echo -e "${MAGENTA}════════════════════════════════════════${NC}\n"
	PAUSE
}

# ==============================
# Удаление
# ==============================
uninstall_all() {
	clear
	echo -e "${MAGENTA}━━━ Удаление Splify2 ━━━${NC}\n"

	if ! pkg_installed luci-app-splify2 && ! pkg_installed steer && ! pkg_installed steer-extended; then
		echo -e "${YELLOW}Splify2 не установлен${NC}\n"; PAUSE; return 0
	fi

	echo -e "${CYAN}Останавливаем службы${NC}"
	[ -x /etc/init.d/steer ] && /etc/init.d/steer stop >/dev/null 2>&1

	echo -e "${CYAN}Удаляем пакеты${NC}"
	apk del luci-app-splify2 >/dev/null 2>&1
	apk del steer-extended >/dev/null 2>&1
	apk del steer >/dev/null 2>&1

	echo -e "${CYAN}Удаляем конфигурацию${NC}"
	rm -rf /etc/steer /etc/splify2 /var/lib/steer /var/lib/splify2
	uci -q delete splify2 2>/dev/null && uci commit splify2 2>/dev/null

	/etc/init.d/rpcd restart >/dev/null 2>&1
	echo -e "${GREEN}✓ splify2 и движок steer удалены${NC}"

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

			echo -e "${CYAN}Удаляем firewall-зону${NC}"
			_zi=0
			while [ -n "$(uci -q get "firewall.@zone[$_zi]")" ]; do
				if [ "$(uci -q get "firewall.@zone[$_zi].name")" = "$WARP_IFACE" ]; then
					uci -q delete "firewall.@zone[$_zi]"
				else
					_zi=$((_zi + 1))
				fi
			done
			_fi=0
			while [ -n "$(uci -q get "firewall.@forwarding[$_fi]")" ]; do
				if [ "$(uci -q get "firewall.@forwarding[$_fi].dest")" = "$WARP_IFACE" ]; then
					uci -q delete "firewall.@forwarding[$_fi]"
				else
					_fi=$((_fi + 1))
				fi
			done
			uci commit firewall >/dev/null 2>&1
			/etc/init.d/network restart >/dev/null 2>&1
			/etc/init.d/firewall restart >/dev/null 2>&1

			echo -e "${CYAN}Удаляем пакеты AmneziaWG${NC}"
			apk del luci-proto-amneziawg >/dev/null 2>&1
			apk del luci-i18n-amneziawg-ru >/dev/null 2>&1
			apk del amneziawg-tools >/dev/null 2>&1
			apk del kmod-amneziawg >/dev/null 2>&1

			rm -f /root/WARP.conf
			echo -e "${GREEN}✓ WARP и AmneziaWG удалены${NC}"
			;;
		*)
			echo -e "\n${YELLOW}WARP / AmneziaWG оставлены без изменений${NC}"
			;;
	esac
	echo; PAUSE
}

# ==============================
# Статус
# ==============================
show_status() {
	if pkg_installed steer-extended; then
		ST_VER="$(local_pkg_ver "steer-extended-")"
		ST_STATE="${GREEN}steer-extended $ST_VER${NC}"
	elif pkg_installed steer; then
		ST_VER="$(local_pkg_ver "steer-")"
		ST_STATE="${YELLOW}steer (базовый) $ST_VER${NC}"
	else
		ST_STATE="${RED}не установлен${NC}"
	fi

	if pkg_installed luci-app-splify2; then
		SP_VER="$(local_pkg_ver "luci-app-splify2-")"
		SP_STATE="${GREEN}$SP_VER${NC}"
	else
		SP_STATE="${RED}не установлен${NC}"
	fi

	if pkg_installed amneziawg-tools && pkg_installed kmod-amneziawg; then
		AWG_STATE="${GREEN}установлен${NC}"
	else
		AWG_STATE="${RED}не установлен${NC}"
	fi

	if [ -n "$(uci -q get "network.$WARP_IFACE" 2>/dev/null)" ]; then
		if ifstatus "$WARP_IFACE" 2>/dev/null | grep -q '"up":[[:space:]]*true'; then
			WARP_STATE="${GREEN}настроен, поднят${NC}"
		else
			WARP_STATE="${YELLOW}настроен, не поднят${NC}"
		fi
	else
		WARP_STATE="${RED}не настроен${NC}"
	fi

	if [ -x /etc/init.d/steer ] && /etc/init.d/steer status >/dev/null 2>&1; then
		STEER_SVC="${GREEN}запущен${NC}"
	else
		STEER_SVC="${RED}остановлен${NC}"
	fi

	echo -e "${YELLOW}Steer engine:${NC}       $ST_STATE"
	echo -e "${YELLOW}Служба steer:${NC}       $STEER_SVC"
	echo -e "${YELLOW}Splify2 UI:${NC}         $SP_STATE"
	echo -e "${YELLOW}AmneziaWG:${NC}          $AWG_STATE"
	echo -e "${YELLOW}Интерфейс $WARP_IFACE:${NC}    $WARP_STATE"
}

# ==============================
# Главное меню
# ==============================
show_menu() {
	clear
	echo -e "${MAGENTA}╔════════════════════════════════════════╗${NC}"
	echo -e "${MAGENTA}║${NC}          ${BLUE}Splify2 Manager${NC}                ${MAGENTA}║${NC}"
	echo -e "${MAGENTA}╚════════════════════════════════════════╝${NC}\n"

	echo -e "${YELLOW}OpenWrt:${NC} $OWRTREL  ${YELLOW}Архитектура:${NC} $ARCH\n"
	show_status

	echo -e "\n${CYAN}1) ${GREEN}Установить${NC} / ${GREEN}обновить${NC} splify2"
	echo -e "${CYAN}2) ${GREEN}Удалить${NC} splify2"
	echo -e "${CYAN}3) ${GREEN}Информация${NC} о WARP.conf"
	echo -e "${CYAN}4) ${GREEN}Перегенерировать${NC} WARP-эндпоинт"
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

# ==============================
# Запуск
# ==============================
while true; do show_menu; done
