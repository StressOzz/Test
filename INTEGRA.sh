#!/bin/sh

CONFWARP="/root/WARP.conf"
IFACE="AWG"

[ ! -f "$CONFWARP" ] && {
	echo "Файл $CONFWARP не найден"
	exit 1
}

# остановить и удалить старый интерфейс
ifdown "$IFACE" 2>/dev/null
ip link del "$IFACE" 2>/dev/null

# удалить interface
uci -q delete network.$IFACE

# удалить все amneziawg_AWG секции
while uci show network | grep -q "=amneziawg_AWG"; do
	SEC="$(uci show network | grep "=amneziawg_AWG" | head -n1 | cut -d. -f2 | cut -d= -f1)"
	[ -n "$SEC" ] && uci -q delete network.$SEC
done

# получить значение параметра
get_val() {
	sed -n "s/^$1 *= *//p" "$CONFWARP" | head -n1
}

# добавить option если значение существует
set_opt() {
	local key="$1"
	local val="$2"

	[ -n "$val" ] && uci set "network.$IFACE.$key=$val"
}

# добавить list
add_list() {
	local section="$1"
	local key="$2"
	local vals="$3"

	[ -z "$vals" ] && return

	local OLD_IFS="$IFS"
	IFS=','

	for v in $vals; do
		v="$(echo "$v" | xargs)"
		[ -n "$v" ] && uci add_list "network.$section.$key=$v"
	done

	IFS="$OLD_IFS"
}

# =========================
# Interface
# =========================

PRIVATE_KEY="$(get_val PrivateKey)"
ADDRESS="$(get_val Address)"
DNS="$(get_val DNS)"
MTU="$(get_val MTU)"

S1="$(get_val S1)"
S2="$(get_val S2)"
S3="$(get_val S3)"
S4="$(get_val S4)"

JC="$(get_val Jc)"
JMIN="$(get_val Jmin)"
JMAX="$(get_val Jmax)"

H1="$(get_val H1)"
H2="$(get_val H2)"
H3="$(get_val H3)"
H4="$(get_val H4)"

I1="$(get_val I1)"
I2="$(get_val I2)"
I3="$(get_val I3)"
I4="$(get_val I4)"
I5="$(get_val I5)"

uci set network.$IFACE="interface"

set_opt proto "amneziawg"
set_opt private_key "$PRIVATE_KEY"

set_opt awg_s1 "$S1"
set_opt awg_s2 "$S2"
set_opt awg_s3 "$S3"
set_opt awg_s4 "$S4"

set_opt awg_jc "$JC"
set_opt awg_jmin "$JMIN"
set_opt awg_jmax "$JMAX"

set_opt awg_h1 "$H1"
set_opt awg_h2 "$H2"
set_opt awg_h3 "$H3"
set_opt awg_h4 "$H4"

set_opt awg_i1 "$I1"
set_opt awg_i2 "$I2"
set_opt awg_i3 "$I3"
set_opt awg_i4 "$I4"
set_opt awg_i5 "$I5"

set_opt mtu "$MTU"

uci set network.$IFACE.multipath="off"

add_list "$IFACE" addresses "$ADDRESS"
add_list "$IFACE" dns "$DNS"

# =========================
# Peer
# =========================

PUBLIC_KEY="$(get_val PublicKey)"
PRESHARED_KEY="$(get_val PresharedKey)"
ALLOWED_IPS="$(get_val AllowedIPs)"
ENDPOINT="$(get_val Endpoint)"
KEEPALIVE="$(get_val PersistentKeepalive)"

ENDPOINT_HOST="${ENDPOINT%:*}"
ENDPOINT_PORT="${ENDPOINT##*:}"

# создать peer
PEER_SECTION="$(uci add network amneziawg_AWG)"

# добавить peer option если значение существует
set_peer_opt() {
	local key="$1"
	local val="$2"

	[ -n "$val" ] && uci set "network.$PEER_SECTION.$key=$val"
}

set_peer_opt description "$(basename "$CONFWARP")"
set_peer_opt public_key "$PUBLIC_KEY"
set_peer_opt preshared_key "$PRESHARED_KEY"

add_list "$PEER_SECTION" allowed_ips "$ALLOWED_IPS"

set_peer_opt endpoint_host "$ENDPOINT_HOST"
set_peer_opt endpoint_port "$ENDPOINT_PORT"
set_peer_opt persistent_keepalive "$KEEPALIVE"

# сохранить
uci commit network

# перезапуск сети
/etc/init.d/network restart

echo "AWG интерфейс успешно создан"
