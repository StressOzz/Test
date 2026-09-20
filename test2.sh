#!/bin/sh
# YouTube Bypass — установщик для OpenWrt
# ByeDPI (DPITrickster/ByeDPI-OpenWrt) + hev-socks5-tunnel + LuCI-приложение.
# В обход DPI заворачиваются только домены YouTube, остальной трафик идёт напрямую.
#
#   sh install.sh               установить и запустить
#   sh install.sh --no-start    установить, но не запускать
#   sh install.sh --uninstall   удалить (пакеты byedpi и hev остаются)
#   sh install.sh --purge       удалить вместе с пакетами byedpi и hev-socks5-tunnel
#
# Переменные окружения:
#   BYEDPI_URL=<ссылка на .ipk/.apk>   поставить byedpi с конкретной ссылки
#   FORCE_BYEDPI=1                     переустановить byedpi

BYEDPI_REPO="DPITrickster/ByeDPI-OpenWrt"
NEW_BYEDPI=0
NEW_HEV=0

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!! \033[0m%s\n' "$*" >&2; }
die()  { printf '\033[1;31mОшибка:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- аргументы
MODE=install
NOSTART=0
for a in "$@"; do
	case "$a" in
		--no-start)  NOSTART=1 ;;
		--uninstall) MODE=uninstall ;;
		--purge)     MODE=purge ;;
		-h|--help)   sed -n '2,13p' "$0" 2>/dev/null; exit 0 ;;
		*) die "неизвестный аргумент: $a" ;;
	esac
done

# ---------------------------------------------------------------- окружение
[ "$(id -u)" = "0" ] || die "нужны права root"
[ -f /etc/openwrt_release ] || die "это не OpenWrt"
. /etc/openwrt_release
ARCH="$DISTRIB_ARCH"
REL_MM=$(echo "$DISTRIB_RELEASE" | cut -d. -f1,2)

if command -v apk >/dev/null 2>&1; then
	PM=apk;  EXT=apk
elif command -v opkg >/dev/null 2>&1; then
	PM=opkg; EXT=ipk
else
	die "не найден ни apk, ни opkg"
fi

pkg_has() {
	if [ "$PM" = apk ]; then apk info -e "$1" >/dev/null 2>&1
	else opkg list-installed 2>/dev/null | grep -q "^$1 - "; fi
}
pkg_add() { if [ "$PM" = apk ]; then apk add "$@"; else opkg install "$@"; fi; }
pkg_del() { if [ "$PM" = apk ]; then apk del "$@"; else opkg remove "$@"; fi; }

fetch() { # fetch URL OUT   (OUT="-" — в stdout)
	if command -v curl >/dev/null 2>&1; then
		curl -fsSL --connect-timeout 15 -o "$2" "$1"
	else
		wget -q -T 20 -O "$2" "$1"
	fi
}

# ---------------------------------------------------------------- удаление
YTB_FILES="/etc/config/ytbypass /etc/init.d/ytbypass /etc/hotplug.d/firewall/90-ytbypass
/usr/bin/ytbypass /usr/libexec/ytbypass /usr/share/ytbypass
/usr/share/nftables.d/chain-pre/forward/50-ytbypass.nft
/usr/share/luci/menu.d/luci-app-ytbypass.json /usr/share/rpcd/acl.d/luci-app-ytbypass.json
/www/luci-static/resources/view/ytbypass /var/etc/ytbypass /var/run/ytbypass.started"

do_uninstall() {
	say "Останавливаю и удаляю YouTube Bypass"
	if [ -x /etc/init.d/ytbypass ]; then
		/etc/init.d/ytbypass stop >/dev/null 2>&1
		/etc/init.d/ytbypass disable >/dev/null 2>&1
	fi
	if [ -x /usr/libexec/ytbypass/net.sh ]; then
		/usr/libexec/ytbypass/net.sh purge >/dev/null 2>&1
		. /usr/libexec/ytbypass/common.sh
		rm -f "$(dnsmasq_confdir)/ytbypass.conf"
	fi
	# shellcheck disable=SC2086
	rm -rf $YTB_FILES
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
	/etc/init.d/firewall reload >/dev/null 2>&1
	rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
	/etc/init.d/rpcd reload >/dev/null 2>&1
	if [ "$MODE" = purge ]; then
		say "Удаляю пакеты byedpi и hev-socks5-tunnel"
		pkg_del byedpi hev-socks5-tunnel >/dev/null 2>&1
	fi
	say "Готово."
	exit 0
}

[ "$MODE" = install ] || do_uninstall

# ---------------------------------------------------------------- проверки
say "OpenWrt $DISTRIB_RELEASE, архитектура $ARCH, менеджер пакетов: $PM"
command -v fw4 >/dev/null 2>&1 || die "нужен firewall4 (OpenWrt 22.03+); hev-socks5-tunnel в пакетах — с 24.10"
command -v nft >/dev/null 2>&1 || die "не найден nft"
[ -d /www/luci-static/resources ] || warn "LuCI не найден — веб-интерфейс работать не будет (установите luci)"

