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
/www/luci-static/resources/view/ytbypass /www/luci-static/resources/ytbypass /var/etc/ytbypass /var/run/ytbypass.started /tmp/ytbypass-test
/etc/ytbypass /lib/upgrade/keep.d/ytbypass"

do_uninstall() {
	say "Останавливаю и удаляю YouTube Bypass"
	[ -x /usr/bin/ytbypass ] && /usr/bin/ytbypass test stop >/dev/null 2>&1
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
	# стратегия обхода DPI, подбирается под провайдера (вкладка «Тест стратегий»)
	option byedpi_opts '-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1'
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
	  | sort -u \
	  | awk '
		{ name[NR] = $0; have[$0] = 1 }
		END {
			for (i = 1; i <= NR; i++) {
				n = split(name[i], p, ".")
				suf = ""; redundant = 0
				# proper-суффиксы справа налево: если родительский домен уже в списке — запись избыточна
				for (j = n; j >= 2; j--) {
					suf = (suf == "") ? p[j] : p[j] "." suf
					if (suf in have) { redundant = 1; break }
				}
				if (!redundant) print name[i]
			}
		}'
}

dns_remove() {
	local conf
	conf="$(dnsmasq_confdir)/ytbypass.conf"
	[ -f "$conf" ] || return 0
	rm -f "$conf"
	/etc/init.d/dnsmasq restart >/dev/null 2>&1
}

# Записать nftset-правила для dnsmasq; dnsmasq перезапускается только при изменении.
# Строка конфига dnsmasq не может быть длиннее ~1 КБ (иначе dnsmasq вообще не запустится),
# поэтому домены разбиваются на несколько строк nftset= по <= 800 байт.
dns_apply() {
	local ipv6="$1" conf domains suffix new old
	conf="$(dnsmasq_confdir)/ytbypass.conf"
	domains=$(collect_domains)
	if [ -z "$domains" ]; then
		dns_remove
		return 0
	fi
	suffix="4#inet#${NFT_TABLE}#yt4"
	[ "$ipv6" = "1" ] && suffix="$suffix,6#inet#${NFT_TABLE}#yt6"
	new=$(printf '%s\n' "$domains" | awk -v suffix="$suffix" -v max=800 '
		{
			if (cur != "" && length("nftset=/" cur "/" $0 "/" suffix) > max) {
				print "nftset=/" cur "/" suffix
				cur = ""
			}
			cur = (cur == "") ? $0 : cur "/" $0
		}
		END { if (cur != "") print "nftset=/" cur "/" suffix }')
	old=$(cat "$conf" 2>/dev/null)
	if [ "$old" != "$new" ]; then
		mkdir -p "$(dirname "$conf")"
		printf '%s\n' "$new" > "$conf"
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
	byedpi_opts=$(byedpi_opts_clean "$byedpi_opts")
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
	mkdir -p "$R/lib/upgrade/keep.d"
	cat > "$R/lib/upgrade/keep.d/ytbypass" <<'YTB_FILE_END_7f3a9c'
/etc/ytbypass/
YTB_FILE_END_7f3a9c
	chmod 644 "$R/lib/upgrade/keep.d/ytbypass"
	mkdir -p "$R/usr/bin"
	cat > "$R/usr/bin/ytbypass" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Вспомогательная утилита YouTube Bypass (используется LuCI и для отладки)
#   ytbypass status   — состояние в JSON
#   ytbypass flush    — очистить наборы IP (клиентам нужно заново резолвить домены)
#   ytbypass list     — показать IP в наборах
#   ytbypass diag [IP|MAC|имя] [сек] — диагностика клиента: куда идёт его DNS и :443-трафик (без аргумента — список клиентов)
#   ytbypass test …   — тест стратегий ByeDPI (start|stop|status|log|results|clear|list)
#   ytbypass test list get|set|reset strategies|domains [текст] — свои списки для теста
#   ytbypass set-strategy "<параметры ciadpi>" — записать стратегию и перезапустить службу

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
diag)
	arg="$2"; secs="${3:-20}"
	LEASES="${YTB_LEASES:-/tmp/dhcp.leases}"
	CT="${YTB_CT:-/proc/net/nf_conntrack}"
	case "$secs" in ''|*[!0-9]*) secs=20 ;; esac

	echo "=== YouTube Bypass: диагностика ==="
	"$0" status
	echo
	echo "--- счётчики nft (растут, когда трафик попадает под правила) ---"
	{ nft list chain inet "$NFT_TABLE" prerouting; nft list chain inet "$NFT_TABLE" forward; } 2>/dev/null \
		| grep counter | sed 's/^[[:space:]]*//'
	echo
	echo "--- какие DNS раздаются клиентам по DHCP ---"
	uci -q show dhcp | grep -E 'dhcp_option|\.dns=' || echo "своих dhcp_option/dns нет (клиенты получают DNS роутера)"
	echo "--- IPv6: маршрут по умолчанию: $(ip -6 route show default 2>/dev/null | head -n 1)"

	router_addrs=$(ip -o addr show 2>/dev/null | awk '{print $4}' | sed 's#/.*##' | tr '\n' ' ')
	lan_ip=$(uci -q get network.lan.ipaddr | sed 's#/.*##')
	[ -n "$lan_ip" ] && router_addrs="$router_addrs $lan_ip"

	list_leases() {
		echo "--- клиенты в DHCP ---"
		if [ -s "$LEASES" ]; then
			awk '{printf "  %-16s %-18s %s\n", $3, $2, $4}' "$LEASES"
		else
			echo "  (файл аренд пуст — смотрите IP в LuCI: Состояние → Обзор)"
		fi
	}

	if [ -z "$arg" ]; then
		echo
		list_leases
		echo
		echo "Запустите: ytbypass diag <IP|MAC|имя телефона> [секунд, по умолчанию 20]"
		exit 0
	fi

	# имя/MAC -> IP через аренды DHCP
	client="$arg"
	if ! printf '%s' "$arg" | grep -Eq '^[0-9]+(\.[0-9]+){3}$'; then
		found=$(grep -i -- "$arg" "$LEASES" 2>/dev/null)
		n=$(printf '%s\n' "$found" | grep -c .)
		if [ "$n" -eq 0 ]; then
			echo; echo "«$arg» не найден в DHCP-арендах."; list_leases; exit 0
		elif [ "$n" -gt 1 ]; then
			echo; echo "«$arg» подходит нескольким клиентам — уточните:"; list_leases; exit 0
		fi
		client=$(printf '%s\n' "$found" | awk '{print $3}')
	fi
	case " $router_addrs " in
		*" $client "*)
			echo
			echo "$client — это адрес самого РОУТЕРА. Нужен IP телефона:"
			list_leases
			exit 0 ;;
	esac

	# все адреса устройства: IPv4 + его глобальные IPv6 (по MAC)
	mac=$(ip neigh show 2>/dev/null | awk -v ip="$client" '$1==ip {for(i=1;i<=NF;i++) if($i=="lladdr") print $(i+1)}' | head -n 1)
	ips="$client"
	[ -n "$mac" ] && ips="$ips $(ip -6 neigh show 2>/dev/null | awk -v m="$mac" 'tolower($0) ~ tolower(m) {print $1}' | grep -v '^fe80' | tr '\n' ' ')"
	echo
	echo "=== клиент: $ips (MAC: ${mac:-не найден}) ==="
	echo ">>> Собираю данные ${secs} с. ОТКРОЙТЕ YouTube НА ТЕЛЕФОНЕ (перезапустите приложение / обновите страницу) <<<"

	raw="/tmp/ytb-ct.$$"; out="/tmp/ytb-diag.$$"; ins="/tmp/ytb-ins.$$"
	: > "$raw"; : > "$ins"
	i=0
	while [ "$i" -lt "$secs" ]; do
		cat "$CT" >> "$raw" 2>/dev/null
		i=$((i + 1))
		[ "$i" -lt "$secs" ] && sleep 1
	done

	# каждый поток считаем один раз; «в туннеле», если у него хоть раз была метка
	awk -v ips=" $ips " '
	{
		proto=$3; src=""; dst=""; sport=""; dport=""; mark=0
		for (i=1;i<=NF;i++) {
			if (src=="" && $i ~ /^src=/) src=substr($i,5)
			else if (dst=="" && $i ~ /^dst=/) dst=substr($i,5)
			else if (sport=="" && $i ~ /^sport=/) sport=substr($i,7)
			else if (dport=="" && $i ~ /^dport=/) dport=substr($i,7)
			else if ($i ~ /^mark=/) mark=substr($i,6)+0
		}
		if (index(ips, " " src " ") == 0) next
		key=proto " " src " " sport " " dst " " dport
		if (!(key in P)) { P[key]=proto; D[key]=dst; Q[key]=dport; M[key]=0 }
		if (int(mark/65536)%2==1) M[key]=1
	}
	END {
		for (k in P) {
			if (Q[k]=="53" || Q[k]=="853") c["DNS " P[k] " " D[k] ":" Q[k]]++
			else if (Q[k]=="443") c["443 " P[k] " " (M[k] ? "tunnel" : "direct") " " D[k]]++
		}
		for (k in c) print k, c[k]
	}' "$raw" 2>/dev/null | sort > "$out"

	echo
	echo "--- DNS-запросы клиента (куда он реально их шлёт) ---"
	dns_ok=0; dns_bad=0
	if grep -q '^DNS' "$out"; then
		while read -r _ proto target n; do
			host="${target%:*}"; port="${target##*:}"
			if [ "$port" = "853" ]; then
				who="DNS-over-TLS (Частный DNS) — МИМО роутера"; dns_bad=1
			elif case " $router_addrs " in *" $host "*) true ;; *) false ;; esac; then
				who="роутер (ок)"; dns_ok=1
			else
				who="НЕ роутер — набор для этого клиента не заполнится"; dns_bad=1
			fi
			echo "  $proto $target x$n — $who"
		done <<EOF_DNS
$(grep '^DNS' "$out")
EOF_DNS
	else
		echo "  DNS-запросов не было (клиент мог отвечать из кэша или использует DoH по :443)"
	fi

	echo "--- соединения клиента на :443 ---"
	tcp_t=$(awk '$1=="443" && $2=="tcp" && $3=="tunnel" {s+=$NF} END{print s+0}' "$out")
	tcp_d=$(awk '$1=="443" && $2=="tcp" && $3=="direct" {s+=$NF} END{print s+0}' "$out")
	udp_n=$(awk '$1=="443" && $2=="udp" {s+=$NF} END{print s+0}' "$out")
	echo "  tcp: через туннель — $tcp_t, напрямую — $tcp_d;  udp/443 (QUIC): $udp_n"

	echo "--- топ прямых TCP/443 (нет ли среди них YouTube/Google?) ---"
	grep '^443 tcp direct' "$out" | awk '{printf "%09d %s\n", 999999999-$NF, $0}' | sort | head -n 8 | cut -d' ' -f2- | while read -r _ _ _ dst n; do
		fam=yt4; case "$dst" in *:*) fam=yt6 ;; esac
		if nft get element inet "$NFT_TABLE" "$fam" "{ $dst }" >/dev/null 2>&1; then
			echo "  $dst x$n — в наборе, но трафик не помечен" | tee -a "$ins"
		else
			echo "  $dst x$n — не в наборе"
		fi
	done
	in_set=$(grep -c . "$ins")

	echo
	found_any=0
	if [ "$dns_bad" -eq 1 ]; then
		found_any=1
		if [ "$dns_ok" -eq 0 ]; then
			echo "ВЫВОД: телефон шлёт DNS мимо роутера (Частный DNS / DoT / внешний DNS) — набор не заполняется, YouTube идёт напрямую."
		else
			echo "ВЫВОД: часть DNS-запросов телефона идёт мимо роутера (Частный DNS / DoT / внешний DNS) — для таких имён набор не заполнится."
		fi
		echo "       Отключите «Частный DNS» и «Безопасный DNS» в Chrome, уберите статический DNS/VPN/AdGuard и переподключите Wi-Fi."
	fi
	if [ "$in_set" -gt 0 ]; then
		found_any=1
		echo "ВЫВОД: есть соединения на IP из набора, но без метки — пришлите этот вывод целиком."
	fi
	if [ "$tcp_t" -gt 0 ]; then
		found_any=1
		echo "ИНФО: часть трафика YouTube от телефона идёт через туннель — маршрутизация работает."
		[ "$dns_bad" -eq 0 ] && [ "$in_set" -eq 0 ] && \
			echo "      Если видео всё равно не грузится — стратегия ByeDPI (вкладка «Тест стратегий») или домены, которых нет в списке."
	fi
	if [ "$tcp_t" -eq 0 ] && [ "$tcp_d" -eq 0 ] && [ "$dns_ok" -eq 0 ] && [ "$dns_bad" -eq 0 ]; then
		found_any=1
		echo "ВЫВОД: от этого клиента не было ни DNS, ни :443-трафика. Проверьте IP/MAC, что телефон в этой сети, и откройте YouTube во время сбора."
	fi
	[ "$found_any" -eq 1 ] || echo "ВЫВОД: однозначно определить не удалось — пришлите этот вывод целиком."
	rm -f "$raw" "$out" "$ins"
	;;
test)
	shift
	exec /usr/libexec/ytbypass/test.sh "$@"
	;;
set-strategy)
	opts="$2"
	if [ -z "$opts" ] || [ "$(printf '%s' "$opts" | wc -l)" -gt 0 ]; then
		echo '{"error":"пустая или многострочная стратегия"}'
		exit 0
	fi
	uci set ytbypass.main.byedpi_opts="$opts" && uci commit ytbypass
	/etc/init.d/ytbypass restart >/dev/null 2>&1
	echo '{"ok":true}'
	;;
*)
	echo "usage: ytbypass status|flush|list|diag|test|set-strategy" >&2
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

# путь к бинарнику ByeDPI
find_byedpi() {
	local b
	for b in /usr/bin/ciadpi /usr/bin/byedpi; do
		[ -x "$b" ] && { echo "$b"; return 0; }
	done
	command -v ciadpi
}

# Параметры ByeDPI приходят из UCI как строка, а раскрываются без eval (по пробелам).
# Кавычки вроде -n "google.com" при этом остались бы в аргументе буквально,
# поэтому их убираем: у аргументов ciadpi пробелов внутри не бывает.
byedpi_opts_clean() {
	printf '%s' "$1" | tr -d "\"'" | tr '\n\r\t' '   ' | sed 's/^ *//; s/ *$//; s/  */ /g'
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

set_mark_stmt="counter ct mark set ct mark | $MARK meta mark set meta mark | $MARK"

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
		udp dport 443 ip daddr @yt4 counter reject
		udp dport 443 ip6 daddr @yt6 counter reject
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
	mkdir -p "$R/usr/libexec/ytbypass"
	cat > "$R/usr/libexec/ytbypass/test.sh" <<'YTB_FILE_END_7f3a9c'
#!/bin/sh
# Тест стратегий ByeDPI.
#   ytbypass test start | stop | status | log | results | clear
#
# Списки стратегий и доменов: свои (/etc/ytbypass/, переживают обновление) или встроенные.
#   ytbypass test list get|set|reset strategies|domains [текст]
#
# Каждая стратегия запускается во ВРЕМЕННОМ экземпляре ciadpi на отдельном порту,
# домены проверяются через него по curl --socks5. Боевой сервис и трафик клиентов
# не затрагиваются, конфигурация не меняется. Сначала контрольный замер без обхода.

. /lib/functions.sh
. /usr/libexec/ytbypass/common.sh

TEST_DIR=/tmp/ytbypass-test
PIDF="$TEST_DIR/job.pid"
LOGF="$TEST_DIR/job.log"
RES="$TEST_DIR/results.txt"
RAW="$TEST_DIR/results.raw"
STOP="$TEST_DIR/stop"
CPID="$TEST_DIR/ciadpi.pid"
USER_DIR=/etc/ytbypass
STRATS_DEFAULT=/usr/share/ytbypass/strategies.txt
DOMS_DEFAULT=/usr/share/ytbypass/test-domains.txt
PORT_BASE=22000
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) curl/8.0'
TAB=$(printf '\t')

is_running() {
	[ -f "$PIDF" ] && kill -0 "$(cat "$PIDF" 2>/dev/null)" 2>/dev/null
}

count_lines() { # файл -> число строк без пустых и комментариев
	sed 's/#.*//' "$1" 2>/dev/null | tr -d '\r' | grep -c '[^[:space:]]'
}

# ---------------------------------------------------------------- списки
# имя файла у пользователя
list_name() {
	case "$1" in
		strategies) echo strategies.txt ;;
		domains)    echo test-domains.txt ;;
	esac
}

# путь действующего списка: свой (если есть и не пуст), иначе встроенный
list_file() {
	local nm
	nm=$(list_name "$1")
	if [ -n "$nm" ] && [ -s "$USER_DIR/$nm" ]; then
		echo "$USER_DIR/$nm"
	else
		case "$1" in
			strategies) echo "$STRATS_DEFAULT" ;;
			domains)    echo "$DOMS_DEFAULT" ;;
		esac
	fi
}

list_is_custom() { # kind
	local nm
	nm=$(list_name "$1")
	[ -n "$nm" ] && [ -s "$USER_DIR/$nm" ]
}