if ip rule add pref 8999 fwmark 0x10000/0x10000 lookup 89 2>/dev/null; then
	ip rule del pref 8999 2>/dev/null
else
	die "ваш ip не поддерживает fwmark с маской. Установите ip-full: замените ip-tiny на ip-full и запустите установщик снова"
fi

say "Обновляю списки пакетов"
if [ "$PM" = apk ]; then apk update >/dev/null 2>&1 || warn "apk update не удался"
else opkg update >/dev/null 2>&1 || warn "opkg update не удался"; fi

# ---------------------------------------------------------------- dnsmasq-full
fix_resolv() {
	rm -f /tmp/resolv.conf
	if grep -qs '^nameserver' /tmp/resolv.conf.d/resolv.conf.auto; then
		cp /tmp/resolv.conf.d/resolv.conf.auto /tmp/resolv.conf
	else
		printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > /tmp/resolv.conf
	fi
}

ensure_dnsmasq_full() {
	if dnsmasq --version 2>/dev/null | grep -Eq '(^| )nftset( |$)'; then
		say "dnsmasq с поддержкой nftset уже установлен"
		return 0
	fi
	say "Заменяю dnsmasq на dnsmasq-full (нужен nftset)"
	cp /etc/config/dhcp /tmp/dhcp.ytb.bak 2>/dev/null
	for p in dnsmasq dnsmasq-dhcpv6; do
		pkg_has "$p" && pkg_del "$p" >/dev/null 2>&1
	done
	fix_resolv
	if ! pkg_add dnsmasq-full; then
		warn "не удалось поставить dnsmasq-full, возвращаю обычный dnsmasq"
		fix_resolv
		pkg_add dnsmasq
		[ -f /etc/config/dhcp ] || cp /tmp/dhcp.ytb.bak /etc/config/dhcp 2>/dev/null
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
		die "dnsmasq-full не установлен"
	fi
	[ -f /etc/config/dhcp ] || cp /tmp/dhcp.ytb.bak /etc/config/dhcp 2>/dev/null
	/etc/init.d/dnsmasq enable >/dev/null 2>&1
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
}

# ---------------------------------------------------------------- byedpi
install_byedpi() {
	if [ -x /usr/bin/ciadpi ] && [ "${FORCE_BYEDPI:-0}" != 1 ]; then
		say "ByeDPI уже установлен"
		return 0
	fi
	url="${BYEDPI_URL:-}"
	if [ -z "$url" ]; then
		say "Ищу пакет byedpi ($ARCH, .$EXT) в $BYEDPI_REPO"
		json=$(fetch "https://api.github.com/repos/$BYEDPI_REPO/releases?per_page=40" - 2>/dev/null)
		cands=$(printf '%s\n' "$json" \
			| grep -o '"browser_download_url": *"[^"]*"' \
			| sed 's/^[^:]*: *"//; s/"$//' \
			| grep -E "/byedpi_[^/]*_${ARCH}\.${EXT}\$")
		# предпочитаем релиз под вашу версию OpenWrt, иначе самый свежий
		url=$(printf '%s\n' "$cands" | grep -F "$REL_MM" | head -n 1)
		[ -n "$url" ] || url=$(printf '%s\n' "$cands" | head -n 1)
	fi
	[ -n "$url" ] || die "не нашёл пакет byedpi для $ARCH (.$EXT). Скачайте вручную с https://github.com/$BYEDPI_REPO/releases и запустите: BYEDPI_URL=<ссылка> sh install.sh"
	say "Скачиваю $url"
	mkdir -p /tmp/ytb-dl
	f="/tmp/ytb-dl/$(basename "$url")"
	fetch "$url" "$f" || die "не удалось скачать byedpi"
	if [ "$PM" = apk ]; then apk add --allow-untrusted "$f"; else opkg install "$f"; fi \
		|| die "не удалось установить byedpi"
	NEW_BYEDPI=1
}