json_esc() {
	printf '%s' "$1" | tr -d '\000-\037' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# домены: по одному в строке; допускаем ссылки, *.домен, запятые/пробелы; комментарии (#) сохраняем.
# Первая некорректная запись пишется в файл $1.
norm_domains() {
	awk -v badf="$1" '
	{
		gsub(/\r/, "")
		line = $0
		sub(/^[ \t]+/, "", line); sub(/[ \t]+$/, "", line)
		if (line == "") next
		if (substr(line, 1, 1) == "#") { print line; next }
		sub(/#.*/, "", line)
		n = split(line, tok, /[ \t,;]+/)
		for (i = 1; i <= n; i++) {
			d = tolower(tok[i])
			if (d == "") continue
			sub(/^[a-z][a-z0-9+.-]*:\/\//, "", d)
			sub(/[\/?#].*$/, "", d)
			sub(/^\*?\./, "", d)
			if (d ~ /^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/ && index(d, ".") > 0) {
				if (!(d in seen)) { seen[d] = 1; print d }
			} else if (!bad) { bad = 1; print tok[i] > badf }
		}
	}'
}

# стратегии: по одной в строке, пробелы схлопываются, дубли убираются, комментарии (#) сохраняем
norm_strategies() {
	awk '
	{
		gsub(/\r/, ""); gsub(/[ \t]+/, " ")
		line = $0; sub(/^ /, "", line); sub(/ $/, "", line)
		if (line == "") next
		if (substr(line, 1, 1) == "#") { print line; next }
		if (!(line in seen)) { seen[line] = 1; print line }
	}'
}

cmd_list() {
	local action="$1" kind="$2" text="$3" nm tmp bad n
	nm=$(list_name "$kind")
	if [ -z "$nm" ]; then
		echo '{"error":"неизвестный список"}'
		return 0
	fi
	case "$action" in
	get)
		local f
		f=$(list_file "$kind")
		[ -f "$f" ] && cat "$f"
		;;
	set)
		if is_running; then
			echo '{"error":"тест выполняется — остановите его перед сохранением списка"}'
			return 0
		fi
		mkdir -p "$TEST_DIR"
		tmp="$TEST_DIR/list.$$"; bad="$TEST_DIR/bad.$$"; : > "$bad"
		if [ "$kind" = "domains" ]; then
			printf '%s\n' "$text" | norm_domains "$bad" > "$tmp"
		else
			printf '%s\n' "$text" | norm_strategies > "$tmp"
		fi
		if [ -s "$bad" ]; then
			printf '{"error":"Некорректный домен: %s"}\n' "$(json_esc "$(head -n 1 "$bad")")"
			rm -f "$tmp" "$bad"
			return 0
		fi
		rm -f "$bad"
		n=$(count_lines "$tmp")
		if [ "${n:-0}" -le 0 ]; then
			echo '{"error":"список пуст — чтобы вернуть встроенный, нажмите «Сбросить к встроенному»"}'
			rm -f "$tmp"
			return 0
		fi
		mkdir -p "$USER_DIR"
		mv "$tmp" "$USER_DIR/$nm"
		printf '{"ok":true,"count":%s,"custom":true}\n' "$n"
		;;
	reset)
		if is_running; then
			echo '{"error":"тест выполняется — остановите его перед сбросом списка"}'
			return 0
		fi
		rm -f "$USER_DIR/$nm"
		printf '{"ok":true,"count":%s,"custom":false}\n' "$(count_lines "$(list_file "$kind")")"
		;;
	*)
		echo '{"error":"неизвестное действие"}'
		;;
	esac
	return 0
}

# ---------------------------------------------------------------- управление
cmd_start() {
	if is_running; then
		echo '{"started":true,"already_running":true}'
		return 0
	fi
	command -v curl >/dev/null 2>&1 || { echo '{"error":"не установлен curl (apk add curl / opkg install curl)"}'; return 0; }
	[ -n "$(find_byedpi)" ] || { echo '{"error":"не найден ciadpi (пакет byedpi)"}'; return 0; }
	mkdir -p "$TEST_DIR"
	rm -f "$STOP"
	: > "$LOGF"
	# полностью отвязываем от stdin/stdout, иначе rpcd будет ждать завершения
	( "$0" run >>"$LOGF" 2>&1; echo "__DONE__ $?" >>"$LOGF" ) >/dev/null 2>&1 </dev/null &
	echo $! > "$PIDF"
	echo '{"started":true}'
}

cmd_stop() {
	if ! is_running; then
		echo '{"error":"тест не запущен"}'
		return 0
	fi
	touch "$STOP"
	[ -f "$CPID" ] && kill "$(cat "$CPID" 2>/dev/null)" 2>/dev/null
	echo '{"ok":true}'
}

cmd_status() {
	local running=false has=false cu=false rc=""
	is_running && running=true
	[ -s "$RES" ] && has=true
	command -v curl >/dev/null 2>&1 && cu=true
	[ -f "$LOGF" ] && rc=$(grep '^__DONE__' "$LOGF" | tail -n 1 | awk '{print $2}')
	local sc=false dc=false
	list_is_custom strategies && sc=true
	list_is_custom domains && dc=true
	printf '{"running":%s,"has_results":%s,"curl":%s,"strategies":%s,"domains":%s,"strategies_custom":%s,"domains_custom":%s,"rc":"%s"}\n' \
		"$running" "$has" "$cu" "$(count_lines "$(list_file strategies)")" "$(count_lines "$(list_file domains)")" "$sc" "$dc" "$rc"
}

cmd_log() {
	[ -f "$LOGF" ] && tail -n 400 "$LOGF" | grep -v '^__DONE__'
	return 0
}

cmd_results() {
	[ -s "$RES" ] && cat "$RES"
	return 0
}

cmd_clear() {
	if is_running; then
		echo '{"error":"тест выполняется"}'
		return 0
	fi
	rm -f "$RES" "$RAW"
	echo '{"ok":true}'
}

# ---------------------------------------------------------------- движок
# check_url ЗАПИСЬ OKFILE LOGFILE [socks host:port]
check_url() {
	local entry="$1" okfile="$2" logfile="$3" proxy="$4" host url rc
	host="${entry%%|*}"
	url="${entry#*|}"
	if [ -n "$proxy" ]; then
		curl -4 -sL --socks5 "$proxy" --connect-timeout 4 --max-time 6 --speed-time 3 --speed-limit 1 \
			--range 0-65535 -A "$UA" -o /dev/null "$url" </dev/null >/dev/null 2>&1
	else
		curl -4 -sL --connect-timeout 4 --max-time 6 --speed-time 3 --speed-limit 1 \
			--range 0-65535 -A "$UA" -o /dev/null "$url" </dev/null >/dev/null 2>&1
	fi
	rc=$?
	if [ "$rc" -eq 0 ]; then
		echo 1 >> "$okfile"
		echo "[ OK ] $host" >> "$logfile"
	else
		echo "[FAIL] $host" >> "$logfile"
	fi
}

# check_all ФАЙЛ_URL LOGFILE [socks] -> "ok total"
check_all() {
	local urls="$1" logfile="$2" proxy="$3" okf run=0 total=0 ok entry
	okf="$TEST_DIR/ok.$$"
	: > "$okf"
	: > "$logfile"
	while IFS= read -r entry; do
		[ -n "$entry" ] || continue
		[ -f "$STOP" ] && break
		total=$((total + 1))
		check_url "$entry" "$okf" "$logfile" "$proxy" &
		run=$((run + 1))
		if [ "$run" -ge "$PARALLEL" ]; then
			wait
			run=0
		fi
	done < "$urls"
	wait
	ok=$(wc -l < "$okf" | tr -d ' ')
	rm -f "$okf"
	echo "$ok $total"
}

cleanup() {
	[ -f "$CPID" ] && kill "$(cat "$CPID" 2>/dev/null)" 2>/dev/null
	rm -f "$CPID"
}

cmd_run() {
	local BIN cand keys urls line k opts port idx total ntot res ok tot cok ctot cpid skipped=0 best

	set -f      # параметры ciadpi раскрываем по пробелам без glob
	trap cleanup EXIT
	trap 'exit 130' INT TERM

	config_load ytbypass
	config_get PARALLEL main test_parallel 8
	config_get CUR main byedpi_opts ""
	case "$PARALLEL" in ''|*[!0-9]*) PARALLEL=8 ;; esac
	[ "$PARALLEL" -ge 1 ] || PARALLEL=8

	BIN=$(find_byedpi)
	[ -n "$BIN" ] || { echo "ОШИБКА: ciadpi не найден"; exit 1; }
	command -v curl >/dev/null 2>&1 || { echo "ОШИБКА: не установлен curl"; exit 1; }

	mkdir -p "$TEST_DIR"
	rm -f "$STOP"
	cand="$TEST_DIR/candidates.txt"
	keys="$TEST_DIR/keys.txt"
	urls="$TEST_DIR/urls.txt"
	: > "$cand"; : > "$keys"; : > "$RAW"

	echo "==> Собираем стратегии для теста"
	# текущая стратегия идёт первой, затем список; дубликаты (без учёта кавычек) отбрасываем
	{ printf '%s\n' "$CUR"; cat "$(list_file strategies)"; } | tr -d '\r' | while IFS= read -r line; do
		line=$(printf '%s' "$line" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
		case "$line" in ''|'#'*) continue ;; esac
		k=$(byedpi_opts_clean "$line")
		[ -n "$k" ] || continue
		grep -qxF -- "$k" "$keys" && continue
		echo "$k" >> "$keys"
		echo "$line" >> "$cand"
	done
	total=$(wc -l < "$cand" | tr -d ' ')
	[ "$total" -gt 0 ] || { echo "ОШИБКА: нет стратегий для теста"; exit 1; }

	echo "==> Собираем список доменов"
	tr -d '\r' < "$(list_file domains)" | sed 's/#.*//; s/^[[:space:]]*//; s/[[:space:]]*$//' \
		| grep -E '^[A-Za-z0-9._-]+$' | awk '!s[$0]++' | sed 's#.*#&|https://&/#' > "$urls"
	ntot=$(wc -l < "$urls" | tr -d ' ')
	[ "$ntot" -gt 0 ] || { echo "ОШИБКА: нет доменов для теста"; exit 1; }
	echo "==> Стратегий: $total, доменов: $ntot, параллельно: $PARALLEL"

	echo "==> Контрольный тест: без обхода"
	res=$(check_all "$urls" "$TEST_DIR/log_control.txt" "")
	if [ -f "$STOP" ]; then
		echo "==> Тест остановлен на контрольном замере, результатов нет"
		rm -f "$STOP"
		return 0
	fi
	cok=${res% *}; ctot=${res#* }
	echo "==> Результат: $cok/$ctot"

	idx=0
	while IFS= read -r line; do
		[ -f "$STOP" ] && break
		idx=$((idx + 1))
		opts=$(byedpi_opts_clean "$line")
		port=$((PORT_BASE + idx))
		echo "==> [$idx/$total] $line"
		"$BIN" -i 127.0.0.1 -p "$port" $opts >/dev/null 2>&1 </dev/null &
		cpid=$!
		echo "$cpid" > "$CPID"
		sleep 1
		if ! kill -0 "$cpid" 2>/dev/null; then
			echo "    пропуск: ciadpi не запустился с этими параметрами"
			skipped=$((skipped + 1))
			continue
		fi
		res=$(check_all "$urls" "$TEST_DIR/log_$idx.txt" "127.0.0.1:$port")
		kill "$cpid" 2>/dev/null
		wait "$cpid" 2>/dev/null
		rm -f "$CPID"
		if [ -f "$STOP" ]; then
			echo "    прервано — эта стратегия в результаты не входит"
			break
		fi
		ok=${res% *}; tot=${res#* }
		ok=${ok:-0}
		echo "    результат: $ok/$tot"
		# ключ сортировки: (999999-ok) и номер — при обычном лексикографическом sort получается
		# «больше ok выше, при равенстве раньше в списке». sort -k/-n в busybox OpenWrt может не работать.
		printf '%06d\t%06d\t%s\t%s\t%s\n' "$((999999 - ok))" "$idx" "$ok" "$tot" "$line" >> "$RAW"
	done < "$cand"

	if [ -f "$STOP" ]; then
		echo "==> Тест остановлен пользователем, показываю то, что успели проверить"
		rm -f "$STOP"
	else
		echo "==> Тест завершён"
	fi
	[ "$skipped" -gt 0 ] && echo "==> Пропущено стратегий (не запустились): $skipped"

	# итог: по убыванию числа доступных доменов, при равенстве — в порядке списка
	{
		echo "Контрольный тест (без обхода) → $cok/$ctot"
		sort "$RAW" | while IFS="$TAB" read -r _ _ ok tot line; do
			echo "$line → $ok/$tot"
		done
	} > "$RES"

	echo "==> Результаты"
	cat "$RES"
	best=$(sed -n '2p' "$RES")
	[ -n "$best" ] && echo "==> Лучшая стратегия: $best"
	echo "==> Основной сервис и его настройки не менялись. Применить стратегию можно кнопкой на вкладке «Тест стратегий»."
	return 0
}

case "$1" in
	start)   cmd_start ;;
	stop)    cmd_stop ;;
	status)  cmd_status ;;
	log)     cmd_log ;;
	results) cmd_results ;;
	clear)   cmd_clear ;;
	list)    shift; cmd_list "$@" ;;
	run)     cmd_run ;;
	*) echo "usage: ytbypass test start|stop|status|log|results|clear|list" >&2; exit 1 ;;