# ---------------------------------------------------------------- payload
# Файлы приложения вшиты обычным текстом (без base64/tar — их может не быть в busybox).
install_payload() {
	R="${YTB_ROOT:-}"
	mkdir -p "$R/etc/config"
	[ -f "$R/etc/config/ytbypass" ] || cat > "$R/etc/config/ytbypass" <<'YTB_FILE_END_7f3a9c'
config ytbypass 'main'
	option enabled '1'
	# локальный порт SOCKS5 у ByeDPI (отдельный экземпляр, штатный byedpi не трогаем)
	option byedpi_port '1088'
	# стратегия обхода DPI, подбирается под провайдера
	option byedpi_opts '--split 1 --disorder 3+s --mod-http=h,d --auto=torst --tlsrec 1+s'
	# заворачивать IPv6-адреса YouTube (0 — только IPv4)
	option ipv6 '1'
	# QUIC (UDP/443): block — отбрасывать, чтобы клиент откатился на TCP; proxy — гнать через ByeDPI
	option quic 'block'
	# использовать встроенный список доменов YouTube
	option default_domains '1'
	# дополнительные домены:
	# list domain 'example.com'
YTB_FILE_END_7f3a9c
	chmod 644 "$R/etc/config/ytbypass"
	mkdir -p "$R/etc/hotplug.d/firewall"
	cat > "$R/etc/hotplug.d/firewall/90-ytbypass" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Если после reload firewall наша таблица пропала — восстановить.
[ -f /var/run/ytbypass.started ] || exit 0
nft list table inet ytbypass >/dev/null 2>&1 && exit 0
logger -t ytbypass "таблица nft пропала после reload firewall — восстанавливаю"
/etc/init.d/ytbypass restart >/dev/null 2>&1
exit 0
YTB_FILE_END_7f3a9c
	chmod 755 "$R/etc/hotplug.d/firewall/90-ytbypass"
	mkdir -p "$R/etc/init.d"
	cat > "$R/etc/init.d/ytbypass" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh /etc/rc.common
# YouTube Bypass: ByeDPI + hev-socks5-tunnel, маршрутизация только доменов YouTube

START=99
STOP=10
USE_PROCD=1

NAME=ytbypass
LIBEXEC=/usr/libexec/ytbypass
RUNDIR=/var/etc/ytbypass
DOMAINS_DEFAULT=/usr/share/ytbypass/domains.list
STARTED_FLAG=/var/run/ytbypass.started

. "$LIBEXEC/common.sh"

log() { logger -t "$NAME" "$*"; }
_echo() { echo "$1"; }

find_byedpi() {
	local b
	for b in /usr/bin/ciadpi /usr/bin/byedpi; do
		[ -x "$b" ] && { echo "$b"; return 0; }
	done
	command -v ciadpi
}

# итоговый список доменов: встроенный + свои, только валидные имена
collect_domains() {
	local use_default
	config_get use_default main default_domains 1
	{
		[ "$use_default" = "1" ] && [ -f "$DOMAINS_DEFAULT" ] && cat "$DOMAINS_DEFAULT"
		config_list_foreach main domain _echo
	} | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
	  | tr 'A-Z' 'a-z' \
	  | grep -E '^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$' \
	  | sort -u
}

dns_remove() {
	local conf
	conf="$(dnsmasq_confdir)/ytbypass.conf"
	[ -f "$conf" ] || return 0
	rm -f "$conf"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
}

# записать nftset-правило для dnsmasq; dnsmasq перезапускается только при изменении
dns_apply() {
	local ipv6="$1" conf domains line old
	conf="$(dnsmasq_confdir)/ytbypass.conf"
	domains=$(collect_domains | tr '\n' '/')
	if [ -z "$domains" ]; then
		dns_remove
		return 0
	fi
	line="nftset=/${domains}4#inet#${NFT_TABLE}#yt4"
	[ "$ipv6" = "1" ] && line="$line,6#inet#${NFT_TABLE}#yt6"
	old=$(cat "$conf" 2>/dev/null)
	if [ "$old" != "$line" ]; then
		mkdir -p "$(dirname "$conf")"
		echo "$line" > "$conf"
		/etc/init.d/dnsmasq restart >/dev/null 2>&1
	fi
}

write_hev_conf() {
	local port="$1" ipv6="$2" f="$RUNDIR/hev.yml"
	{
		echo "tunnel:"
		echo "  name: $TUN"
		echo "  mtu: 1500"
		echo "  ipv4: 198.18.0.1"
		[ "$ipv6" = "1" ] && echo "  ipv6: 'fc00::1'"
		echo "  post-up-script: $LIBEXEC/route-up.sh"
		echo "socks5:"
		echo "  port: $port"
		echo "  address: 127.0.0.1"
		echo "  udp: 'udp'"
		echo "misc:"
		echo "  log-level: warn"
	} > "$f"
}

# правило forward в fw4 (иначе policy drop не пропустит LAN -> tun)
ensure_fw4_include() {
	command -v fw4 >/dev/null 2>&1 || { log "fw4 не найден — нужен OpenWrt 22.03+"; return 0; }
	nft list chain inet fw4 forward 2>/dev/null | grep -q "ytbypass" && return 0
	[ -f /usr/share/nftables.d/chain-pre/forward/50-ytbypass.nft ] || return 0
	log "перезагружаю firewall, чтобы подхватить правило forward"
	/etc/init.d/firewall reload >/dev/null 2>&1
}

start_service() {
	local enabled byedpi_port byedpi_opts ipv6 byedpi hev

	config_load "$NAME"
	config_get enabled main enabled 0
	if [ "$enabled" != "1" ]; then
		"$LIBEXEC/net.sh" purge
		dns_remove
		rm -f "$STARTED_FLAG"
		return 0
	fi

	config_get byedpi_port main byedpi_port 1088
	config_get byedpi_opts main byedpi_opts ""
	config_get ipv6 main ipv6 1
	[ -f /proc/net/if_inet6 ] || ipv6=0

	case "$byedpi_port" in
		''|*[!0-9]*) log "некорректный порт: $byedpi_port"; return 1 ;;
	esac

	byedpi=$(find_byedpi)
	hev=$(command -v hev-socks5-tunnel)
	[ -n "$byedpi" ] || { log "ciadpi не найден: установите пакет byedpi"; return 1; }
	[ -n "$hev" ] || { log "hev-socks5-tunnel не найден: установите пакет"; return 1; }
	dnsmasq_has_nftset || { log "dnsmasq без поддержки nftset: установите dnsmasq-full"; return 1; }
	[ -c /dev/net/tun ] || modprobe tun 2>/dev/null

	mkdir -p "$RUNDIR"
	write_hev_conf "$byedpi_port" "$ipv6"

	"$LIBEXEC/net.sh" up || { log "не удалось настроить nftables/маршрутизацию"; return 1; }
	ensure_fw4_include
	dns_apply "$ipv6"

	# --- ByeDPI: локальный SOCKS5 с десинхронизацией ---
	procd_open_instance byedpi
	procd_set_param command "$byedpi" -i 127.0.0.1 -p "$byedpi_port"
	set -f
	# shellcheck disable=SC2086
	[ -n "$byedpi_opts" ] && procd_append_param command $byedpi_opts
	set +f
	procd_set_param respawn 3600 5 0
	procd_set_param stderr 1
	procd_close_instance

	# --- hev-socks5-tunnel: TUN -> SOCKS5 ByeDPI ---
	procd_open_instance hev
	procd_set_param command "$hev" "$RUNDIR/hev.yml"
	procd_set_param respawn 3600 5 0
	procd_set_param stderr 1
	procd_close_instance

	touch "$STARTED_FLAG"
}

stop_service() {
	rm -f "$STARTED_FLAG"
	"$LIBEXEC/net.sh" down
}

service_triggers() {
	procd_add_reload_trigger "$NAME"
}
YTB_FILE_END_7f3a9c
	chmod 755 "$R/etc/init.d/ytbypass"
	mkdir -p "$R/usr/bin"
	cat > "$R/usr/bin/ytbypass" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Вспомогательная утилита YouTube Bypass (используется LuCI и для отладки)
#   ytbypass status   — состояние в JSON
#   ytbypass flush    — очистить наборы IP (клиентам нужно заново резолвить домены)
#   ytbypass list     — показать IP в наборах

. /lib/functions.sh
. /usr/libexec/ytbypass/common.sh

svc_running() {
	ubus call service list '{"name":"ytbypass"}' 2>/dev/null \
		| jsonfilter -e "@.ytbypass.instances.$1.running" 2>/dev/null | grep -q true
}

count_set() {
	nft list set inet "$NFT_TABLE" "$1" 2>/dev/null | grep -o 'expires' | wc -l
}

b() { if [ "$1" = "1" ]; then echo true; else echo false; fi; }

case "$1" in
status)
	config_load ytbypass
	config_get enabled main enabled 0
	config_get ipv6 main ipv6 1
	config_get quic main quic block

	v_byedpi=0; svc_running byedpi && v_byedpi=1
	v_hev=0;    svc_running hev && v_hev=1
	v_tun=0;    ip link show "$TUN" >/dev/null 2>&1 && v_tun=1
	v_nft=0;    nft list table inet "$NFT_TABLE" >/dev/null 2>&1 && v_nft=1
	v_rule=0;   ip rule show 2>/dev/null | grep -q "lookup $TABLE" && v_rule=1
	v_route=0;  ip route show table "$TABLE" 2>/dev/null | grep -q "$TUN" && v_route=1
	v_dns=0;    [ -s "$(dnsmasq_confdir)/ytbypass.conf" ] && v_dns=1
	v_nftset=0; dnsmasq_has_nftset && v_nftset=1
	v_fw=0;     nft list chain inet fw4 forward 2>/dev/null | grep -q ytbypass && v_fw=1
	v_bin=0;    { [ -x /usr/bin/ciadpi ] || [ -x /usr/bin/byedpi ]; } && [ -x /usr/bin/hev-socks5-tunnel ] && v_bin=1

	printf '{"enabled":%s,"byedpi":%s,"hev":%s,"tun":%s,"nft":%s,"rule":%s,"route":%s,"dns":%s,"dnsmasq_nftset":%s,"fw":%s,"binaries":%s,"ipv6":%s,"quic":"%s","ips4":%s,"ips6":%s}\n' \
		"$(b "$enabled")" "$(b $v_byedpi)" "$(b $v_hev)" "$(b $v_tun)" "$(b $v_nft)" \
		"$(b $v_rule)" "$(b $v_route)" "$(b $v_dns)" "$(b $v_nftset)" "$(b $v_fw)" "$(b $v_bin)" \
		"$(b "$ipv6")" "$quic" "$(count_set yt4)" "$(count_set yt6)"
	;;