esac
exit 0
YTB_FILE_END_7f3a9c
	chmod 755 "$R/usr/libexec/ytbypass/test.sh"
	mkdir -p "$R/usr/share/luci/menu.d"
	cat > "$R/usr/share/luci/menu.d/luci-app-ytbypass.json" <<'YTB_FILE_END_7f3a9c'
{
	"admin/services/ytbypass": {
		"title": "YouTube Bypass",
		"order": 60,
		"action": {
			"type": "alias",
			"path": "admin/services/ytbypass/settings"
		},
		"depends": {
			"acl": [ "luci-app-ytbypass" ],
			"uci": { "ytbypass": true }
		}
	},
	"admin/services/ytbypass/settings": {
		"title": "Настройки",
		"order": 10,
		"action": {
			"type": "view",
			"path": "ytbypass/main"
		}
	},
	"admin/services/ytbypass/test": {
		"title": "Тест стратегий",
		"order": 20,
		"action": {
			"type": "view",
			"path": "ytbypass/test"
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
# Домены YouTube и связанных сервисов Google (поддомены подхватываются автоматически).
# Список объединяется с «Дополнительными доменами» из настроек. Вложенные записи
# (например, i.ytimg.com при наличии ytimg.com) сервис сам отбрасывает как избыточные.
android.clients.google.com
beacons.gvt2.com
cdn.youtube.com
connectivitycheck.gstatic.com
fonts.googleapis.com
fonts.gstatic.com
ggpht.com
googleapis.com
googleplay.com
googleusercontent.com
googlevideo.com
gvt1.com
i.ytimg.com
i9.ytimg.com
jnn-pa.googleapis.com
kids.youtube.com
lh3.googleusercontent.com
m.youtube.com
manifest.googlevideo.com
music.youtube.com
nhacmp3youtube.com
play-fe.googleapis.com
play-games.googleusercontent.com
play-lh.googleusercontent.com
play.google.com
play.googleapis.com
prod-lt-playstoregatewayadapter-pa.googleapis.com
returnyoutubedislikeapi.com
s.ytimg.com
signaler-pa.youtube.com
studio.youtube.com
tv.youtube.com
wide-youtube.l.google.com
withyoutube.com
youtu.be
youtube-nocookie.com
youtube-ui.l.google.com
youtube.ae
youtube.al
youtube.am
youtube.at
youtube.az
youtube.ba
youtube.be
youtube.bg
youtube.bh
youtube.bo
youtube.by
youtube.ca
youtube.cat
youtube.ch
youtube.cl
youtube.co
youtube.co.ae
youtube.co.at
youtube.co.cr
youtube.co.hu
youtube.co.id
youtube.co.il
youtube.co.in
youtube.co.jp
youtube.co.ke
youtube.co.kr
youtube.co.ma
youtube.co.nz
youtube.co.th
youtube.co.tz
youtube.co.ug
youtube.co.uk
youtube.co.ve
youtube.co.za
youtube.co.zw
youtube.com
youtube.com.ar
youtube.com.au
youtube.com.az
youtube.com.bd
youtube.com.bh
youtube.com.bo
youtube.com.br
youtube.com.by
youtube.com.co
youtube.com.do
youtube.com.ec
youtube.com.ee
youtube.com.eg
youtube.com.es
youtube.com.gh
youtube.com.gr
youtube.com.gt
youtube.com.hk
youtube.com.hn
youtube.com.hr
youtube.com.jm
youtube.com.jo
youtube.com.kw
youtube.com.lb
youtube.com.lv
youtube.com.ly
youtube.com.mk
youtube.com.mt
youtube.com.mx
youtube.com.my
youtube.com.ng
youtube.com.ni
youtube.com.om
youtube.com.pa
youtube.com.pe
youtube.com.ph
youtube.com.pk
youtube.com.pt
youtube.com.py
youtube.com.qa
youtube.com.ro
youtube.com.sa
youtube.com.sg
youtube.com.sv
youtube.com.tn
youtube.com.tr
youtube.com.tw
youtube.com.ua
youtube.com.uy
youtube.com.ve
youtube.cr
youtube.cz
youtube.de
youtube.dk
youtube.ee
youtube.es
youtube.fi
youtube.fr
youtube.ge
youtube.googleapis.com
youtube.gr
youtube.gt
youtube.hk
youtube.hr
youtube.hu
youtube.ie
youtube.in
youtube.iq
youtube.is
youtube.it
youtube.jo
youtube.jp
youtube.kr
youtube.kz
youtube.la
youtube.lk
youtube.lt
youtube.lu
youtube.lv
youtube.ly
youtube.ma
youtube.md
youtube.me
youtube.mk
youtube.mn
youtube.mx
youtube.my
youtube.ng
youtube.ni
youtube.nl
youtube.no
youtube.pa
youtube.pe
youtube.ph
youtube.pk
youtube.pl
youtube.pr
youtube.pt
youtube.qa
youtube.ro
youtube.rs
youtube.ru
youtube.sa
youtube.se
youtube.sg
youtube.si
youtube.sk
youtube.sn
youtube.soy
youtube.sv
youtube.tn
youtube.tv
youtube.ua
youtube.ug
youtube.uy
youtube.vn
youtubeeducation.com
youtubeembeddedplayer.googleapis.com
youtubefanfest.com
youtubegaming.com
youtubego.co.id
youtubego.co.in
youtubego.com
youtubego.com.br
youtubego.id
youtubego.in
youtubei.googleapis.com
youtubei.youtube.com
youtubekids.com
youtubemobilesupport.com
yt-video-upload.l.google.com
yt.be
yt3.ggpht.com
yt3.googleusercontent.com
yt4.ggpht.com
ytimg.com
ytimg.l.google.com
yting.com
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/ytbypass/domains.list"
	mkdir -p "$R/usr/share/ytbypass"
	cat > "$R/usr/share/ytbypass/strategies.txt" <<'YTB_FILE_END_7f3a9c'
-f-200 -Qr -s3:5+sm -a1 -As -d1 -s4+sm -s8+sh -f-300 -d6+sh -a1 -At,r,s -o2 -f-30 -As -r5 -Mh -r6+sh -f-250 -s2:7+s -s3:6+sm -a1 -At,r,s -s3:5+sm -s6+s -s7:9+s -q30+sm -a1
-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1
-q2 -s2 -s3+s -r3 -s4 -r4 -s5+s -r5+s -s6 -s7+s -r8 -s9+s -Qr -Mh,d,r -a1 -At,r -s2+s -r2 -d2 -s3 -r3 -r4 -s4 -d5+s -r5 -d6 -s7+s -d7 -a1
-o1 -d1 -a1 -At,r,s -s1 -d1 -s5+s -s10+s -s15+s -s20+s -r1+s -S -a1 -As -s1 -d1 -s5+s -s10+s -s15+s -s20+s -S -a1
-n "google.com" -Qr -f-204 -s1:5+sm -a1 -As -d1 -s3+s -s5+s -q7 -a1 -As -o2 -f-43 -a1 -As -r5 -Mh -s1:5+s -s3:7+sm -a1
-n "google.com" -Qr -f-205 -a1 -As -s1:3+sm -a1 -As -s5:8+sm -a1 -As -d3 -q7 -o2 -f-43 -f-85 -f-165 -r5 -Mh -a1
-d1+s -s50+s -a1 -As -f20 -r2+s -a1 -At -d2 -s1+s -s5+s -s10+s -s15+s -s25+s -s35+s -s50+s -s60+s -a1
-o1 -a1 -At,r,s -f-1 -a1 -At,r,s -d1:11+sm -S -a1 -At,r,s -n "google.com" -Qr -f1 -d1:11+sm -s1:11+sm -S -a1
-d1 -s1 -q1 -a1 -Ar -s5 -o1+s -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -a1
-f1+nme -t6 -a1 -As -n "google.com" -Qr -s1:6+sm -a1 -As -s5:12+sm -a1 -As -d3 -q7 -r6 -Mh -a1
-d1 -s1+s -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -a1
-d1 -s1+s -d1+s -s3+s -d6+s -s12+s -d14+s -s20+s -d24+s -s30+s -a1
-o1 -a1 -At,r,s -f-1 -a1 -Ar,s -o1 -a1 -At -r1+s -f-1 -t6 -a1
-d1 -s1+s -s3+s -s6+s -s9+s -s12+s -s15+s -s20+s -s30+s -a1
-d1 -d3+s -s6+s -d6+s -s7+s -d8+s -s10+s -a1 -t12 -At,s -r3
-f1 -t5 -n "google.com" -q3+h -Qr -f2 -q1 -r1+s -t15 -q1 -o2 -a1
-n "google.com" -d2:5:2+h -f-3 -r2+sm -o2 -o50+s -r2+s -f-4 -a1
-f-1 -Qr -s1+sm -d3+s -s5+sm -o2 -a1 -As -r1+s -d8+s -a1
-r-1+s -o20+sm -s3:7+sm -d5:3+sm -f300+s -Qr -f-1 -a1
-o2 -O4 -s1 -q1 -a1 -Ar -s5 -o1+s -f1+s -r20+s -a1
-o1 -r-5+se -a1 -At,r,s -d1 -n "google.com" -Qr -f-1 -a1
--fake -1 --ttl 8 --split 1+s --disorder 3+s -a1
-n "google.com" -Qr -f6+nr -d2 -d11 -f9+hm -o3 -t7 -a1
-r5+s -s25+s -a1 -At,r,s -s50 -r5+s -s50+s -a1
-d1 -d3+s -s6+s -d9+s -s20+s -d25+s -s30+s -a1
-d9+s -q20+s -s25+s -t5 -a1 -At,r,s -r1+h -a1
-q1+s -s29+s -s30+s -s14+s -o5+s -f-1 -S -a1
-d1 -s1+s -r1+s -e1 -m1 -o1+s -f-1 -t2 -a1
-d1 -o1 -a1 -Ar -o1 -a1 -At -f-1 -r1+s -a1
-d1 -s4 -d8 -s1+s -d5+s -s10+s -d20+s -a1
-f-1 -n "google.com" -Qr -s2+s -r3 -o20 -t4 -a1
-n "google.com" -Qr -d5+sm -f3+sm -o2 -t4 -a1
-o1 -a1 -Ar -q1 -a1 -At -f-1 -r1+s -a1
-q1 -a1 -Ar -o1 -a1 -At -f-1 -r1+s -a1
-s4+sn -r9+s -Qr -n "google.com" -S -a1
-o1 -d1 -r1+s -S -s1+s -d3+s -a1
-q1+s -s29+s -o5+s -f-1 -S -a1
-n "google.com" -Qr -m2 -f-1 -d7 -a1
-d1 -s1+s -r1+s -f-1 -t8 -a1
-o1 -a1 -An -f1+nme -t6 -a1
-n "google.com" -Qr -f-1 -r1+s -a1
-n "google.com" -Qr -d1:3 -f-1 -a1
-s1 -d3+s -a1 -At -r1+s -a1
-f-1 -t8 -n "google.com" -s1+s -a1
-n "google.com" -Qr -d1 -f-1 -a1
-f64+se -n "google.com" -t5 -a1
-o1 -a1 -At,r,s -d1 -a1
-d1+s -o2 -s5 -r5 -a1
-r8 -o2 -s7 -q4+s -a1
-o1 -f-1 -r-5+se -a1
-d6+s -q4+hm -o2 -a1
-s5+s -s35+s -m4 -a1
-f-1+sm -t7 -m2 -a1
-o1 -r-5+se -a1
-o1+s -d3+s -a1
-o1 -s4 -s6 -a1
-q1 -r25+s -a1
-d1 -s3+s -a1
-o3 -d7 -a1
-d7 -s2 -a1
-o1 -a1 -r-5+se
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/ytbypass/strategies.txt"
	mkdir -p "$R/usr/share/ytbypass"
	cat > "$R/usr/share/ytbypass/test-domains.txt" <<'YTB_FILE_END_7f3a9c'
# Google and Youtube
youtu.be
youtube.com
i.ytimg.com
i9.ytimg.com
yt3.ggpht.com
yt4.ggpht.com
googleapis.com
jnn-pa.googleapis.com
googleusercontent.com
signaler-pa.youtube.com
youtubei.googleapis.com
manifest.googlevideo.com
yt3.googleusercontent.com

# Googlevideo
rr1---sn-4axm-n8vs.googlevideo.com
rr1---sn-gvnuxaxjvh-o8ge.googlevideo.com
rr1---sn-ug5onuxaxjvh-p3ul.googlevideo.com
rr1---sn-ug5onuxaxjvh-n8v6.googlevideo.com
rr4---sn-q4flrnsl.googlevideo.com
rr10---sn-gvnuxaxjvh-304z.googlevideo.com
rr14---sn-n8v7kn7r.googlevideo.com
rr16---sn-axq7sn76.googlevideo.com
rr1---sn-8ph2xajvh-5xge.googlevideo.com
rr1---sn-gvnuxaxjvh-5gie.googlevideo.com
rr12---sn-gvnuxaxjvh-bvwz.googlevideo.com
rr5---sn-n8v7knez.googlevideo.com
rr1---sn-u5uuxaxjvhg0-ocje.googlevideo.com
rr2---sn-q4fl6ndl.googlevideo.com
rr5---sn-gvnuxaxjvh-n8vk.googlevideo.com
rr4---sn-jvhnu5g-c35d.googlevideo.com
rr1---sn-q4fl6n6y.googlevideo.com
rr2---sn-hgn7ynek.googlevideo.com
rr1---sn-xguxaxjvh-gufl.googlevideo.com
YTB_FILE_END_7f3a9c
	chmod 644 "$R/usr/share/ytbypass/test-domains.txt"
	mkdir -p "$R/www/luci-static/resources/view/ytbypass"
	cat > "$R/www/luci-static/resources/view/ytbypass/main.js" <<'YTB_FILE_END_7f3a9c'
'use strict';
'require view';
'require form';
'require fs';
'require poll';
'require ui';
'require dom';
'require uci';
'require ytbypass.presets as presets';

var CTL = '/usr/bin/ytbypass';
var INIT = '/etc/init.d/ytbypass';

/* ---- дополнительные домены: по одному в строке ---- */
var DOMAIN_RE = /^[a-z0-9]([a-z0-9._-]*[a-z0-9])?$/;

/* привести введённое к домену: https://Foo.com/path -> foo.com, *.foo.com / .foo.com -> foo.com */
function normDomain(s) {
	return String(s).trim().toLowerCase()
		.replace(/^[a-z][a-z0-9+.-]*:\/\//, '')
		.replace(/[\/?#].*$/, '')
		.replace(/^\*?\./, '');
}

/* текст -> { list: уникальные домены по порядку, bad: некорректные записи } */
function parseDomains(text) {
	var list = [], bad = [], seen = {};
	String(text == null ? '' : text).split(/[\s,;]+/).forEach(function(tok) {
		if (!tok) return;
		var d = normDomain(tok);
		if (!d || d.indexOf('.') < 0 || !DOMAIN_RE.test(d)) { bad.push(tok); return; }
		if (!seen[d]) { seen[d] = true; list.push(d); }
	});
	return { list: list, bad: bad };
}

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

		/* Список с короткими именами — удобно выбирать; полная команда видна в поле ниже */
		o = s.option(form.ListValue, '_preset', _('Готовая стратегия'),
			_('Выберите вариант — его параметры подставятся в поле ниже. ' +
			  'Лучшую под вашего провайдера найдёт вкладка «Тест стратегий».'));
		presets.list.forEach(function(p) { o.value(p.id, p.name); });
		o.value('custom', _('Своя (редактируется в поле ниже)'));
		o.cfgvalue = function(section_id) {
			var p = presets.find(uci.get('ytbypass', section_id, 'byedpi_opts'));
			return p ? p.id : 'custom';
		};
		o.write = function() {};   /* служебное поле, в UCI не пишется */
		o.remove = function() {};
		o.onchange = function(ev, section_id, value) {
			var p = presets.byId(value);
			var ta = this.section.getUIElement(section_id, 'byedpi_opts');
			if (p && ta) ta.setValue(p.opts);
		};

		o = s.option(form.TextValue, 'byedpi_opts', _('Параметры ByeDPI (ciadpi)'),
			_('Командная строка ciadpi одной строкой, переносы для удобства чтения — на экране. ' +
			  'Можно править вручную; список выше тогда переключится на «Своя».'));
		o.rows = 5;
		o.wrap = true;
		o.monospace = true;
		o.default = presets.DEFAULT;
		o.rmempty = false;
		o.validate = function(section_id, value) {
			if (!presets.norm(value))
				return _('Параметры не могут быть пустыми');
			return true;
		};
		/* пробелы и переводы строк схлопываем, кавычки (-n "google.com") сохраняем */
		o.write = function(section_id, value) {
			return form.TextValue.prototype.write.call(this, section_id, presets.norm(value));
		};
		o.onchange = function(ev, section_id, value) {
			var p = presets.find(value);
			var sel = this.section.getUIElement(section_id, '_preset');
			if (sel) sel.setValue(p ? p.id : 'custom');
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
			_('YouTube, googlevideo, ytimg, ggpht и связанные сервисы Google (googleapis, googleusercontent, ' +
			  'gstatic для шрифтов, Google Play). Полный список: /usr/share/ytbypass/domains.list. ' +
			  'Сервисы Google часто делят IP-адреса, поэтому часть трафика Google (не только YouTube) тоже пойдёт через обход, ' +
			  'а QUIC (UDP/443) к этим адресам будет блокироваться.'));
		o.default = '1';
		o.rmempty = false;

		/* Как поле параметров ByeDPI, только уже: один домен на строку. В UCI это list domain. */
		o = s.option(form.TextValue, 'domain', _('Дополнительные домены'),
			_('По одному домену в строке; поддомены подхватываются автоматически. ' +
			  'Добавляются к встроенному списку. Можно вставлять и ссылки — из них берётся домен.'));
		o.rows = 8;
		o.cols = 36;          /* с cols LuCI не растягивает поле на всю ширину */
		/* тема может задавать textarea свой width и игнорировать cols — фиксируем ширину явно */
		o.renderWidget = function() {
			var fix = function(n) {
				var ta = n && n.querySelector ? n.querySelector('textarea') : null;
				if (ta) { ta.style.width = '40ch'; ta.style.maxWidth = '100%'; }
				return n;
			};
			var node = form.TextValue.prototype.renderWidget.apply(this, arguments);
			return (node && typeof node.then === 'function') ? node.then(fix) : fix(node);
		};
		o.wrap = false;
		o.monospace = true;
		o.placeholder = 'example.com\nanother.org';
		o.cfgvalue = function(section_id) {
			var v = uci.get('ytbypass', section_id, 'domain');
			return Array.isArray(v) ? v.join('\n') : (v || '');
		};
		o.validate = function(section_id, value) {
			var r = parseDomains(value);
			if (r.bad.length)
				return _('Некорректный домен: ') + r.bad[0];
			return true;
		};
		o.write = function(section_id, value) {
			var list = parseDomains(value).list;
			return this.map.data.set(this.uciconfig || this.section.uciconfig || this.map.config,
				section_id, this.ucioption || this.option, list.length ? list : null);
		};

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
	mkdir -p "$R/www/luci-static/resources/view/ytbypass"
	cat > "$R/www/luci-static/resources/view/ytbypass/test.js" <<'YTB_FILE_END_7f3a9c'
'use strict';
'require view';
'require fs';
'require poll';
'require ui';
'require uci';
'require dom';
'require ytbypass.presets as presets';

var CTL = '/usr/bin/ytbypass';

/* палитра «терминала» на чёрном фоне */
var C = {
	fg: '#d0d0d0', green: '#4ade80', orange: '#fbbf24', red: '#f87171',
	cyan: '#22d3ee', yellow: '#facc15', gray: '#8b949e', white: '#ffffff'
};
var TERM = 'background:#000;color:' + C.fg + ';font-family:monospace;font-size:13px;line-height:1.5;' +
	'border:1px solid #222;border-radius:4px;padding:10px 12px;';

/* Вызов ytbypass с JSON-ответом */
function callJson(args) {
	return fs.exec(CTL, args).then(function(r) {
		var out = (r.stdout || '').trim();
		try { return JSON.parse(out); }
		catch (e) { return { error: out || r.stderr || _('нет ответа') }; }
	}).catch(function(e) { return { error: e.message }; });
}

/* Вызов ytbypass с текстовым ответом */
function callText(args) {
	return fs.exec(CTL, args).then(function(r) { return r.stdout || ''; })
		.catch(function() { return ''; });
}

/* «стратегия → ok/total»; контрольная строка отдельно */
function parseResults(text) {
	var rows = [], control = null;
	(text || '').split('\n').forEach(function(line) {
		var m = line.match(/^(.*?)\s*→\s*(\d+)\/(\d+)\s*$/);
		if (!m) return;
		if (/^Контрольный тест/.test(m[1]))
			control = { ok: +m[2], total: +m[3] };
		else
			rows.push({ opts: m[1], ok: +m[2], total: +m[3] });
	});
	rows.forEach(function(r, i) { r.i = i; });
	rows.sort(function(a, b) { return (b.ok - a.ok) || (a.i - b.i); });
	return { control: control, rows: rows };
}

/* зелёный — все домены; оранжевый — лучше контрольного замера; красный — не лучше */
function scoreColor(ok, total, controlOk) {
	if (ok === total) return C.green;
	if (controlOk !== null && controlOk !== undefined) return ok > controlOk ? C.orange : C.red;
	return ok > 0 ? C.orange : C.red;
}

function sp(text, color, bold) {
	return E('span', { 'style': 'color:' + color + (bold ? ';font-weight:bold' : '') }, [ text ]);
}

function chip(text, color) {
	return E('span', {
		'style': 'display:inline-block;min-width:4.4em;text-align:center;padding:1px 7px;border-radius:3px;' +
			'font-weight:bold;color:#000;background:' + color
	}, [ text ]);
}

function toast(ok, text) {
	ui.addNotification(null, E('p', text), ok ? 'info' : 'danger');
}

/* ---- цветной вывод лога ---- */
function logLine(line, ctx) {
	var m, kids;

	if ((m = line.match(/^==> \[(\d+)\/(\d+)\] (.*)$/))) {
		var p = presets.find(m[3]);
		kids = [ sp('==> ', C.cyan, true), sp('[' + m[1] + '/' + m[2] + '] ', C.yellow, true), sp(m[3], C.white) ];
		if (p) kids.push(sp('   ← ' + p.name, C.gray));
	}
	else if ((m = line.match(/^==> Результат: (\d+)\/(\d+)$/))) {
		ctx.ctrl = +m[1];
		kids = [ sp('==> ', C.cyan, true), sp('Результат контрольного замера: ', C.gray), sp(m[1] + '/' + m[2], C.white, true) ];
	}
	else if ((m = line.match(/^(\s+)результат: (\d+)\/(\d+)$/))) {
		kids = [ sp(m[1] + 'результат: ', C.gray), sp(m[2] + '/' + m[3], scoreColor(+m[2], +m[3], ctx.ctrl), true) ];
	}
	else if (/^\s+(пропуск|прервано)/.test(line)) {
		kids = [ sp(line, C.yellow) ];
	}
	else if ((m = line.match(/^==> Лучшая стратегия: (.*?)\s*→\s*(\d+)\/(\d+)\s*$/))) {
		kids = [ sp('==> Лучшая стратегия: ', C.green, true), sp(m[1] + ' ', C.white),
			sp('→ ', C.gray), sp(m[2] + '/' + m[3], scoreColor(+m[2], +m[3], ctx.ctrl), true) ];
	}
	else if (/^==> Тест завершён/.test(line)) {
		kids = [ sp(line, C.green, true) ];
	}
	else if (/^==> Тест остановлен/.test(line) || /^==> Пропущено/.test(line)) {
		kids = [ sp(line, C.yellow, true) ];
	}
	else if (/^==> Результаты$/.test(line)) {
		kids = [ sp(line, C.cyan, true) ];
	}
	else if ((m = line.match(/^(.*?)\s*→\s*(\d+)\/(\d+)\s*$/))) {
		if (/^Контрольный тест/.test(m[1])) {
			ctx.ctrl = +m[2];
			kids = [ sp(m[1] + ' → ', C.gray), sp(m[2] + '/' + m[3], C.white, true) ];
		} else {
			kids = [ sp(m[1] + ' ', C.fg), sp('→ ', C.gray),
				sp(m[2] + '/' + m[3], scoreColor(+m[2], +m[3], ctx.ctrl), true) ];
		}
	}
	else if (/^ОШИБКА/.test(line)) {
		kids = [ sp(line, C.red, true) ];
	}
	else if (/^==> /.test(line)) {
		kids = [ sp('==> ', C.cyan, true), sp(line.slice(4), C.fg) ];
	}
	else {
		kids = [ sp(line, C.fg) ];
	}
	return E('div', {}, kids);
}

function renderLog(el, text) {
	var ctx = { ctrl: null };
	dom.content(el, (text || '').split('\n').filter(function(l) { return l !== ''; })
		.map(function(l) { return logLine(l, ctx); }));
}

return view.extend({
	load: function() {
		return Promise.all([
			callJson([ 'test', 'status' ]),
			uci.load('ytbypass'),
			callText([ 'test', 'list', 'get', 'strategies' ]),
			callText([ 'test', 'list', 'get', 'domains' ])
		]);
	},

	render: function(data) {
		var status = data[0] || {};
		var texts = { strategies: data[2] || '', domains: data[3] || '' };
		var editors = {};
		var running = status.running === true;
		var curOpts = presets.clean(uci.get('ytbypass', 'main', 'byedpi_opts'));
		var wasRunning = running;

		var infoEl = E('p', { 'class': 'cbi-section-descr' });
		var buttonsEl = E('div', { 'style': 'margin:8px 0' });
		var logEl = E('div', {
			'style': TERM + 'display:none;max-height:380px;overflow:auto;white-space:pre-wrap;' +
				'word-break:break-word;margin-top:10px'
		});
		var resultsEl = E('div');

		function listState(kind) {
			var isS = kind === 'strategies';
			var n = (isS ? status.strategies : status.domains) || 0;
			var custom = isS ? status.strategies_custom : status.domains_custom;
			return { n: n, custom: !!custom, text: n + ' (' + (custom ? _('свой список') : _('встроенный')) + ')' };
		}

		function renderInfo() {
			var t = _('Каждая стратегия запускается во временном экземпляре ByeDPI на отдельном порту, а домены ' +
				'проверяются через него. Основной сервис и трафик клиентов не затрагиваются, настройки не меняются. ' +
				'Сначала делается контрольный замер без обхода. Тест идёт в фоне — вкладку можно закрыть.');
			dom.content(infoEl, [
				t,
				E('br'),
				E('em', {}, [ _('Стратегий: ') + listState('strategies').text + _(', доменов: ') + listState('domains').text ])
			]);
		}

		/* ---- редакторы списков: по одной стратегии / одному домену в строке ---- */
		function makeEditor(kind, title, hint, opts) {
			var attrs = {
				'class': 'cbi-input-textarea',
				'rows': opts.rows,
				'wrap': opts.wrap ? 'soft' : 'off',
				'spellcheck': 'false',
				/* ширина — явным стилем (theme задаёт свой width для textarea); display:block и max-width
				   не дают полю выйти за пределы страницы */
				'style': 'display:block;box-sizing:border-box;max-width:100%;resize:vertical;' +
					'font-family:monospace;font-size:13px;line-height:1.5;' + opts.width
			};
			var ta = E('textarea', attrs, [ texts[kind] ]);
			var meta = E('div', { 'class': 'cbi-section-descr', 'style': 'margin:4px 0' });
			var saveBtn = E('button', { 'class': 'cbi-button cbi-button-save', 'click': function() { doSaveList(kind); } }, _('Сохранить'));
			var resetBtn = E('button', { 'class': 'cbi-button', 'click': function() { doResetList(kind); } }, _('Сбросить к встроенному'));
			var node = E('div', { 'style': 'margin:14px 0 18px 0' }, [
				E('strong', {}, [ title ]),
				E('div', { 'class': 'cbi-section-descr', 'style': 'margin:2px 0 6px 0' }, [ hint ]),
				ta, meta,
				E('div', {}, [ saveBtn, ' ', resetBtn ])
			]);
			return { node: node, ta: ta, meta: meta, saveBtn: saveBtn, resetBtn: resetBtn };
		}

		/* доступность правки: во время теста списки менять нельзя */
		function syncEditors() {
			[ 'strategies', 'domains' ].forEach(function(k) {
				var ed = editors[k];
				if (!ed) return;
				var st = listState(k);
				dom.content(ed.meta, [ (st.custom ? _('Свой список') : _('Встроенный список')) + ' · ' + st.n + ' ' +
					(k === 'strategies' ? _('стратегий') : _('доменов')) ]);
				ed.ta.disabled = running;
				ed.saveBtn.disabled = running;
				ed.resetBtn.disabled = running || !st.custom;
			});
		}

		function reloadList(kind) {
			return callText([ 'test', 'list', 'get', kind ]).then(function(t) { editors[kind].ta.value = t; });
		}

		function setListState(kind, res) {
			if (kind === 'strategies') { status.strategies = res.count; status.strategies_custom = res.custom; }
			else { status.domains = res.count; status.domains_custom = res.custom; }
		}

		function doSaveList(kind) {
			var ed = editors[kind];
			if (!ed.ta.value.trim()) {
				toast(false, _('Список пуст. Чтобы вернуть встроенный, нажмите «Сбросить к встроенному».'));
				return;
			}
			callJson([ 'test', 'list', 'set', kind, ed.ta.value ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				setListState(kind, res);
				reloadList(kind).then(function() {
					renderInfo(); syncEditors();
					toast(true, _('Список сохранён.'));
				});
			});
		}

		function doResetList(kind) {
			if (!confirm(_('Вернуть встроенный список? Ваши правки будут удалены.'))) return;
			callJson([ 'test', 'list', 'reset', kind ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				setListState(kind, res);
				reloadList(kind).then(function() {
					renderInfo(); syncEditors();
					toast(true, _('Возвращён встроенный список.'));
				});
			});
		}

		editors.strategies = makeEditor('strategies', _('Стратегии'),
			_('Одна стратегия (параметры ciadpi) в строке. Длинные строки переносятся на экране, но остаются одной стратегией.'),
			{ rows: 14, wrap: true, width: 'width:100%;' });
		editors.domains = makeEditor('domains', _('Домены для проверки'),
			_('Один домен в строке; можно вставлять ссылки.'),
			{ rows: 10, wrap: false, width: 'width:40ch;' });

		var listsEl = E('details', { 'style': 'margin:10px 0' }, [
			E('summary', { 'style': 'cursor:pointer;font-weight:bold' }, [ _('Списки для теста — стратегии и домены (редактировать)') ]),
			E('p', { 'class': 'cbi-section-descr' }, [
				_('Свои списки хранятся в /etc/ytbypass/ и не затираются при обновлении. Строки, начинающиеся с #, — комментарии. ' +
				  'Домены нужны только для проверки доступности при тесте и на маршрутизацию не влияют. ' +
				  'Пока идёт тест, списки менять нельзя.')
			]),
			E('div', {}, [ editors.strategies.node, editors.domains.node ])
		]);

		function renderButtons() {
			var els = [];
			if (status.curl === false) {
				els.push(E('em', { 'style': 'color:#c0392b' },
					_('Не установлен curl — он нужен для теста: apk add curl (или opkg install curl).')));
			} else if (running) {
				els.push(E('span', {
					'style': 'display:inline-block;padding:2px 8px;border-radius:3px;color:#000;background:' + C.green
				}, _('тест выполняется')));
				els.push(' ');
				els.push(E('button', { 'class': 'cbi-button cbi-button-remove', 'click': doStop },
					_('Остановить тест')));
			} else {
				els.push(E('button', { 'class': 'cbi-button cbi-button-positive', 'click': doStart },
					_('Запустить тест')));
				if (status.has_results) {
					els.push(' ');
					els.push(E('button', { 'class': 'cbi-button', 'click': doClear },
						_('Очистить результаты')));
				}
			}
			dom.content(buttonsEl, els);
			syncEditors();
		}

		function renderResults(text) {
			var res = parseResults(text);
			if (!res.rows.length && !res.control) {
				dom.content(resultsEl, E('p', { 'class': 'cbi-section-descr' },
					_('Пока нет результатов — запустите тест.')));
				return;
			}

			var controlOk = res.control ? res.control.ok : null;
			var headKids = [];
			if (res.control)
				headKids.push(sp(_('Контрольный замер (без обхода): '), C.gray),
					chip(res.control.ok + '/' + res.control.total, C.gray), E('br'));
			headKids.push(sp(_('Цвет: '), C.gray), chip(_('все домены'), C.green), ' ',
				chip(_('лучше контроля'), C.orange), ' ', chip(_('не лучше'), C.red),
				sp(_('   При равенстве выше стоит стратегия, что раньше в списке.'), C.gray));
			var head = E('div', { 'style': 'margin-bottom:8px' }, headKids);

			/* обычная таблица с фиксированной раскладкой: длинные стратегии переносятся внутри своей ячейки */
			var CELL = 'padding:7px 8px 7px 0;border:0;border-top:1px solid #1e1e1e;vertical-align:top;' +
				'background:transparent;color:inherit;';
			var rows = res.rows.map(function(r, i) {
				var p = presets.find(r.opts);
				var isCur = presets.clean(r.opts) === curOpts;
				var body = [];
				if (p || isCur)
					body.push(E('div', { 'style': 'color:' + C.gray + ';margin-bottom:2px' }, [
						p ? p.name : '',
						isCur ? sp((p ? '  ' : '') + _('(текущая)'), C.cyan, true) : ''
					]));
				body.push(E('div', {
					'style': 'color:' + C.white + ';white-space:pre-wrap;word-break:break-word;overflow-wrap:anywhere'
				}, [ r.opts ]));

				return E('tr', {}, [
					E('td', { 'style': CELL + 'width:2.6em;color:' + C.gray }, [ String(i + 1) ]),
					E('td', { 'style': CELL + 'width:6.6em' }, [ chip(r.ok + '/' + r.total, scoreColor(r.ok, r.total, controlOk)) ]),
					E('td', { 'style': CELL }, body),
					E('td', { 'style': CELL + 'width:9em;text-align:right;padding-right:0' }, [
						isCur ? '' : E('button', {
							'class': 'cbi-button cbi-button-apply',
							'click': function() { doApply(r.opts); }
						}, _('Применить'))
					])
				]);
			});

			var table = E('table', {
				'style': 'width:100%;table-layout:fixed;border-collapse:collapse;border-spacing:0;margin:0;background:transparent'
			}, [ E('tbody', {}, rows) ]);

			dom.content(resultsEl, E('div', { 'style': TERM }, [ head, table ]));
		}

		function refreshResults() {
			return callText([ 'test', 'results' ]).then(renderResults);
		}

		function refreshLog() {
			return callText([ 'test', 'log' ]).then(function(t) {
				var atBottom = logEl.scrollTop + logEl.clientHeight >= logEl.scrollHeight - 20;
				logEl.style.display = t ? '' : 'none';
				renderLog(logEl, t);
				if (atBottom) logEl.scrollTop = logEl.scrollHeight;
			});
		}

		function doStart() {
			callJson([ 'test', 'start' ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				running = true;
				wasRunning = true;
				status.has_results = false;
				dom.content(resultsEl, '');
				renderButtons();
				refreshLog();
				toast(true, _('Тест запущен.'));
			});
		}

		function doStop() {
			callJson([ 'test', 'stop' ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				toast(true, _('Останавливаю тест…'));
			});
		}

		function doClear() {
			callJson([ 'test', 'clear' ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				status.has_results = false;
				renderButtons();
				renderResults('');
				logEl.style.display = 'none';
			});
		}

		function doApply(opts) {
			var p = presets.find(opts);
			if (!confirm(_('Применить стратегию и перезапустить службу?\n\n') + (p ? p.name + '\n' : '') + opts)) return;
			callJson([ 'set-strategy', opts ]).then(function(res) {
				if (res.error) { toast(false, res.error); return; }
				curOpts = presets.clean(opts);
				toast(true, _('Стратегия применена, служба перезапущена.'));
				refreshResults();
			});
		}

		function tick() {
			return callJson([ 'test', 'status' ]).then(function(st) {
				if (st.error) return;
				status = st;
				running = st.running === true;
				renderInfo();
				renderButtons();
				if (running || wasRunning)
					refreshLog();
				if (wasRunning && !running) {
					wasRunning = false;
					refreshResults();
					toast(st.rc === '0' || st.rc === '', _('Тест завершён.'));
				}
			});
		}

		renderInfo();
		renderButtons();
		refreshLog();
		refreshResults();
		poll.add(tick, 3);

		return E([
			E('h2', {}, _('Тест стратегий ByeDPI')),
			E('div', { 'class': 'cbi-section' }, [ infoEl, buttonsEl, listsEl, logEl ]),
			E('div', { 'class': 'cbi-section' }, [ E('h3', {}, _('Результаты')), resultsEl ])
		]);
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null
});
YTB_FILE_END_7f3a9c
	chmod 644 "$R/www/luci-static/resources/view/ytbypass/test.js"
	mkdir -p "$R/www/luci-static/resources/ytbypass"
	cat > "$R/www/luci-static/resources/ytbypass/presets.js" <<'YTB_FILE_END_7f3a9c'
'use strict';
'require baseclass';

/*
 * Готовые стратегии ByeDPI (параметры ciadpi).
 * name — короткое имя для списка, чтобы не читать длинную командную строку;
 * опции подставляются в поле «Параметры ByeDPI».
 * Под своего провайдера лучшую стратегию подбирает вкладка «Тест стратегий».
 */
var LIST = [
	{
		id: 'p1',
		name: '1 · Каскад disorder/split + tlsrec + md5sig, авто-режим -As (по умолчанию)',
		opts: '-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1'
	},
	{
		id: 'p2',
		name: '2 · Короткая: OOB + tlsrec у SNI',
		opts: '-o1 -a1 -r-5+se'
	},
	{
		id: 'p3',
		name: '3 · Fake SNI google.com + disorder/OOB (TTL 4)',
		opts: '-n "google.com" -Qr -d5+sm -f3+sm -o2 -t4 -a1'
	},
	{
		id: 'p4',
		name: '4 · Каскад disorder/split без tlsrec и авто-режима',
		opts: '-d1 -s1+s -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -a1'
	},
	{
		id: 'p5',
		name: '5 · Fake + disoob + tlsrec (TTL 5 и 15)',
		opts: '-f1 -t5 -n "google.com" -q3+h -Qr -f2 -q1 -r1+s -t15 -q1 -o2 -a1'
	},
	{
		id: 'p6',
		name: '6 · OOB + tlsrec + авто-режим -At,r,s, fake google.com',
		opts: '-o1 -r-5+se -a1 -At,r,s -d1 -n "google.com" -Qr -f-1 -a1'
	}
];

/* для сравнения: без кавычек, пробелы схлопнуты (так же, как в бэкенде) */
function clean(s) {
	return String(s == null ? '' : s).replace(/["']/g, '').replace(/\s+/g, ' ').trim();
}

/* для хранения: только пробелы, кавычки остаются как ввёл пользователь */
function norm(s) {
	return String(s == null ? '' : s).replace(/\s+/g, ' ').trim();
}

function find(opts) {
	var c = clean(opts);
	if (!c) return null;
	for (var i = 0; i < LIST.length; i++)
		if (clean(LIST[i].opts) === c) return LIST[i];
	return null;
}

function byId(id) {
	for (var i = 0; i < LIST.length; i++)
		if (LIST[i].id === id) return LIST[i];
	return null;
}

return baseclass.extend({
	list: LIST,
	DEFAULT: LIST[0].opts,
	clean: clean,
	norm: norm,
	find: find,
	byId: byId
});
YTB_FILE_END_7f3a9c
	chmod 644 "$R/www/luci-static/resources/ytbypass/presets.js"
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

# curl (с SOCKS5) и корневые сертификаты нужны вкладке «Тест стратегий»
for p in ca-bundle curl; do
	pkg_has "$p" || pkg_add "$p" >/dev/null 2>&1 || warn "не удалось поставить $p — тест стратегий работать не будет (остальное — да)"
done

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

# стратегия по умолчанию сменилась: обновляем, только если стоял один из прежних дефолтов (свою не трогаем)
OLD_DEFAULT_1='--split 1 --disorder 3+s --mod-http=h,d --auto=torst --tlsrec 1+s'
OLD_DEFAULT_2='-o1 -r-5+se -a1 -At,r,s -d1 -n "google.com" -Qr -f-1 -a1'
NEW_DEFAULT='-d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -r1+s -S -a1 -As -d1 -d3+s -s6+s -d9+s -s12+s -d15+s -s20+s -d25+s -s30+s -d35+s -S -a1'
CUR_OPTS=$(uci -q get ytbypass.main.byedpi_opts)
if [ "$CUR_OPTS" = "$OLD_DEFAULT_1" ] || [ "$CUR_OPTS" = "$OLD_DEFAULT_2" ]; then
	uci set ytbypass.main.byedpi_opts="$NEW_DEFAULT" && uci commit ytbypass
	say "Стратегия по умолчанию обновлена"
fi
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

Готово. Веб-интерфейс: LuCI -> Службы -> YouTube Bypass (вкладки «Настройки» и «Тест стратегий»).
Проверка: откройте YouTube на устройстве в LAN (DNS — роутер), затем на роутере:
  ytbypass status       состояние
  ytbypass list         IP, попавшие в наборы
  logread -e ytbypass   логи

Если клиент уже держал IP YouTube в DNS-кэше — перезапустите браузер / переподключите Wi-Fi.
Удаление: sh install.sh --uninstall
MSG