flush)
	nft flush set inet "$NFT_TABLE" yt4 2>/dev/null
	nft flush set inet "$NFT_TABLE" yt6 2>/dev/null
	echo "наборы очищены"
	;;
list)
	nft list set inet "$NFT_TABLE" yt4 2>/dev/null
	nft list set inet "$NFT_TABLE" yt6 2>/dev/null
	;;
*)
	echo "usage: ytbypass status|flush|list" >&2
	exit 1
	;;
esac
YTB_FILE_END_7f3a9c
	chmod 755 "$R/usr/bin/ytbypass"
	mkdir -p "$R/usr/libexec/ytbypass"
	cat > "$R/usr/libexec/ytbypass/common.sh" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Общие константы и функции YouTube Bypass

TUN=ytb0            # имя TUN-интерфейса hev-socks5-tunnel
MARK=0x10000        # fwmark (один выделенный бит)
MASK=0x10000
TABLE=89            # таблица маршрутизации
PREF=8900           # приоритет ip rule
NFT_TABLE=ytbypass

# каталог conf-dir, который читает dnsmasq
dnsmasq_confdir() {
	local d
	d=$(sed -n 's/^conf-dir=\([^,]*\).*/\1/p' /var/etc/dnsmasq.conf.* 2>/dev/null | head -n 1)
	[ -n "$d" ] || d=/tmp/dnsmasq.d
	echo "$d"
}

# dnsmasq собран с nftset (dnsmasq-full)?
dnsmasq_has_nftset() {
	dnsmasq --version 2>/dev/null | grep -Eq '(^| )nftset( |$)'
}
YTB_FILE_END_7f3a9c
	chmod 755 "$R/usr/libexec/ytbypass/common.sh"
	mkdir -p "$R/usr/libexec/ytbypass"
	cat > "$R/usr/libexec/ytbypass/net.sh" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Настройка nftables и policy routing.
# Использование: net.sh up | down | purge
#   up    — создать таблицу inet ytbypass и ip rule
#   down  — убрать правила маркировки и ip rule (наборы IP остаются, чтобы dnsmasq не сыпал ошибками)
#   purge — удалить всё, включая таблицу

. /lib/functions.sh
. /usr/libexec/ytbypass/common.sh

config_load ytbypass
config_get IPV6 main ipv6 1
config_get QUIC main quic block
[ -f /proc/net/if_inet6 ] || IPV6=0

rules_del() {
	while ip rule del pref "$PREF" 2>/dev/null; do :; done
	while ip -6 rule del pref "$PREF" 2>/dev/null; do :; done
	ip route del default dev "$TUN" table "$TABLE" 2>/dev/null
	ip -6 route del default dev "$TUN" table "$TABLE" 2>/dev/null
}

set_mark_stmt="ct mark set ct mark | $MARK meta mark set meta mark | $MARK"

gen_ruleset() {
	cat <<NFT
table inet $NFT_TABLE {
	set yt4 {
		type ipv4_addr
		flags timeout
		timeout 12h
		size 65535
	}
	set yt6 {
		type ipv6_addr
		flags timeout
		timeout 12h
		size 65535
	}
	chain prerouting {
		type filter hook prerouting priority mangle; policy accept;
		iifname "$TUN" return
		ct mark & $MASK == $MARK meta mark set meta mark | $MARK return
		meta l4proto tcp ip daddr @yt4 $set_mark_stmt
NFT
	[ "$IPV6" = "1" ] && echo "		meta l4proto tcp ip6 daddr @yt6 $set_mark_stmt"
	if [ "$QUIC" = "proxy" ]; then
		echo "		udp dport 443 ip daddr @yt4 $set_mark_stmt"
		[ "$IPV6" = "1" ] && echo "		udp dport 443 ip6 daddr @yt6 $set_mark_stmt"
	fi
	echo "	}"
	if [ "$QUIC" != "proxy" ]; then
		cat <<NFT
	chain forward {
		type filter hook forward priority filter - 10; policy accept;
		udp dport 443 ip daddr @yt4 reject
		udp dport 443 ip6 daddr @yt6 reject
	}
NFT
	fi
	echo "}"
}

case "$1" in
up)
	rules_del
	nft delete table inet "$NFT_TABLE" 2>/dev/null
	gen_ruleset | nft -f - || exit 1
	ip rule add pref "$PREF" fwmark "$MARK/$MASK" lookup "$TABLE" || exit 1
	[ "$IPV6" = "1" ] && ip -6 rule add pref "$PREF" fwmark "$MARK/$MASK" lookup "$TABLE"
	# если туннель уже поднят — сразу добавить маршрут (иначе это сделает post-up hev)
	ip link show "$TUN" >/dev/null 2>&1 && /usr/libexec/ytbypass/route-up.sh "$TUN"
	exit 0
	;;
down)
	rules_del
	nft flush chain inet "$NFT_TABLE" prerouting 2>/dev/null
	nft flush chain inet "$NFT_TABLE" forward 2>/dev/null
	;;
purge)
	rules_del
	nft delete table inet "$NFT_TABLE" 2>/dev/null
	;;
*)
	echo "usage: $0 up|down|purge" >&2
	exit 1
	;;
esac
exit 0
YTB_FILE_END_7f3a9c
	chmod 755 "$R/usr/libexec/ytbypass/net.sh"
	mkdir -p "$R/usr/libexec/ytbypass"
	cat > "$R/usr/libexec/ytbypass/route-up.sh" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Вызывается hev-socks5-tunnel после подъёма TUN (и из net.sh up).
# Если туннель упадёт, маршрут исчезнет вместе с интерфейсом, и помеченный
# трафик уйдёт по основной таблице напрямую (fail-open).

. /lib/functions.sh
. /usr/libexec/ytbypass/common.sh

config_load ytbypass
config_get IPV6 main ipv6 1
[ -f /proc/net/if_inet6 ] || IPV6=0

ip link set "$TUN" up 2>/dev/null
ip route replace default dev "$TUN" table "$TABLE"
[ "$IPV6" = "1" ] && ip -6 route replace default dev "$TUN" table "$TABLE"

# ответы приходят с адресов YouTube на TUN — нужен нестрогий rp_filter (2 = loose)
echo 2 > "/proc/sys/net/ipv4/conf/$TUN/rp_filter" 2>/dev/null
exit 0
YTB_FILE_END_7f3a9c
	chmod 755 "$R/usr/libexec/ytbypass/route-up.sh"
	mkdir -p "$R/usr/share/luci/menu.d"
	cat > "$R/usr/share/luci/menu.d/luci-app-ytbypass.json" <<'YTB_FILE_END_7f3a9c'
{
	"admin/services/ytbypass": {
		"title": "YouTube Bypass",
		"order": 60,
		"action": {
			"type": "view",
			"path": "ytbypass/main"
		},
		"depends": {
			"acl": [ "luci-app-ytbypass" ],
			"uci": { "ytbypass": true }
		}
	}
}
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/luci/menu.d/luci-app-ytbypass.json"
	mkdir -p "$R/usr/share/nftables.d/chain-pre/forward"
	cat > "$R/usr/share/nftables.d/chain-pre/forward/50-ytbypass.nft" <<'YTB_FILE_END_7f3a9c'
oifname "ytb0" accept comment "ytbypass"
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/nftables.d/chain-pre/forward/50-ytbypass.nft"
	mkdir -p "$R/usr/share/rpcd/acl.d"
	cat > "$R/usr/share/rpcd/acl.d/luci-app-ytbypass.json" <<'YTB_FILE_END_7f3a9c'
{
	"luci-app-ytbypass": {
		"description": "YouTube Bypass (ByeDPI + hev-socks5-tunnel)",
		"read": {
			"file": {
				"/usr/bin/ytbypass": [ "exec" ],
				"/etc/init.d/ytbypass": [ "exec" ]
			},
			"uci": [ "ytbypass" ]
		},
		"write": {
			"uci": [ "ytbypass" ]
		}
	}
}
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/rpcd/acl.d/luci-app-ytbypass.json"
	mkdir -p "$R/usr/share/ytbypass"
	cat > "$R/usr/share/ytbypass/domains.list" <<'YTB_FILE_END_7f3a9c'
# Домены YouTube (поддомены подхватываются автоматически)
youtube.com
youtu.be
youtube-nocookie.com
youtubei.googleapis.com
youtube.googleapis.com
googlevideo.com
ytimg.com
ggpht.com
yt3.googleusercontent.com
youtubeeducation.com
youtubekids.com
withyoutube.com
yt.be
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/ytbypass/domains.list"
	mkdir -p "$R/www/luci-static/resources/view/ytbypass"
	cat > "$R/www/luci-static/resources/view/ytbypass/main.js" <<'YTB_FILE_END_7f3a9c'
'use strict';
'require view';
'require form';
'require fs';
'require poll';
'require ui';
'require dom';

var CTL = '/usr/bin/ytbypass';
var INIT = '/etc/init.d/ytbypass';

/* Готовые стратегии ByeDPI — отправные точки, под своего провайдера подбирайте сами */
var PRESET_1 = '--split 1 --disorder 3+s --mod-http=h,d --auto=torst --tlsrec 1+s';
var PRESET_2 = '-s1 -d1 -r1+s -a1 -Ar -o1 -a1 -At -f-1 -r1+s -a1';

function getStatus() {
	return fs.exec_direct(CTL, [ 'status' ], 'json').catch(function() { return null; });
}

function badge(ok, okText, badText) {
	return E('span', {
		'style': 'display:inline-block;padding:2px 8px;border-radius:3px;color:#fff;background:' +
			(ok ? '#2e9c4b' : '#c0392b')
	}, ok ? okText : badText);
}

function row(label, node) {
	return E('tr', { 'class': 'tr' }, [
		E('td', { 'class': 'td left', 'style': 'width:38%' }, label),
		E('td', { 'class': 'td left' }, node)
	]);
}

function renderStatus(st) {
	if (!st)
		return E('em', {}, _('Не удалось получить состояние (проверьте, что установлен rpcd-mod-file и ACL применён).'));

	var working = st.enabled && st.byedpi && st.hev && st.tun && st.nft && st.rule && st.route && st.dns && st.fw;
	var rows = [
		row(_('Итог'), working
			? badge(true, _('Работает'))
			: badge(false, '', st.enabled ? _('Не полностью запущен') : _('Выключен'))),
		row(_('ByeDPI (ciadpi)'), badge(st.byedpi, _('запущен'), _('не запущен'))),
		row(_('hev-socks5-tunnel'), badge(st.hev, _('запущен'), _('не запущен'))),
		row(_('Интерфейс ytb0'), badge(st.tun, _('поднят'), _('нет'))),
		row(_('Маркировка nftables'), badge(st.nft, _('активна'), _('нет'))),
		row(_('Policy routing'), badge(st.rule && st.route, _('активен'), _('нет'))),
		row(_('dnsmasq → nftset'), st.dnsmasq_nftset
			? badge(st.dns, _('домены загружены'), _('нет'))
			: badge(false, '', _('нужен dnsmasq-full'))),
		row(_('Firewall forward'), badge(st.fw, _('разрешён'), _('нет'))),
		row(_('IP в наборах'), 'IPv4: ' + st.ips4 + (st.ipv6 ? ', IPv6: ' + st.ips6 : ''))
	];

	if (!st.binaries)
		rows.unshift(row(_('Пакеты'), badge(false, '', _('не найден byedpi или hev-socks5-tunnel'))));

	return E('table', { 'class': 'table' }, rows);
}

function notify(ok, text) {
	ui.addNotification(null, E('p', text), ok ? 'info' : 'danger');
}

return view.extend({
	load: function() {
		return getStatus();
	},

	render: function(st) {
		var m, s, o;

		m = new form.Map('ytbypass', _('YouTube Bypass'),
			_('Трафик только до доменов YouTube проходит через TUN-интерфейс (hev-socks5-tunnel) в локальный SOCKS5 ByeDPI. ' +
			  'Остальной трафик идёт напрямую. Клиенты должны использовать DNS роутера (dnsmasq).'));

		s = m.section(form.NamedSection, 'main', 'ytbypass', _('Настройки'));
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Включить'));
		o.rmempty = false;
		o.default = '1';

		o = s.option(form.Value, 'byedpi_opts', _('Стратегия ByeDPI'),
			_('Параметры командной строки ciadpi. Можно выбрать готовую или вписать свою. ' +
			  'Стратегия зависит от провайдера — подбирайте (например, через ByeByeDPI).'));
		o.value(PRESET_1, _('Вариант 1: split + disorder + tlsrec'));
		o.value(PRESET_2, _('Вариант 2: split/disorder + fake (из issue #357 ByeDPI)'));
		o.default = PRESET_1;
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (/[\r\n]/.test(value))
				return _('Параметры должны быть в одной строке');
			return true;
		};

		o = s.option(form.Value, 'byedpi_port', _('Порт SOCKS5 ByeDPI'),
			_('Локальный порт (127.0.0.1). Отдельный экземпляр, штатная служба byedpi не затрагивается.'));
		o.datatype = 'port';
		o.default = '1088';
		o.rmempty = false;

		o = s.option(form.ListValue, 'quic', _('QUIC (UDP/443) до YouTube'),
			_('«Блокировать» — клиент быстро откатится на TCP, который обрабатывает ByeDPI (рекомендуется). ' +
			  '«Через прокси» — пробовать пропускать UDP через ByeDPI.'));
		o.value('block', _('Блокировать (рекомендуется)'));
		o.value('proxy', _('Через прокси'));
		o.default = 'block';

		o = s.option(form.Flag, 'ipv6', _('IPv6'),
			_('Заворачивать IPv6-адреса YouTube. Если IPv6 у вас нет — отключите.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.Flag, 'default_domains', _('Встроенный список доменов'),
			_('youtube.com, googlevideo.com, ytimg.com, ggpht.com, youtu.be и др.'));
		o.default = '1';
		o.rmempty = false;

		o = s.option(form.DynamicList, 'domain', _('Дополнительные домены'),
			_('Поддомены подхватываются автоматически. Например: example.com'));
		o.datatype = 'hostname';
		o.placeholder = 'example.com';

		o = s.option(form.Button, '_restart', _('Служба'));
		o.inputtitle = _('Перезапустить');
		o.inputstyle = 'apply';
		o.onclick = function() {
			return fs.exec(INIT, [ 'restart' ]).then(function() {
				notify(true, _('Служба перезапущена.'));
			}).catch(function(e) {
				notify(false, _('Ошибка: ') + e.message);
			});
		};

		o = s.option(form.Button, '_flush', _('Наборы IP'));
		o.inputtitle = _('Очистить');
		o.inputstyle = 'reset';
		o.onclick = function() {
			return fs.exec(CTL, [ 'flush' ]).then(function() {
				notify(true, _('Наборы очищены. Обновите DNS-кэш на клиентах или перезапустите браузер.'));
			}).catch(function(e) {
				notify(false, _('Ошибка: ') + e.message);
			});
		};

		return m.render().then(function(mapEl) {
			var statusEl = E('div', {}, renderStatus(st));

			poll.add(function() {
				return getStatus().then(function(res) {
					dom.content(statusEl, renderStatus(res));
				});
			}, 5);

			return E([
				E('div', { 'class': 'cbi-section' }, [ E('h3', _('Состояние')), statusEl ]),
				mapEl
			]);
		});
	}
});
YTB_FILE_END_7f3a9c
	chmod 644 "$R/www/luci-static/resources/view/ytbypass/main.js"
}

# ================================================================ установка
[ "$PM" = apk ] || true
pkg_has kmod-tun || { say "Ставлю kmod-tun"; pkg_add kmod-tun || die "kmod-tun не установлен"; }
ensure_dnsmasq_full

if ! pkg_has hev-socks5-tunnel; then
	say "Ставлю hev-socks5-tunnel"
	pkg_add hev-socks5-tunnel || die "hev-socks5-tunnel не найден в репозитории (есть в feeds OpenWrt 24.10+)"
	NEW_HEV=1
fi
install_byedpi

# свежепоставленные пакеты стартуют со своими дефолтами — гасим, наш экземпляр запускает ytbypass
if [ "$NEW_BYEDPI" = 1 ] && [ -x /etc/init.d/byedpi ]; then
	/etc/init.d/byedpi stop >/dev/null 2>&1; /etc/init.d/byedpi disable >/dev/null 2>&1
fi
if [ "$NEW_HEV" = 1 ] && [ -x /etc/init.d/hev-socks5-tunnel ]; then
	/etc/init.d/hev-socks5-tunnel stop >/dev/null 2>&1; /etc/init.d/hev-socks5-tunnel disable >/dev/null 2>&1
fi

say "Устанавливаю YouTube Bypass (сервис + LuCI)"
install_payload
rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache
/etc/init.d/rpcd reload >/dev/null 2>&1
/etc/init.d/ytbypass enable

if [ "$NOSTART" = 1 ]; then
	say "Установлено. Запуск пропущен (--no-start): /etc/init.d/ytbypass start"
	exit 0
fi

say "Запускаю"
/etc/init.d/ytbypass restart
sleep 4

# проверка цепочки DNS -> nftset
nslookup youtube.com 127.0.0.1 >/dev/null 2>&1
sleep 1
ST=$(/usr/bin/ytbypass status 2>/dev/null)
show() { # ключ, описание
	if [ "$(jsonfilter -s "$ST" -e "@.$1" 2>/dev/null)" = "true" ]; then
		printf '  \033[32m[ok]\033[0m %s\n' "$2"
	else
		printf '  \033[31m[--]\033[0m %s\n' "$2"
	fi
}
echo
say "Состояние:"
show byedpi         "ByeDPI (ciadpi)"
show hev            "hev-socks5-tunnel"
show tun            "интерфейс ytb0"
show nft            "правила nftables"
show route          "policy routing"
show dns            "dnsmasq -> nftset"
show fw             "firewall forward"
IPS=$(jsonfilter -s "$ST" -e '@.ips4' 2>/dev/null)
echo "  IP youtube.com в наборе после тестового резолва: ${IPS:-0}"

cat <<MSG

Готово. Веб-интерфейс: LuCI -> Службы -> YouTube Bypass.
Проверка: откройте YouTube на устройстве в LAN (DNS — роутер), затем на роутере:
  ytbypass status       состояние
  ytbypass list         IP, попавшие в наборы
  logread -e ytbypass   логи

Если клиент уже держал IP YouTube в DNS-кэше — перезапустите браузер / переподключите Wi-Fi.
Удаление: sh install.sh --uninstall
MSG
