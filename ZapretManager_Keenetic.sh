#!/bin/sh
ZM_NEW_VER="1.00"
GREEN="\033[1;32m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; RED="\033[1;31m"; NC="\033[0m"
PATH=/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH

_zmi_say() { echo -e "${CYAN}==>${NC} $*"; }
_zmi_ok() { echo -e "   ${GREEN}✓${NC} $*"; }
_zmi_step() { echo -e "   → $*"; }
_zmi_warn() { echo -e "   ${YELLOW}!${NC} $*"; }
_zmi_die() { echo -e "\n${RED}Ошибка: $*${NC}\n"; exit 1; }
_zmi_has() { opkg list-installed 2>/dev/null | grep -q "^$1 "; }
_zmi_pkg() {
	if _zmi_has "$1"; then _zmi_ok "Пакет $1 уже установлен"; return 0; fi
	_zmi_step "Устанавливаем пакет $1"
	opkg install "$1" >/dev/null 2>&1 || true
	if ! _zmi_has "$1"; then
		_zmi_step "Не получилось — обновляем список пакетов и пробуем ещё раз"
		opkg update >/dev/null 2>&1 || true
		opkg install "$1" >/dev/null 2>&1 || true
	fi
	if _zmi_has "$1"; then _zmi_ok "Пакет $1 установлен"; return 0; fi
	_zmi_warn "Пакет $1 не установился — проверьте интернет на роутере. $2"
	return 1
}

clear 2>/dev/null || true
echo -e "${MAGENTA}Zapret Manager для Keenetic $ZM_NEW_VER — установка${NC}\n"

_zmi_say "Проверяем роутер"
[ -f /opt/etc/opkg.conf ] && command -v opkg >/dev/null 2>&1 || _zmi_die "не найден Entware (/opt). Сначала установите OPKG/Entware на флешку или во внутреннюю память — см. инструкцию"
[ "$(id -u 2>/dev/null || echo 0)" = 0 ] || _zmi_die "запустите установку от root"
if [ -x /bin/ndm ] || [ -x /bin/ndmc ]; then _zmi_ok "KeeneticOS + Entware"
else _zmi_warn "Похоже, это не Keenetic — функции DNS и политик работать не будут"; fi
case "$(grep -oE 'mips-3|mipsel-3|aarch64-3|armv7|x64-3' /opt/etc/opkg.conf | head -n 1)" in
	mipsel-3) _zmi_ok "Архитектура: mipsel" ;;
	mips-3) _zmi_ok "Архитектура: mips" ;;
	aarch64-3) _zmi_ok "Архитектура: aarch64" ;;
	armv7) _zmi_ok "Архитектура: armv7" ;;
	x64-3) _zmi_ok "Архитектура: x86_64" ;;
	*) _zmi_warn "Не удалось определить архитектуру Entware — пробуем по uname: $(uname -m)" ;;
esac
_zm_free="$(df -k /opt 2>/dev/null | awk 'NR == 2 { print $4 }')"
[ -n "$_zm_free" ] && [ "$_zm_free" -lt 15360 ] 2>/dev/null && _zmi_die "в /opt свободно меньше 15 МБ ($_zm_free КБ)"
_zmi_ok "Свободно в /opt: $((${_zm_free:-0} / 1024)) МБ"
for _zm_f in /tmp/zapret-manager/*.pid; do
	[ -f "$_zm_f" ] || continue
	_zm_j="$(basename "$_zm_f" .pid)"
	[ "$_zm_j" = panel ] && continue
	if kill -0 "$(cat "$_zm_f" 2>/dev/null)" 2>/dev/null && ! grep -q '^__DONE__' "/tmp/zapret-manager/$_zm_j.log" 2>/dev/null; then
		_zmi_die "сейчас в панели идёт операция ($_zm_j) — дождитесь её окончания и запустите установку снова"
	fi
done

_zmi_say "Ставим нужные пакеты"
_zmi_step "Обновляем список пакетов"
opkg update >/dev/null 2>&1 && _zmi_ok "Список пакетов обновлён" || _zmi_warn "Список пакетов не обновился — пробуем с тем, что есть"
_zmi_pkg ca-bundle || true
_zmi_pkg curl "Без curl панель не сможет ничего скачивать." || _zmi_die "нужен пакет curl"
_zmi_pkg jq || _zmi_die "нужен пакет jq"
_zmi_pkg iptables "Без iptables обход работать не будет." || _zmi_die "нужен пакет iptables"
_zmi_pkg lighttpd "Без него не откроется веб-панель." || _zmi_die "нужен пакет lighttpd"
_zmi_pkg lighttpd-mod-cgi "Без него не откроется веб-панель." || _zmi_die "нужен пакет lighttpd-mod-cgi"
command -v sha256sum >/dev/null 2>&1 || _zmi_pkg coreutils-sha256sum || true

_zmi_say "Записываем файлы панели"
_zm_had_lib=0
[ -f /opt/zapret-manager/lib.sh ] && _zm_had_lib=1
mkdir -p /opt/zapret-manager/www /opt/zapret-manager/defaults /opt/etc/zapret-manager /opt/zapret/ipset /opt/zapret/files/fake /opt/zapret/nfq /opt/etc/init.d /opt/etc/ndm/netfilter.d /opt/etc/lighttpd/conf.d /opt/var/run /opt/var/log /opt/bin /opt/tmp
cat > '/opt/zapret-manager/lib.sh.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
ZM_VERSION="1.00"
PATH=${ZM_PATH_PREFIX:+$ZM_PATH_PREFIX:}/opt/sbin:/opt/bin:/opt/usr/sbin:/opt/usr/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PATH
umask 022

ZM_ROOT="${ZM_ROOT:-}"
ZM_DIR="$ZM_ROOT/opt/zapret-manager"
ZM_ETC="$ZM_ROOT/opt/etc/zapret-manager"
ZM_TMP="${ZM_TMP:-$ZM_ROOT/tmp/zapret-manager}"
ZM_RUN="$ZM_ROOT/opt/var/run"
ZM_LOG="$ZM_ROOT/opt/var/log/zapret-manager.log"
ZAP="$ZM_ROOT/opt/zapret"
NFQWS="$ZAP/nfq/nfqws"
IPS="$ZAP/ipset"
FAKE="$ZAP/files/fake"
CONF="$ZM_ETC/zapret.conf"
STATE="$ZM_ETC/strategy.conf"
OPT="$ZM_ETC/nfqws.opt"
YV_FILE="$ZM_ETC/youtube.txt"
FS_FILE="$ZM_ETC/flowseal.txt"
PIDF="$ZM_RUN/zm-nfqws.pid"
INIT="$ZM_ROOT/opt/etc/init.d/S51zapret-manager"
TG_INIT="$ZM_ROOT/opt/etc/init.d/S99tg-ws-proxy-rs"
TG_CONF_DIR="$ZM_ROOT/opt/etc/tg-ws-proxy-rs"
TG_BIN="$ZM_ROOT/opt/bin/tg-ws-proxy-rs"
TG_LOG="$ZM_ROOT/opt/var/log/tg-ws-proxy-rs.log"
RCI="${ZM_RCI:-http://127.0.0.1:79/rci}"
QNUM=210
DMARK=0x40000000
ZM_NL='
'

GH_RAW="https://raw.githubusercontent.com"
GH="https://github.com"
ZM_REPO_RAW="$GH_RAW/StressOzz/Zapret-Manager/refs/heads/main"
ZM_SCRIPT_URL="$ZM_REPO_RAW/ZapretManager_Keenetic.sh"
EXCLUDE_URL="$ZM_REPO_RAW/zapret-hosts-user-exclude.txt"
EXCLUDE_URL2="$GH_RAW/remittor/zapret-openwrt/master/zapret/ipset/zapret-hosts-user-exclude.txt"
STR_URL="$ZM_REPO_RAW/files/StrYoutube"
RKN_URL="$GH_RAW/IndeecFOX/zapret4rocket/refs/heads/master/extra_strats/TCP/RKN/List.txt"
FLOWSEAL_ZIP="${ZM_FLOWSEAL_ZIP:-$GH/Flowseal/zapret-discord-youtube/archive/refs/heads/main.zip}"
FAKE_SRC="$GH_RAW/Flowseal/zapret-discord-youtube/main/bin $GH_RAW/bol-van/zapret/master/files/fake $GH_RAW/StressOzz/Zapret-Manager/main/files"
ZAPRET_REPO="bol-van/zapret"
ZAPRET_DEF_TAG="v72.13"
TG_INSTALL_URL="$GH_RAW/valnesfjord/tg-ws-proxy-rs/main/install.sh"

PORTS_UDP_GAME="88,1024-2407,2409-4499,4502-19293,19345-49999,50101-65535"
PORTS_TCP_GAME="2099,2802,2302,2502,3478-3480,3724,6000-8000,8085,8090,8100,8903,8904,25565,27015-27030,27036-27037,35500-35600,50001,60442"
PORTS_XTREME="80,88,444-65535"
DISCORD_UDP="19294-19344,50000-50100"
DISCORD_TCP="2053,2083,2087,2096,8443"
DOH_DEF="cloudflare-dns.com,dns.google,dns.comss.one,dns.quad9.net"
DOH_TPL="--filter-tcp=443 --dpi-desync=hostfakesplit --dpi-desync-hostfakesplit-mod=host=common.dot.dns.yandex.net --dpi-desync-hostfakesplit-midhost=host-2 --dpi-desync-split-seqovl=726 --dpi-desync-fooling=badsum,badseq --dpi-desync-badseq-increment=0"
L_USER="$IPS/zapret-hosts-user.txt"
L_EXCL="$IPS/zapret-hosts-user-exclude.txt"
L_GOOGLE="$IPS/zapret-hosts-google.txt"
L_RKN="$IPS/zapret-hosts-rkn.txt"
L_AUTO="$IPS/zapret-hosts-auto.txt"
L_IPUSER="$IPS/zapret-ip-user.txt"
L_IPEXCL="$IPS/zapret-ip-exclude.txt"

esc() {
	case "$1" in *[!A-Za-z0-9\ ._:/@+=,%-]*) ;; *) printf '%s' "$1"; return 0 ;; esac
	printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r//g' | awk 'NR > 1 { printf "\\n" } { printf "%s", $0 }'
}
jb() { if "$@" >/dev/null 2>&1; then echo true; else echo false; fi; }
jstr_file() { if [ -f "$1" ]; then jq -Rs . < "$1"; else echo '""'; fi; }
err() { printf '{"error":"%s"}\n' "$(esc "$1")"; return 1; }
ok() { printf '{"ok":true%s}\n' "${1:+,$1}"; }
re() { printf '%s' "$1" | grep -qE "$2"; }
now() { date +%s; }
rnd_hex() {
	local n="${1:-16}" r
	r="$(head -c "$n" /dev/urandom 2>/dev/null | hexdump -v -e '1/1 "%02x"' 2>/dev/null)"
	[ -n "$r" ] || r="$(head -c "$n" /dev/urandom 2>/dev/null | od -An -v -tx1 2>/dev/null | tr -d ' \n')"
	[ -n "$r" ] || r="$(printf '%s%s%s' "$(date)" "$$" "$(cat /proc/uptime)" | sha256sum | cut -c1-$((n * 2)))"
	printf '%s' "$r"
}
cnt() { [ -f "$1" ] || { echo 0; return; }; sed 's/#.*//' "$1" | awk 'NF { n++ } END { print n + 0 }'; }
fsize() { [ -f "$1" ] && wc -c < "$1" | tr -d ' ' || echo 0; }

say() { echo "==> $*"; }
good() { echo "   ✓ $*"; }
warn() { echo "   ! $*"; }

zm_log() {
	mkdir -p "${ZM_LOG%/*}" 2>/dev/null
	[ -f "$ZM_LOG" ] && [ "$(wc -c < "$ZM_LOG" 2>/dev/null)" -gt 262144 ] 2>/dev/null && tail -n 400 "$ZM_LOG" > "$ZM_LOG.1" && mv -f "$ZM_LOG.1" "$ZM_LOG"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$ZM_LOG" 2>/dev/null
}

cfg_get() {
	local f="$1" k="$2" d="$3" v
	v="$(sed -n "s/^$k='\(.*\)'\$/\1/p" "$f" 2>/dev/null | tail -n 1)"
	[ -n "$v" ] || v="$(sed -n "s/^$k=\([^'\"]*\)\$/\1/p" "$f" 2>/dev/null | tail -n 1)"
	[ -n "$v" ] && printf '%s' "$v" || printf '%s' "$d"
}
cfg_set() {
	local f="$1" k="$2" v="$3"
	case "$v" in *"'"*|*"$ZM_NL"*) return 1 ;; esac
	mkdir -p "${f%/*}"
	[ -f "$f" ] || : > "$f"
	if grep -q "^$k=" "$f"; then
		awk -v k="$k" -v v="$v" 'BEGIN { q = sprintf("%c", 39) } index($0, k "=") == 1 { print k "=" q v q; next } { print }' "$f" > "$f.n" && mv -f "$f.n" "$f"
	else
		printf "%s='%s'\n" "$k" "$v" >> "$f"
	fi
}
c() { cfg_get "$CONF" "$1" "$2"; }
s() { cfg_get "$STATE" "$1" "$2"; }

conf_defaults() {
	mkdir -p "$ZM_ETC" "$IPS" "$FAKE" "$ZM_TMP"
	[ -f "$CONF" ] || cat > "$CONF" << 'EOF'
ENABLED='1'
WAN_IFACE=''
IPV6='0'
POLICY_NAME=''
POLICY_EXCLUDE='0'
QUIC_BLOCK='0'
LOG='0'
PKT_TCP='9'
PKT_UDP='9'
EOF
	[ -f "$STATE" ] || cat > "$STATE" << 'EOF'
MAIN='v7'
YT='Yv08'
QUIC='0'
DISCORD='1'
GAME='off'
XTREME='0'
LISTS='all'
DOH='0'
EXPERT='0'
EOF
	for f in "$L_USER" "$L_AUTO" "$L_IPUSER"; do [ -f "$f" ] || : > "$f"; done
	return 0
}

zm_has() { command -v "$1" >/dev/null 2>&1; }
fetch_ok() {
	[ -s "$1" ] || return 1
	[ -n "$ZM_FETCH_ANY" ] && return 0
	! head -c 1024 "$1" | grep -qiE '<(!doctype|html|head|body)'
}
fetch() {
	local u="$1" o="$2" t="${3:-120}" code rc
	ZM_FETCH_ERR=""
	rm -f "$o"
	if zm_has curl; then
		code="$(curl -fsSL --connect-timeout 10 --max-time "$t" -A "Mozilla/5.0" -o "$o" -w '%{http_code}' "$u" 2>/dev/null)"; rc=$?
		[ "$rc" = 0 ] && fetch_ok "$o" && return 0
		rm -f "$o"
		case "$rc:$code" in
			22:404|22:410) ZM_FETCH_ERR="файла нет на сервере (HTTP $code)" ;;
			22:*) ZM_FETCH_ERR="сервер ответил ошибкой HTTP $code" ;;
			6:*) ZM_FETCH_ERR="не удалось найти адрес сервера (DNS)" ;;
			7:*) ZM_FETCH_ERR="сервер не отвечает" ;;
			28:*) ZM_FETCH_ERR="истекло время ожидания" ;;
			35:*|60:*) ZM_FETCH_ERR="ошибка TLS — проверьте пакет ca-bundle и время на роутере" ;;
			0:*) ZM_FETCH_ERR="вместо файла пришла веб-страница" ;;
			*) ZM_FETCH_ERR="curl: ошибка $rc" ;;
		esac
		return 1
	fi
	if zm_has wget; then
		wget -q -T "$t" -O "$o" "$u" 2>/dev/null && fetch_ok "$o" && return 0
		rm -f "$o"; ZM_FETCH_ERR="wget не скачал файл"; return 1
	fi
	ZM_FETCH_ERR="на роутере нет curl"
	return 1
}
gh_latest_tag() {
	curl -Ls --connect-timeout 8 --max-time 20 -o /dev/null -w '%{url_effective}' "$GH/$1/releases/latest" 2>/dev/null |
		sed -n 's#.*/releases/tag/##p' | head -n 1 | grep -E '^v?[0-9]+(\.[0-9]+)+$'
}

zm_arch() {
	local a=""
	[ -f "$ZM_ROOT/opt/etc/opkg.conf" ] && a="$(grep -oE 'mips-3|mipsel-3|mips64|aarch64-3|armv7|armv5|x64-3|x86_64|i386|i686' "$ZM_ROOT/opt/etc/opkg.conf" | head -n 1)"
	[ -n "$a" ] || a="$(opkg print-architecture 2>/dev/null | awk '$1 == "arch" && $2 != "all" && $2 != "noarch" { print $2 }' | tail -n 1)"
	[ -n "$a" ] || a="$(uname -m)"
	case "$a" in
		mipsel*) echo mipsel ;;
		mips64*) echo mips64 ;;
		mips*) echo mips ;;
		aarch64*|arm64*) echo arm64 ;;
		armv7*|arm*) echo arm ;;
		x64*|x86_64*) echo x86_64 ;;
		i386*|i686*) echo x86 ;;
		*) return 1 ;;
	esac
}

job_running() {
	local p="$ZM_TMP/$1.pid"
	[ -f "$p" ] && kill -0 "$(cat "$p" 2>/dev/null)" 2>/dev/null && ! grep -q '^__DONE__' "$ZM_TMP/$1.log" 2>/dev/null
}
job_start() {
	local name="$1"; shift
	mkdir -p "$ZM_TMP"
	if job_running "$name"; then printf '{"ok":true,"job":"%s","already":true}\n' "$name"; return 0; fi
	rm -f "$ZM_TMP/$name.log"
	(
		trap '' HUP
		"$@"
		echo "__DONE__ $?"
	) < /dev/null > "$ZM_TMP/$name.log" 2>&1 &
	echo $! > "$ZM_TMP/$name.pid"
	printf '{"ok":true,"job":"%s"}\n' "$name"
}
job_status() {
	local n="$1" l="$ZM_TMP/$1.log" running=false done=false rc=""
	re "$n" '^[a-z0-9_]{1,40}$' || { err "некорректное имя задачи"; return 1; }
	job_running "$n" && running=true
	if grep -q '^__DONE__' "$l" 2>/dev/null; then done=true; rc="$(grep '^__DONE__' "$l" | tail -n 1 | awk '{ print $2 }')"; fi
	printf '{"running":%s,"done":%s,"rc":"%s","lines":%s}\n' "$running" "$done" "$rc" "$( [ -f "$l" ] && tail -n 300 "$l" | grep -v '^__DONE__' | jq -Rs . || echo '""')"
}
jobs_busy() {
	local f n
	for f in "$ZM_TMP"/*.pid; do
		[ -f "$f" ] || continue
		n="${f##*/}"; n="${n%.pid}"
		job_running "$n" && { echo "$n"; return 0; }
	done
	return 1
}

ports_norm() {
	awk -v sep="${1:-,}" -v rs="${2:-:}" '
		{
			n = split($0, a, /[, \t]+/)
			for (i = 1; i <= n; i++) {
				x = a[i]
				if (x ~ /^[0-9]+$/) { lo = x + 0; hi = lo }
				else if (x ~ /^[0-9]+[-:][0-9]+$/) { split(x, b, /[-:]/); lo = b[1] + 0; hi = b[2] + 0 }
				else continue
				if (lo > hi) { t = lo; lo = hi; hi = t }
				if (lo < 1) lo = 1
				if (hi > 65535) hi = 65535
				if (lo > 65535) continue
				m++; L[m] = lo; H[m] = hi
			}
		}
		END {
			for (i = 2; i <= m; i++) { l = L[i]; h = H[i]; j = i - 1; while (j > 0 && L[j] > l) { L[j + 1] = L[j]; H[j + 1] = H[j]; j-- } L[j + 1] = l; H[j + 1] = h }
			k = 0
			for (i = 1; i <= m; i++) {
				if (k > 0 && L[i] <= OH[k] + 1) { if (H[i] > OH[k]) OH[k] = H[i]; continue }
				k++; OL[k] = L[i]; OH[k] = H[i]
			}
			o = ""
			for (i = 1; i <= k; i++) o = o (i > 1 ? sep : "") (OL[i] == OH[i] ? OL[i] : OL[i] rs OH[i])
			print o
		}'
}
mport_chunks() {
	printf '%s\n' "$1" | awk '
		{
			n = split($0, a, ",")
			for (i = 1; i <= n; i++) {
				if (a[i] == "") continue
				w = (index(a[i], ":") ? 2 : 1)
				if (cnt + w > 15) { print cur; cur = ""; cnt = 0 }
				cur = cur (cur == "" ? "" : ",") a[i]; cnt += w
			}
		}
		END { if (cur != "") print cur }'
}

opt_clean() {
	[ -f "${1:-$OPT}" ] || return 0
	sed 's/\r$//; s/^[ \t]*//; s/[ \t]*$//' "${1:-$OPT}" | grep -v '^#' | grep -v '^$' | grep -vx "'"
}
opt_ports() {
	local kind="$1" f="${2:-$OPT}" base=""
	[ "$kind" = tcp ] && base="80,443"
	{ echo "$base"; opt_clean "$f" | tr ' ' '\n' | sed -n "s/^--filter-$kind=//p"; } | ports_norm , :
}
opt_args() {
	local f="${1:-$OPT}" hl hln
	hl="--hostlist=$L_USER --hostlist-exclude=$L_EXCL"
	hln="--hostlist=$L_USER --hostlist=$L_AUTO --hostlist-exclude=$L_EXCL"
	[ -s "$L_IPEXCL" ] && { hl="$hl --ipset-exclude=$L_IPEXCL"; hln="$hln --ipset-exclude=$L_IPEXCL"; }
	opt_clean "$f" | sed "s#<HOSTLIST>#--hostlist-auto=$L_AUTO $hl#g; s#<HOSTLIST_NOAUTO>#$hln#g" | tr '\n' ' '
}

wan_ifaces() {
	local w
	w="$(c WAN_IFACE)"
	[ -n "$w" ] && { echo $w; return 0; }
	awk 'NR > 1 && $2 == "00000000" && $8 == "00000000" && $1 != "lo" { print $1 }' "$ZM_ROOT/proc/net/route" 2>/dev/null | sort -u | xargs
}
wan6_ifaces() {
	local w
	w="$(c WAN_IFACE)"
	[ -n "$w" ] && { echo $w; return 0; }
	awk '$1 == "00000000000000000000000000000000" && $2 == "00" && $10 != "lo" { print $10 }' "$ZM_ROOT/proc/net/ipv6_route" 2>/dev/null | sort -u | xargs
}
ndmc_cli() { LD_LIBRARY_PATH="/lib:/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" /bin/ndmc -c "$@" 2>/dev/null; }
policy_mark() {
	local p m
	p="$(c POLICY_NAME)"
	[ -n "$p" ] || return 1
	m="$(ndmc_cli 'show ip policy' | grep -i "description = $p:" -A 1 | grep 'mark:' | grep -o '[^ ]*$' | head -n 1)"
	[ -n "$m" ] || return 1
	echo "0x$m/0x0fffffff"
}

kmods() {
	local k m p
	k="$(uname -r)"
	modprobe -a -q nfnetlink_queue xt_multiport xt_connbytes xt_NFQUEUE >/dev/null 2>&1
	for m in nfnetlink_queue xt_multiport xt_connbytes xt_NFQUEUE; do
		lsmod 2>/dev/null | grep -q "^$m " && continue
		p="$(find "/lib/modules/$k" -name "$m.ko*" 2>/dev/null | head -n 1)"
		[ -n "$p" ] && insmod "$p" >/dev/null 2>&1
	done
}
kmods_missing() {
	local m o=""
	for m in xt_NFQUEUE xt_connbytes xt_multiport; do
		lsmod 2>/dev/null | grep -q "^$m " && continue
		[ -n "$(find "/lib/modules/$(uname -r)" -name "$m.ko*" 2>/dev/null | head -n 1)" ] && continue
		grep -q "$m" "/lib/modules/$(uname -r)/modules.builtin" 2>/dev/null && continue
		o="$o $m"
	done
	echo $o
}

ipt() { "$@" 2>/dev/null; }
fw_chain() {
	local t="$1" tb="$2" ch="$3" hook="$4"
	ipt $t -w -t "$tb" -N "$ch" || ipt $t -w -t "$tb" -F "$ch"
	ipt $t -w -t "$tb" -C "$hook" -j "$ch" || ipt $t -w -t "$tb" -I "$hook" 1 -j "$ch"
}
fw_unchain() {
	local t="$1" tb="$2" ch="$3" hook="$4"
	while ipt $t -w -t "$tb" -D "$hook" -j "$ch"; do :; done
	ipt $t -w -t "$tb" -F "$ch"
	ipt $t -w -t "$tb" -X "$ch"
}
fw_table() {
	local t="$1" tb="$2" ifs pm tcp udp ch IF ex
	command -v "$t" >/dev/null 2>&1 || return 0
	if [ "$t" = ip6tables ]; then [ "$(c IPV6 0)" = 1 ] || return 0; ifs="$(wan6_ifaces)"; else ifs="$(wan_ifaces)"; fi
	[ -n "$ifs" ] || return 0
	case "$tb" in
		mangle)
			nfqws_running || return 0
			fw_chain "$t" mangle zm_post POSTROUTING
			pm="$(policy_mark)"
			ex="$(c POLICY_EXCLUDE 0)"
			tcp="$(opt_ports tcp)"; udp="$(opt_ports udp)"
			for IF in $ifs; do
				ipt $t -w -t mangle -A zm_post -o "$IF" -m mark --mark "$DMARK/$DMARK" -j RETURN
				if [ -n "$pm" ]; then
					if [ "$ex" = 1 ]; then ipt $t -w -t mangle -A zm_post -o "$IF" -m mark --mark "$pm" -j RETURN
					else ipt $t -w -t mangle -A zm_post -o "$IF" -m mark ! --mark "$pm" -j RETURN; fi
				fi
				for ch in $(mport_chunks "$tcp"); do
					ipt $t -w -t mangle -A zm_post -o "$IF" -p tcp -m multiport --dports "$ch" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes "1:$(c PKT_TCP 9)" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
				done
				for ch in $(mport_chunks "$udp"); do
					ipt $t -w -t mangle -A zm_post -o "$IF" -p udp -m multiport --dports "$ch" -m connbytes --connbytes-dir=original --connbytes-mode=packets --connbytes "1:$(c PKT_UDP 9)" -j NFQUEUE --queue-num "$QNUM" --queue-bypass
				done
			done
			if grep -q -- '<HOSTLIST>' "$OPT" 2>/dev/null; then
				fw_chain "$t" mangle zm_pre PREROUTING
				for IF in $ifs; do
					ipt $t -w -t mangle -A zm_pre -i "$IF" -p tcp -m multiport --sports 80,443 -m connbytes --connbytes-dir=reply --connbytes-mode=packets --connbytes 1:3 -j NFQUEUE --queue-num "$QNUM" --queue-bypass
				done
			else
				fw_unchain "$t" mangle zm_pre PREROUTING
			fi ;;
		nat)
			[ "$t" = iptables ] || return 0
			nfqws_running || return 0
			fw_chain "$t" nat zm_masq POSTROUTING
			for IF in $ifs; do
				ipt $t -w -t nat -A zm_masq -o "$IF" -p udp -m mark --mark "$DMARK/$DMARK" -j MASQUERADE
			done ;;
		filter)
			if [ "$(c QUIC_BLOCK 0)" = 1 ]; then
				fw_chain "$t" filter zm_fwd FORWARD
				for IF in $ifs; do
					ipt $t -w -t filter -A zm_fwd -o "$IF" -p udp --dport 443 -j REJECT
				done
			else
				fw_unchain "$t" filter zm_fwd FORWARD
			fi ;;
	esac
	return 0
}
fw_apply() {
	local t tb
	for t in iptables ip6tables; do
		for tb in mangle nat filter; do fw_table "$t" "$tb"; done
	done
}
fw_remove() {
	local t
	for t in iptables ip6tables; do
		command -v "$t" >/dev/null 2>&1 || continue
		fw_unchain "$t" mangle zm_post POSTROUTING
		fw_unchain "$t" mangle zm_pre PREROUTING
		fw_unchain "$t" nat zm_masq POSTROUTING
	done
}
fw_hook() {
	local t="$1" tb="$2"
	[ -f "$CONF" ] || return 0
	case "$t" in iptables|ip6tables) ;; *) return 0 ;; esac
	case "$tb" in mangle|nat|filter) fw_table "$t" "$tb" ;; esac
}

nfqws_pid() {
	local p
	p="$(cat "$PIDF" 2>/dev/null)"
	[ -n "$p" ] && kill -0 "$p" 2>/dev/null && { echo "$p"; return 0; }
	p="$(pgrep -f "$NFQWS" 2>/dev/null | head -n 1)"
	[ -n "$p" ] && { echo "$p"; return 0; }
	return 1
}
nfqws_running() { nfqws_pid >/dev/null; }
nfqws_ver() { cat "$ZM_ETC/nfqws.ver" 2>/dev/null; }
other_nfqws() {
	local p
	for p in $(pgrep nfqws 2>/dev/null); do
		case "$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null)" in *"$NFQWS"*) ;; *) echo "$p"; return 0 ;; esac
	done
	return 1
}
nfqws_check() {
	local f="${1:-$OPT}" out a
	[ -x "$NFQWS" ] || { echo "нет программы nfqws"; return 1; }
	a="$(opt_args "$f")"
	[ -n "$(printf '%s' "$a" | tr -d ' ')" ] || { echo "блок стратегий пуст"; return 1; }
	set -f
	out="$("$NFQWS" --dry-run --qnum=$QNUM $a 2>&1)" || { set +f; printf '%s\n' "$out" | grep -v '^$' | tail -n 6; return 1; }
	set +f
	return 0
}
zapret_start() {
	local a extra="" n
	conf_defaults
	[ -x "$NFQWS" ] || { echo "nfqws не установлен"; return 1; }
	[ -s "$OPT" ] || strategy_build > /dev/null
	if nfqws_running; then echo "nfqws уже работает"; return 0; fi
	if other_nfqws >/dev/null; then zm_log "найден другой nfqws (pid $(other_nfqws)) — возможен двойной обход"; fi
	kmods
	sysctl -w net.netfilter.nf_conntrack_checksum=0 >/dev/null 2>&1
	sysctl -w net.netfilter.nf_conntrack_tcp_be_liberal=1 >/dev/null 2>&1
	n="$(echo $(wan_ifaces) | wc -w)"
	[ "$n" -gt 1 ] 2>/dev/null && { extra="--bind-fix4"; [ "$(c IPV6 0)" = 1 ] && extra="$extra --bind-fix6"; }
	[ "$(c LOG 0)" = 1 ] && extra="--debug=syslog $extra"
	chmod -R a+rX "$IPS" "$ZAP/files" 2>/dev/null
	a="$(opt_args)"
	mkdir -p "$ZM_RUN"
	set -f
	"$NFQWS" --daemon --pidfile="$PIDF" --user=nobody --qnum=$QNUM $extra $a > "$ZM_TMP/nfqws.start" 2>&1
	set +f
	n=0
	while [ "$n" -lt 10 ]; do nfqws_running && break; sleep 1; n=$((n + 1)); done
	if ! nfqws_running; then
		zm_log "nfqws не запустился: $(tail -n 3 "$ZM_TMP/nfqws.start" 2>/dev/null | tr '\n' ' ')"
		echo "nfqws не запустился: $(tail -n 3 "$ZM_TMP/nfqws.start" 2>/dev/null | tr '\n' ' ')"
		return 1
	fi
	fw_apply
	zm_log "zapret запущен (WAN: $(wan_ifaces))"
	return 0
}
zapret_stop() {
	local p n=0
	fw_remove
	p="$(cat "$PIDF" 2>/dev/null)"
	[ -n "$p" ] && kill "$p" 2>/dev/null
	for p in $(pgrep -f "$NFQWS" 2>/dev/null); do kill "$p" 2>/dev/null; done
	while nfqws_running && [ "$n" -lt 5 ]; do sleep 1; n=$((n + 1)); done
	for p in $(pgrep -f "$NFQWS" 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
	rm -f "$PIDF"
	zm_log "zapret остановлен"
	return 0
}
zapret_restart() {
	zapret_stop >/dev/null
	[ "$(c ENABLED 1)" = 1 ] || { fw_table iptables filter; return 0; }
	zapret_start
}

F_EX="--hostlist-exclude=$L_EXCL"
strat_v() {
	local F="$FAKE"
	case "$1" in
		v1)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=split2" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-seqovl-pattern=$F/stun.bin" ;;
		v2)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=$F/stun.bin" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" ;;
		v3)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=ozon.ru" "--dpi-desync-repeats=4" "--dpi-desync-fooling=ts,md5sig" "--dpi-desync-badseq-increment=0" ;;
		v4)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=582" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=$F/stun.bin" ;;
		v5)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=fake,fakeddisorder" "--dpi-desync-split-pos=1" "--dpi-desync-fake-tls=$F/stun.bin" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-fakedsplit-pattern=$F/tls_clienthello_www_google_com.bin" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-badseq-increment=0" ;;
		v6)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=i2.photo.2gis.com" "--dpi-desync-hostfakesplit-midhost=host-2" "--dpi-desync-split-seqovl=726" "--dpi-desync-fooling=badsum,badseq" "--dpi-desync-badseq-increment=0" ;;
		v7)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=654" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=$F/stun.bin" "--dpi-desync-fake-tls=$F/stun.bin" "--dpi-desync-badseq-increment=0" ;;
		v8)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=fake" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=$F/4pda.bin" "--dpi-desync-fake-tls-mod=none" ;;
		v9)  printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=hostfakesplit" "--dpi-desync-fooling=badseq,badsum" "--dpi-desync-hostfakesplit-mod=host=ozon.ru" "--dpi-desync-badseq-increment=0" ;;
		v10) printf '%s\n' "--filter-tcp=443" "$F_EX" "--dpi-desync=fake,split2" "--dpi-desync-split-pos=2" "--dpi-desync-fake-tls=$F/tls_clienthello_www_google_com.bin" "--dpi-desync-hostfakesplit-mod=host=maxcdn.bootstrapcdn.com" "--dpi-desync-fake-tls-mod=rnd,sni=maxcdn.bootstrapcdn.com" "--dpi-desync-fooling=ts" ;;
		*) return 1 ;;
	esac
}
strat_dv() {
	local G="$FAKE/tls_clienthello_www_google_com.bin"
	printf '%s\n' "--filter-tcp=$DISCORD_TCP" "--hostlist-domains=discord.media"
	case "$1" in
		1|4) printf '%s\n' "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=652" "--dpi-desync-split-pos=2" "--dpi-desync-split-seqovl-pattern=$G" ;;
		2|11) printf '%s\n' "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=$G" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" ;;
		3) printf '%s\n' "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=$G" "--dpi-desync-fake-tls-mod=none" ;;
		5) printf '%s\n' "--dpi-desync=fake,multisplit" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=1000" "--dpi-desync-fake-tls=$G" ;;
		6) printf '%s\n' "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=$G" ;;
		7) printf '%s\n' "--dpi-desync=multisplit" "--dpi-desync-split-pos=2,sniext+1" "--dpi-desync-split-seqovl=679" "--dpi-desync-split-seqovl-pattern=$G" ;;
		8) printf '%s\n' "--dpi-desync=fake" "--dpi-desync-fake-tls-mod=none" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2" ;;
		9) printf '%s\n' "--dpi-desync=fake,fakedsplit" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2" "--dpi-desync-repeats=8" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" ;;
		10) printf '%s\n' "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=681" "--dpi-desync-split-pos=1" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=10000000" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=$G" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" ;;
		12) printf '%s\n' "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=badseq" "--dpi-desync-badseq-increment=2" "--dpi-desync-fake-tls=$G" ;;
		13) printf '%s\n' "--dpi-desync=fake" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fake-tls=$G" ;;
		14) printf '%s\n' "--dpi-desync=fake,fakedsplit" "--dpi-desync-repeats=6" "--dpi-desync-fooling=ts" "--dpi-desync-fakedsplit-pattern=0x00" "--dpi-desync-fake-tls=$G" ;;
		15) printf '%s\n' "--dpi-desync=fake,multidisorder" "--dpi-desync-split-pos=1,midsld" "--dpi-desync-repeats=11" "--dpi-desync-fooling=badseq" "--dpi-desync-fake-tls=0x00000000" "--dpi-desync-fake-tls=$G" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" ;;
		16) printf '%s\n' "--dpi-desync=fake,hostfakesplit" "--dpi-desync-fake-tls-mod=rnd,dupsid,sni=www.google.com" "--dpi-desync-hostfakesplit-mod=host=www.google.com,altorder=1" "--dpi-desync-fooling=ts" ;;
		17) printf '%s\n' "--dpi-desync=hostfakesplit" "--dpi-desync-repeats=4" "--dpi-desync-fooling=ts" "--dpi-desync-hostfakesplit-mod=host=www.google.com" ;;
		*) return 1 ;;
	esac
}
strat_yv_builtin() {
	local G="--hostlist=$L_GOOGLE" F="$FAKE"
	case "$1" in
		Yv08) printf '%s\n' "--filter-tcp=443" "$G" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=google.com" "--dpi-desync-fooling=ts" ;;
		Yv28) printf '%s\n' "--filter-tcp=443" "$G" "--dpi-desync=fake,multidisorder" "--dpi-desync-split-seqovl=midsld-4" "--dpi-desync-split-pos=2,midsld+3,sniext+2,endhost-2,midsld-3,host+1,-10" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=23" "--dpi-desync-split-seqovl-pattern=$F/tls_clienthello_www_sferum_ru.bin" "--dpi-desync-fake-tls=$F/stun2.bin" "--dpi-desync-fake-tls=$F/tls_clienthello_www_sferum_ru.bin" "--dpi-desync-fake-tls=$F/stun.bin" "--dpi-desync-fake-http=$F/tls_clienthello_max_ru.bin" ;;
		Yv29) printf '%s\n' "--filter-tcp=443" "$G" "--dpi-desync=hostfakesplit" "--dpi-desync-fooling=ts" "--dpi-desync-hostfakesplit-mod=host=www.google.com" "--dpi-desync-hostfakesplit-midhost=midsld+1" ;;
		Yv30) printf '%s\n' "--filter-tcp=443" "$G" "--dpi-desync=hostfakesplit" "--dpi-desync-fooling=ts" "--dpi-desync-hostfakesplit-mod=host=www.google.com" "--dpi-desync-hostfakesplit-midhost=sld+1" ;;
		Yv31) printf '%s\n' "--filter-tcp=443" "$G" "--dpi-desync=fake,multisplit" "--dpi-desync-split-seqovl=717" "--dpi-desync-split-pos=sld,sld+3,endhost-1" "--dpi-desync-fooling=ts" "--dpi-desync-repeats=8" "--dpi-desync-split-seqovl-pattern=$F/tls_clienthello_www_google_com_2.bin" "--dpi-desync-fake-tls=$F/tls_clienthello_www_google_com_2.bin" ;;
		*) return 1 ;;
	esac
}
strat_yv() {
	local b
	if [ -s "$YV_FILE" ] && grep -qx "#$1" "$YV_FILE"; then
		b="$(awk -v n="#$1" '$0 == n { f = 1; next } /^#Yv[0-9]/ { f = 0 } f && NF' "$YV_FILE" | sed 's/\r$//')"
		[ -n "$b" ] && { printf '%s\n' "$b" | sed "s#/opt/zapret/#$ZAP/#g"; return 0; }
	fi
	strat_yv_builtin "$1"
}
yv_ids() {
	{ echo Yv08; [ -s "$YV_FILE" ] && grep -oE '^#Yv[0-9]+' "$YV_FILE" | sed 's/^#//'; for n in 28 29 30 31; do echo "Yv$n"; done; } | awk '!s[$0]++' | sort -t v -k 2 -n
}
strat_game() {
	local n="$1" x="$2" pu="$PORTS_UDP_GAME" pt="$PORTS_TCP_GAME"
	[ "$x" = 1 ] && { pu="$PORTS_XTREME"; pt="$PORTS_XTREME"; }
	printf '%s\n' "--new" "#Gv$n$([ "$x" = 1 ] && echo Xtreme)" "--filter-udp=$pu" "--dpi-desync=fake" "--dpi-desync-any-protocol=1" "--dpi-desync-fake-unknown-udp=$FAKE/stun.bin"
	if [ "$n" = 1 ]; then printf '%s\n' "--dpi-desync-cutoff=d2"; else printf '%s\n' "--dpi-desync-repeats=10" "--dpi-desync-cutoff=n$n"; fi
	printf '%s\n' "--new" "--filter-tcp=$pt" "--dpi-desync-any-protocol=1" "--dpi-desync-cutoff=n5" "--dpi-desync=multisplit" "--dpi-desync-split-seqovl=582" "--dpi-desync-split-pos=1" "--dpi-desync-split-seqovl-pattern=$FAKE/stun.bin"
}
strat_discord() {
	printf '%s\n' "--new" "#Discord" "--filter-udp=$DISCORD_UDP" "--filter-l7=discord,stun" "--dpi-desync=fake" "--dpi-desync-fake-discord=$FAKE/stun.bin" "--dpi-desync-fake-stun=$FAKE/stun.bin" "--dpi-desync-repeats=6" "--new" "#Dv$1"
	strat_dv "$1"
}
strat_quic() {
	printf '%s\n' "#udp443" "--filter-udp=443" "--hostlist=$L_GOOGLE" "--dpi-desync=fake" "--dpi-desync-repeats=11" "--dpi-desync-fake-quic=$FAKE/quic_initial_www_google_com.bin" "--new"
}
doh_domains() {
	local d
	d="$(doh_list 2>/dev/null | awk '{ u = tolower($2); sub(/^https:\/\//, "", u); sub(/[\/:?].*$/, "", u); if (u ~ /^[a-z0-9.-]*[a-z][a-z0-9.-]*$/ && !s[u]++) print u }' | head -n 12 | tr '\n' ',' | sed 's/,$//')"
	echo "${d:-$DOH_DEF}"
}
strat_doh() {
	printf '%s\n' "#DoH" "--hostlist-domains=$(doh_domains)"
	printf '%s\n' $DOH_TPL
	echo "--new"
}
main_lists() {
	case "$(s LISTS all)" in
		user) sed "s#^$F_EX\$#--hostlist=$L_USER#" ;;
		rkn) awk -v ex="$F_EX" -v u="--hostlist=$L_USER" -v r="--hostlist=$L_RKN" '$0 == ex { print u; print r; next } { print }' ;;
		*) cat ;;
	esac
}
strategy_build() {
	local main yt dv gv out
	conf_defaults
	[ "$(s EXPERT 0)" = 1 ] && [ -s "$OPT" ] && { cat "$OPT"; return 0; }
	main="$(s MAIN v7)"; yt="$(s YT Yv08)"; dv="$(s DISCORD 1)"; gv="$(s GAME off)"
	out="$ZM_TMP/opt.build"
	mkdir -p "$ZM_TMP"
	{
		[ "$(s DOH 0)" = 1 ] && strat_doh
		[ "$(s QUIC 0)" = 1 ] && strat_quic
		case "$main" in
			fs:*)
				awk -v n="#${main#fs:}" '$0 == n { f = 1; print; next } /^#/ && f { exit } f' "$FS_FILE" 2>/dev/null | sed "s#/opt/zapret/#$ZAP/#g" ;;
			*)
				if [ "$yt" != off ] && strat_yv "$yt" > "$out.yv" 2>/dev/null && [ -s "$out.yv" ]; then echo "#$yt"; cat "$out.yv"; echo "--new"; fi
				rm -f "${out:?}.yv"
				if [ "$main" != off ]; then echo "#$main"; strat_v "$main" | main_lists; fi
				re "$dv" '^([1-9]|1[0-7])$' && strat_discord "$dv"
				re "$gv" '^[1-4]$' && strat_game "$gv" "$(s XTREME 0)" ;;
		esac
	} | awk '
		{ sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, "") }
		$0 == "" { next }
		$0 == "--new" { if (n == 0 || last == "--new") next; b[++n] = $0; last = $0; next }
		{ b[++n] = $0; if ($0 !~ /^#/) last = $0 }
		END {
			while (n > 0 && (b[n] == "--new" || b[n] ~ /^#/)) n--
			for (i = 1; i <= n; i++) print b[i]
		}'
}
strategy_label() {
	local m o=""
	m="$(s MAIN v7)"
	[ "$(s EXPERT 0)" = 1 ] && { echo "Свой блок (экспертный режим)"; return; }
	case "$m" in fs:*) o="Flowseal: ${m#fs:}" ;; off) o="без основной стратегии" ;; *) o="Стратегия $m" ;; esac
	case "$m" in fs:*) ;; *)
		[ "$(s YT Yv08)" != off ] && o="$o · YouTube $(s YT Yv08)"
		re "$(s DISCORD 1)" '^[0-9]+$' && o="$o · Discord Dv$(s DISCORD 1)"
		re "$(s GAME off)" '^[1-4]$' && o="$o · Игры Gv$(s GAME)$([ "$(s XTREME 0)" = 1 ] && echo ' Xtreme')" ;;
	esac
	[ "$(s QUIC 0)" = 1 ] && o="$o · QUIC"
	[ "$(s DOH 0)" = 1 ] && o="$o · DoH"
	case "$(s LISTS all)" in user) o="$o · только свой список" ;; rkn) o="$o · свой список + РКН" ;; esac
	echo "$o"
}

google_list_ensure() {
	[ -s "$L_GOOGLE" ] && grep -q googlevideo.com "$L_GOOGLE" && return 0
	mkdir -p "$IPS"
	{
		[ -f "$L_GOOGLE" ] && cat "$L_GOOGLE"
		[ -f "$ZM_DIR/defaults/zapret-hosts-google.txt" ] && cat "$ZM_DIR/defaults/zapret-hosts-google.txt"
		printf '%s\n' youtube.com youtu.be googlevideo.com ytimg.com ggpht.com googleapis.com googleusercontent.com youtubei.googleapis.com
		printf '%s\n' gvt1.com googleplay.com play.google.com beacons.gvt2.com play.googleapis.com play-fe.googleapis.com lh3.googleusercontent.com android.clients.google.com connectivitycheck.gstatic.com play-lh.googleusercontent.com play-games.googleusercontent.com prod-lt-playstoregatewayadapter-pa.googleapis.com youtubei.youtube.com cloudfunctions.net
	} | sed 's/\r$//' | grep -v '^$' | sort -u > "$L_GOOGLE.n" && mv -f "$L_GOOGLE.n" "$L_GOOGLE"
}
exclude_fetch() {
	local t="$ZM_TMP/excl.dl"
	mkdir -p "$ZM_TMP" "$IPS"
	if fetch "$EXCLUDE_URL" "$t" 30 || fetch "$EXCLUDE_URL2" "$t" 30; then
		sed 's/\r$//' "$t" > "$L_EXCL"; rm -f "$t"
		good "Список исключений обновлён: $(grep -c . "$L_EXCL") доменов"
		return 0
	fi
	[ -s "$L_EXCL" ] || { [ -f "$ZM_DIR/defaults/zapret-hosts-user-exclude.txt" ] && cp -f "$ZM_DIR/defaults/zapret-hosts-user-exclude.txt" "$L_EXCL"; }
	[ -f "$L_EXCL" ] || : > "$L_EXCL"
	warn "Список исключений не скачался ($ZM_FETCH_ERR) — оставлен прежний"
	return 0
}
fake_missing() {
	cat "$@" 2>/dev/null | grep -oE "/opt/zapret/files/fake/[A-Za-z0-9_.-]+\.bin" | sed 's#.*/##' | sort -u | while read -r f; do [ -s "$FAKE/$f" ] || echo "$f"; done
}
fake_get() {
	local f="$1" u
	mkdir -p "$FAKE"
	for u in $FAKE_SRC; do
		if ZM_FETCH_ANY=1 fetch "$u/$f" "$FAKE/$f.dl" 30; then mv -f "$FAKE/$f.dl" "$FAKE/$f"; chmod a+r "$FAKE/$f"; return 0; fi
	done
	rm -f "${FAKE:?}/${f:?}.dl"
	return 1
}
fake_ensure() {
	local m f
	m="$(fake_missing "$@")"
	[ -n "$m" ] || return 0
	say "Докачиваем fake-файлы: $(echo $m | wc -w)"
	for f in $m; do
		if fake_get "$f"; then good "$f"; else warn "$f не скачался — стратегия с ним может не работать"; fi
	done
	return 0
}

opt_profiles() { opt_clean "${1:-$OPT}" | grep -cx -- '--new' | awk '{ print $1 + 1 }'; }
do_apply() {
	local new="$ZM_TMP/opt.new" r
	conf_defaults
	say "Собираем блок стратегий: $(strategy_label)"
	google_list_ensure
	[ -s "$L_EXCL" ] || exclude_fetch
	if [ "$(s LISTS all)" = rkn ] && [ ! -s "$L_RKN" ]; then rkn_fetch || return 1; fi
	case "$(s MAIN)" in fs:*) [ -s "$FS_FILE" ] || { echo "ОШИБКА: список Flowseal не загружен"; return 1; } ;; esac
	if [ "$(s EXPERT 0)" = 1 ]; then cp -f "$OPT" "$new" 2>/dev/null; else strategy_build > "$new"; fi
	[ -s "$new" ] || { echo "ОШИБКА: блок стратегий получился пустым"; return 1; }
	good "Профилей в блоке: $(opt_profiles "$new")"
	fake_ensure "$new"
	if [ -x "$NFQWS" ]; then
		say "Проверяем блок программой nfqws"
		if ! r="$(nfqws_check "$new")"; then
			echo "ОШИБКА: nfqws не принял блок стратегий — прежний блок оставлен"
			printf '%s\n' "$r" | sed 's/^/   /'
			return 1
		fi
		good "nfqws принял все параметры"
	fi
	[ "$(s EXPERT 0)" = 1 ] || cp -f "$new" "$OPT"
	rm -f "$new"
	if [ "$(c ENABLED 1)" != 1 ]; then good "Блок записан. Zapret выключен — включите его на дашборде"; return 0; fi
	say "Перезапускаем Zapret"
	if r="$(zapret_restart)"; then good "Zapret работает · WAN: $(wan_ifaces)"; else echo "ОШИБКА: $r"; return 1; fi
	return 0
}
strategy_set() {
	local main="$1" yt="$2" quic="$3" dv="$4" gv="$5" xt="$6" lists="$7" doh="$8"
	conf_defaults
	case "$main" in v[1-9]|v10|off) ;; fs:*) grep -qxF "#${main#fs:}" "$FS_FILE" 2>/dev/null || { err "стратегия Flowseal не найдена — обновите список"; return 1; } ;; *) err "неизвестная основная стратегия"; return 1 ;; esac
	case "$yt" in off) ;; Yv[0-9]*) yv_ids | grep -qx "$yt" || { err "стратегия YouTube не найдена"; return 1; } ;; *) err "неизвестная стратегия YouTube"; return 1 ;; esac
	re "$dv" '^(off|[1-9]|1[0-7])$' || { err "неизвестная стратегия Discord"; return 1; }
	re "$gv" '^(off|[1-4])$' || { err "неизвестная игровая стратегия"; return 1; }
	re "$lists" '^(all|user|rkn)$' || { err "неизвестный режим списков"; return 1; }
	for x in "$quic" "$xt" "$doh"; do re "$x" '^[01]$' || { err "некорректный переключатель"; return 1; }; done
	if jobs_busy >/dev/null; then err "сейчас выполняется задача: $(jobs_busy) — дождитесь окончания"; return 1; fi
	cfg_set "$STATE" MAIN "$main"; cfg_set "$STATE" YT "$yt"; cfg_set "$STATE" QUIC "$quic"
	cfg_set "$STATE" DISCORD "$dv"; cfg_set "$STATE" GAME "$gv"; cfg_set "$STATE" XTREME "$xt"
	cfg_set "$STATE" LISTS "$lists"; cfg_set "$STATE" DOH "$doh"; cfg_set "$STATE" EXPERT 0
	job_start apply do_apply
}
strategy_get() {
	local fs="[]" yv
	conf_defaults
	[ -s "$FS_FILE" ] && fs="$(grep '^#' "$FS_FILE" | sed 's/^#//' | jq -R . | jq -sc .)"
	yv="$(yv_ids | jq -R . | jq -sc .)"
	printf '{"main":"%s","yt":"%s","quic":%s,"discord":"%s","game":"%s","xtreme":%s,"lists":"%s","doh":%s,"expert":%s,"label":"%s","flowseal":%s,"youtube":%s,"yt_loaded":%s,"rkn_count":%s,"user_count":%s,"opt":%s,"ports_tcp":"%s","ports_udp":"%s"}\n' \
		"$(esc "$(s MAIN v7)")" "$(s YT Yv08)" "$(jb [ "$(s QUIC 0)" = 1 ])" "$(s DISCORD 1)" "$(s GAME off)" "$(jb [ "$(s XTREME 0)" = 1 ])" \
		"$(s LISTS all)" "$(jb [ "$(s DOH 0)" = 1 ])" "$(jb [ "$(s EXPERT 0)" = 1 ])" "$(esc "$(strategy_label)")" "$fs" "$yv" \
		"$(jb [ -s "$YV_FILE" ])" "$(cnt "$L_RKN")" "$(cnt "$L_USER")" \
		"$(jstr_file "$OPT")" "$(opt_ports tcp)" "$(opt_ports udp)"
}
strategy_preview() {
	local t="$ZM_TMP/preview.state"
	mkdir -p "$ZM_TMP"
	cp -f "$STATE" "$t"
	STATE="$t"
	cfg_set "$STATE" MAIN "$1"; cfg_set "$STATE" YT "$2"; cfg_set "$STATE" QUIC "$3"; cfg_set "$STATE" DISCORD "$4"
	cfg_set "$STATE" GAME "$5"; cfg_set "$STATE" XTREME "$6"; cfg_set "$STATE" LISTS "$7"; cfg_set "$STATE" DOH "$8"; cfg_set "$STATE" EXPERT 0
	strategy_build > "$ZM_TMP/preview.opt"
	printf '{"opt":%s,"ports_tcp":"%s","ports_udp":"%s","profiles":%s}\n' "$(jstr_file "$ZM_TMP/preview.opt")" "$(opt_ports tcp "$ZM_TMP/preview.opt")" "$(opt_ports udp "$ZM_TMP/preview.opt")" "$(opt_profiles "$ZM_TMP/preview.opt")"
	rm -f "$t" "$ZM_TMP/preview.opt"
}
opt_set() {
	local f="$1" r
	[ -s "$f" ] || { err "блок пустой"; return 1; }
	sed -i 's/\r$//' "$f"
	if [ -x "$NFQWS" ]; then
		fake_missing "$f" > "$ZM_TMP/opt.miss"
		if [ ! -s "$ZM_TMP/opt.miss" ]; then
			r="$(nfqws_check "$f")" || { err "nfqws не принял блок: $(printf '%s' "$r" | tail -n 3 | tr '\n' ' ')"; return 1; }
		fi
	fi
	if jobs_busy >/dev/null; then err "сейчас выполняется задача: $(jobs_busy)"; return 1; fi
	cp -f "$f" "$OPT"
	cfg_set "$STATE" EXPERT 1
	job_start apply do_apply
}
opt_reset() {
	cfg_set "$STATE" EXPERT 0
	job_start apply do_apply
}

do_yv_download() {
	local t="$ZM_TMP/yv.dl"
	say "Скачиваем стратегии для YouTube"
	fetch "$STR_URL" "$t" 30 || { echo "ОШИБКА: $ZM_FETCH_ERR"; return 1; }
	sed 's/\r$//' "$t" > "$YV_FILE"; rm -f "$t"
	good "Стратегий: $(grep -c '^#Yv' "$YV_FILE")"
	fake_ensure "$YV_FILE"
	return 0
}
rkn_fetch() {
	local t="$ZM_TMP/rkn.dl"
	say "Скачиваем список РКН"
	fetch "$RKN_URL" "$t" 60 || { echo "ОШИБКА: $ZM_FETCH_ERR"; return 1; }
	sed 's/\r$//' "$t" | grep -v '^[[:space:]]*$' > "$L_RKN"; rm -f "$t"
	good "Доменов в списке РКН: $(grep -c . "$L_RKN")"
	return 0
}
do_rkn_update() {
	rkn_fetch || return 1
	[ "$(s LISTS all)" = rkn ] && nfqws_running && { kill -HUP "$(nfqws_pid)" 2>/dev/null; good "nfqws перечитал списки"; }
	return 0
}
do_fs_download() {
	local zip="$ZM_TMP/flowseal.zip" tmp="$ZM_TMP/flowseal" out="$ZM_TMP/flowseal.txt" base F n fb fn
	if ! zm_has unzip; then
		say "Ставим unzip"
		opkg install unzip >/dev/null 2>&1
		zm_has unzip || { echo "ОШИБКА: unzip не установился"; return 1; }
	fi
	say "Скачиваем архив Flowseal"
	fetch "$FLOWSEAL_ZIP" "$zip" 300 || { echo "ОШИБКА: $ZM_FETCH_ERR"; return 1; }
	unzip -tq "$zip" >/dev/null 2>&1 || { echo "ОШИБКА: архив повреждён"; rm -f "$zip"; return 1; }
	good "Архив скачан: $(($(wc -c < "$zip") / 1024)) КБ"
	rm -rf "${tmp:?}"; mkdir -p "$tmp"
	unzip -oq "$zip" -d "$tmp" || { echo "ОШИБКА распаковки"; rm -rf "${tmp:?}" "$zip"; return 1; }
	base="$(find "$tmp" -maxdepth 1 -type d -name 'zapret-discord-youtube*' | head -n 1)"
	[ -n "$base" ] || { echo "ОШИБКА: в архиве нет стратегий"; rm -rf "${tmp:?}" "$zip"; return 1; }
	say "Разбираем .bat-стратегии"
	: > "$out"
	find "$base" -maxdepth 1 -type f -name 'general*.bat' ! -name 'general (ALT5).bat' | sort | while read -r F; do
		n="$(basename "$F" .bat)"
		sed 's/\r$//' "$F" | grep -E '^--filter-udp=19294-19344,50000-50100|^--filter-tcp=%GameFilterTCP%|^--filter-udp=%GameFilterUDP%|^--filter-tcp=2053,2083,2087,2096,8443|^--filter-tcp=443 --hostlist="%LISTS%list-google.txt"|^--filter-tcp=80,443 --hostlist="%LISTS%list-general.txt"' > "$tmp/m.txt"
		[ -s "$tmp/m.txt" ] || continue
		{
			echo "#$n"
			awk '{ sub(/[ \t]*\^[ \t]*$/, ""); n = split($0, a, / --/); for (i = 1; i <= n; i++) { x = a[i]; if (i > 1) x = "--" x; sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); if (x != "") print x } }' "$tmp/m.txt"
		} >> "$out"
	done
	sed -i \
		-e '/--hostlist="%LISTS%list-general.txt"/d' -e '/--ipset="%LISTS%ipset-all.txt"/d' -e '/--hostlist="%LISTS%list-general-user.txt"/d' \
		-e '/--ipset-exclude="%LISTS%ipset-exclude.txt"/d' -e '/--ipset-exclude="%LISTS%ipset-exclude-user.txt"/d' -e '/--hostlist-exclude="%LISTS%list-exclude-user.txt"/d' \
		-e 's|"%LISTS%list-exclude.txt"|/opt/zapret/ipset/zapret-hosts-user-exclude.txt|g' \
		-e 's|"%LISTS%list-google.txt"|/opt/zapret/ipset/zapret-hosts-google.txt|g' \
		-e 's|"%BIN%ACTIVE_DISCORD_UDP.bin"|/opt/zapret/files/fake/quic_initial_steamcommunity_com.bin|g' \
		-e 's|"%BIN%ACTIVE_GAME_UDP.bin"|/opt/zapret/files/fake/quic_initial_4pda_to.bin|g' \
		-e 's|"%BIN%\([A-Za-z0-9_.-]*\.bin\)"|/opt/zapret/files/fake/\1|g' -e 's|%BIN%\([A-Za-z0-9_.-]*\.bin\)|/opt/zapret/files/fake/\1|g' \
		-e 's|\^!|/opt/zapret/files/fake/tls_clienthello_www_google_com.bin|g' \
		-e "s|%GameFilterTCP%|$PORTS_TCP_GAME|g" -e "s|%GameFilterUDP%|$PORTS_UDP_GAME|g" \
		-e 's/[[:space:]]\+$//' -e '/^[[:space:]]*$/d' "$out"
	awk '{ if ($0 == "--new" && (p == "--new" || p ~ /^#/ || p == "")) next; print; p = $0 }' "$out" > "$out.n" && mv -f "$out.n" "$out"
	n="$(grep -oE '%[A-Za-z_]+%' "$out" | sort -u | tr '\n' ' ')"
	[ -n "$n" ] && warn "В стратегиях остались неизвестные подстановки: $n"
	mkdir -p "$FAKE"
	for fb in "$base"/bin/*.bin; do
		[ -s "$fb" ] || continue
		fn="${fb##*/}"
		case "$fn" in ACTIVE_*) continue ;; esac
		cp -f "$fb" "$FAKE/$fn"
	done
	chmod -R a+rX "$FAKE" 2>/dev/null
	rm -rf "${tmp:?}" "$zip"
	grep -q '^#' "$out" || { echo "ОШИБКА: в архиве не нашлось ни одной стратегии"; rm -f "$out"; return 1; }
	mv -f "$out" "$FS_FILE"
	fake_ensure "$FS_FILE"
	good "Стратегий Flowseal: $(grep -c '^#' "$FS_FILE")"
	return 0
}

LIST_IDS="user exclude google rkn auto ipuser ipexclude"
list_path() {
	case "$1" in
		user) echo "$L_USER" ;; exclude) echo "$L_EXCL" ;; google) echo "$L_GOOGLE" ;; rkn) echo "$L_RKN" ;;
		auto) echo "$L_AUTO" ;; ipuser) echo "$L_IPUSER" ;; ipexclude) echo "$L_IPEXCL" ;; *) return 1 ;;
	esac
}
lists_status() {
	local id p o=""
	for id in $LIST_IDS; do
		p="$(list_path "$id")"
		o="$o${o:+,}\"$id\":{\"count\":$(cnt "$p"),\"size\":$(fsize "$p")}"
	done
	printf '{%s}\n' "$o"
}
list_get() {
	local p
	p="$(list_path "$1")" || { err "неизвестный список"; return 1; }
	printf '{"id":"%s","content":%s}\n' "$1" "$(jstr_file "$p")"
}
list_set() {
	local id="$1" f="$2" p
	p="$(list_path "$id")" || { err "неизвестный список"; return 1; }
	mkdir -p "$IPS"
	sed 's/\r$//; s/[[:space:]]*$//' "$f" | awk 'NF || NR == 1' > "$p.n" && mv -f "$p.n" "$p"
	chmod a+r "$p"
	nfqws_running && kill -HUP "$(nfqws_pid)" 2>/dev/null
	case "$id" in ipexclude) nfqws_running && zapret_restart >/dev/null ;; esac
	ok "\"count\":$(cnt "$p")"
}
list_restore() {
	case "$1" in
		exclude) exclude_fetch > /dev/null ;;
		google) rm -f "$L_GOOGLE"; google_list_ensure ;;
		rkn) rkn_fetch > /dev/null || { err "$ZM_FETCH_ERR"; return 1; } ;;
		auto) : > "$L_AUTO" ;;
		ipexclude) [ -f "$ZM_DIR/defaults/zapret-ip-exclude.txt" ] && cp -f "$ZM_DIR/defaults/zapret-ip-exclude.txt" "$L_IPEXCL" ;;
		*) err "для этого списка нет стандартной версии"; return 1 ;;
	esac
	nfqws_running && kill -HUP "$(nfqws_pid)" 2>/dev/null
	list_get "$1"
}

settings_get() {
	printf '{"enabled":%s,"wan":"%s","wan_auto":"%s","ipv6":%s,"policy":"%s","policy_exclude":%s,"policy_found":%s,"quic_block":%s,"log":%s,"pkt_tcp":"%s","pkt_udp":"%s"}\n' \
		"$(jb [ "$(c ENABLED 1)" = 1 ])" "$(esc "$(c WAN_IFACE)")" "$(esc "$(WAN_IFACE= ; CONF=/dev/null wan_ifaces)")" "$(jb [ "$(c IPV6 0)" = 1 ])" \
		"$(esc "$(c POLICY_NAME)")" "$(jb [ "$(c POLICY_EXCLUDE 0)" = 1 ])" "$(jb policy_mark)" "$(jb [ "$(c QUIC_BLOCK 0)" = 1 ])" "$(jb [ "$(c LOG 0)" = 1 ])" \
		"$(c PKT_TCP 9)" "$(c PKT_UDP 9)"
}
settings_set() {
	local wan="$1" v6="$2" pol="$3" pex="$4" qb="$5" lg="$6" pt="$7" pu="$8"
	re "$wan" '^[A-Za-z0-9_. -]{0,64}$' || { err "некорректное имя интерфейса"; return 1; }
	re "$pol" '^[A-Za-z0-9_ -]{0,32}$' || { err "имя политики: латиница, цифры, пробел, _ и -"; return 1; }
	for x in "$v6" "$pex" "$qb" "$lg"; do re "$x" '^[01]$' || { err "некорректный переключатель"; return 1; }; done
	re "$pt" '^([2-9]|1[0-9]|20)$' && re "$pu" '^([2-9]|1[0-9]|20)$' || { err "число пакетов: от 2 до 20"; return 1; }
	cfg_set "$CONF" WAN_IFACE "$(echo $wan)"; cfg_set "$CONF" IPV6 "$v6"; cfg_set "$CONF" POLICY_NAME "$pol"
	cfg_set "$CONF" POLICY_EXCLUDE "$pex"; cfg_set "$CONF" QUIC_BLOCK "$qb"; cfg_set "$CONF" LOG "$lg"
	cfg_set "$CONF" PKT_TCP "$pt"; cfg_set "$CONF" PKT_UDP "$pu"
	fw_table iptables filter; fw_table ip6tables filter
	if nfqws_running; then zapret_restart >/dev/null; fi
	settings_get
}
zapret_action() {
	case "$1" in
		start) cfg_set "$CONF" ENABLED 1; r="$(zapret_start)" || { err "$r"; return 1; } ;;
		stop) cfg_set "$CONF" ENABLED 0; zapret_stop >/dev/null ;;
		restart) cfg_set "$CONF" ENABLED 1; r="$(zapret_restart)" || { err "$r"; return 1; } ;;
		update) job_start engine do_engine_update; return ;;
		*) err "неизвестное действие"; return 1 ;;
	esac
	status
}
do_engine_update() {
	local tag arch tmp="$ZM_ROOT/opt/tmp/zm-zapret" tgz was=0
	arch="$(zm_arch)" || { echo "ОШИБКА: архитектура роутера не поддерживается"; return 1; }
	say "Узнаём последнюю версию zapret на GitHub"
	tag="$(gh_latest_tag "$ZAPRET_REPO")"
	[ -n "$tag" ] || { warn "GitHub не ответил — берём проверенную $ZAPRET_DEF_TAG"; tag="$ZAPRET_DEF_TAG"; }
	good "Версия: $tag$([ -n "$(nfqws_ver)" ] && echo ", сейчас стоит $(nfqws_ver)")"
	rm -rf "${tmp:?}"; mkdir -p "$tmp"
	tgz="$tmp/z.tgz"
	say "Скачиваем zapret-$tag (linux-$arch)"
	fetch "$GH/$ZAPRET_REPO/releases/download/$tag/zapret-$tag-openwrt-embedded.tar.gz" "$tgz" 300 || { echo "ОШИБКА: $ZM_FETCH_ERR"; rm -rf "${tmp:?}"; return 1; }
	gzip -dc "$tgz" | tar -x -C "$tmp" "zapret-$tag/binaries/linux-$arch/nfqws" "zapret-$tag/files/fake" 2>/dev/null
	[ -s "$tmp/zapret-$tag/binaries/linux-$arch/nfqws" ] || { echo "ОШИБКА: в архиве нет nfqws для linux-$arch"; rm -rf "${tmp:?}"; return 1; }
	nfqws_running && { was=1; zapret_stop >/dev/null; }
	mkdir -p "${NFQWS%/*}" "$FAKE"
	cp -f "$tmp/zapret-$tag/binaries/linux-$arch/nfqws" "$NFQWS.new" && chmod 755 "$NFQWS.new" && mv -f "$NFQWS.new" "$NFQWS"
	for f in "$tmp/zapret-$tag/files/fake/"*.bin; do [ -s "$f" ] && cp -f "$f" "$FAKE/"; done
	chmod -R a+rX "$FAKE"
	echo "$tag" > "$ZM_ETC/nfqws.ver"
	rm -rf "${tmp:?}"
	good "nfqws $tag установлен"
	if [ "$was" = 1 ] || [ "$(c ENABLED 1)" = 1 ]; then
		say "Запускаем Zapret"
		r="$(zapret_start)" && good "Zapret работает" || { echo "ОШИБКА: $r"; return 1; }
	fi
	return 0
}

rci_get() { curl -s --connect-timeout 3 -m 10 "$RCI/$1" 2>/dev/null; }
rci_post() { curl -s --connect-timeout 3 -m 20 -H 'Content-Type: application/json' -d "$1" "$RCI/" 2>/dev/null; }
rci_up() { rci_get show/version | jq -e 'type == "object"' >/dev/null 2>&1; }
rci_err() { jq -r '[.. | objects | select(.status? == "error") | .message] | first // empty' 2>/dev/null; }
cli() {
	local r e
	if rci_up; then
		r="$(rci_post "$(jq -nc --arg c "$1" '[{parse: $c}]')")"
		e="$(printf '%s' "$r" | rci_err)"
		[ -z "$e" ] && return 0
		CLI_ERR="$e"; return 1
	fi
	r="$(ndmc_cli "$1")"; e=$?
	[ "$e" = 0 ] && ! printf '%s' "$r" | grep -qi 'error' && return 0
	CLI_ERR="$(printf '%s' "$r" | tail -n 1)"; return 1
}
cfg_save() { rci_post '[{"system":{"configuration":{"save":{}}}}]' >/dev/null 2>&1 || ndmc_cli 'system configuration save' >/dev/null; }
running_config() {
	local r
	r="$(rci_get show/running-config | jq -r '.. | strings' 2>/dev/null)"
	[ -n "$r" ] && { printf '%s\n' "$r"; return 0; }
	ndmc_cli 'show running-config'
}
doh_list() {
	running_config | awk '
		/^dns-proxy[ \t]*$/ { f = 1; next }
		f && /^[^ \t]/ { f = 0 }
		f {
			sub(/^[ \t]+/, "")
			if ($1 == "https" && $2 == "upstream") print "https", $3, ($4 == "" ? "dnsm" : $4)
			else if ($1 == "tls" && $2 == "upstream") { sni = ""; port = "853"; for (i = 4; i <= NF; i++) { if ($i == "sni") sni = $(i + 1); else if ($i ~ /^[0-9]+$/) port = $i } print "tls", $3, sni, port }
		}'
}
DOH_PRESETS='cloudflare|Cloudflare|https://cloudflare-dns.com/dns-query
google|Google|https://dns.google/dns-query
quad9|Quad9|https://dns.quad9.net/dns-query
adguard|AdGuard (без рекламы)|https://dns.adguard-dns.com/dns-query
comss|Comss.one|https://dns.comss.one/dns-query
xbox|Xbox DNS|https://xbox-dns.ru/dns-query
dnsai|DNS-AI|https://dns.dns-ai.ru/dns-query
geohide_eu|GeoHide EU|https://eu.geohide.ru/dns-query
malw|Malw.link|https://dns.malw.link/dns-query
zapretmoe|Zapret.moe|https://dns.zapret.moe/dns-query
yandex|Яндекс|https://common.dot.dns.yandex.net/dns-query
dns4eu|DNS4EU|https://unfiltered.joindns4.eu/dns-query'
doh_status() {
	local items up=false
	rci_up && up=true
	items="$(doh_list | awk '{ printf "%s{\"type\":\"%s\",\"addr\":\"%s\",\"extra\":\"%s\"}", (NR > 1 ? "," : ""), $1, $2, ($1 == "tls" ? $3 : $3) }')"
	printf '{"rci":%s,"items":[%s],"presets":%s,"doh_component":%s}\n' "$up" "$items" \
		"$(printf '%s\n' "$DOH_PRESETS" | jq -R 'split("|") | {id: .[0], name: .[1], url: .[2]}' | jq -sc .)" \
		"$(jb doh_component)"
}
doh_component() { rci_get show/version | jq -e '[.. | strings] | map(select(test("dns-https|doh"; "i"))) | length > 0' >/dev/null 2>&1 || running_config | grep -q 'https upstream'; }
doh_valid() { re "$1" '^https://[A-Za-z0-9.-]+(:[0-9]{1,5})?/[A-Za-z0-9._~/?=&%-]*$'; }
doh_add() {
	local u="$1"
	doh_valid "$u" || { err "нужна ссылка вида https://сервер/dns-query"; return 1; }
	doh_list | awk '$1 == "https" { print $2 }' | grep -qxF "$u" && { doh_status; return 0; }
	cli "dns-proxy https upstream $u dnsm" || { err "роутер не принял команду: ${CLI_ERR:-нет ответа}. Проверьте, что установлен компонент «Прокси-сервер DNS-over-HTTPS»"; return 1; }
	cfg_save
	zm_log "DoH добавлен: $u"
	[ "$(s DOH 0)" = 1 ] && [ "$(s EXPERT 0)" != 1 ] && job_start apply do_apply >/dev/null
	doh_status
}
doh_del() {
	local u="$1" e t
	doh_valid "$u" || { err "некорректная ссылка"; return 1; }
	doh_has() { doh_list | awk '$1 == "https" { print $2 }' | grep -qxF "$u"; }
	doh_has || { doh_status; return 0; }
	if rci_up; then
		rci_get dns-proxy | jq -c --arg u "$u" '[.. | objects | select([.[]? | strings] | index($u))] | .[]' 2>/dev/null | while read -r e; do
			rci_post "$(jq -nc --argjson e "$e" '[{"dns-proxy": {"https": {"upstream": ($e + {"no": true})}}}]')" >/dev/null
		done
	fi
	doh_has && cli "no dns-proxy https upstream $u"
	doh_has && cli "dns-proxy no https upstream $u"
	doh_has && { err "не удалось убрать сервер — уберите его в веб-интерфейсе роутера: Сетевые правила → Интернет-фильтры"; return 1; }
	cfg_save
	zm_log "DoH убран: $u"
	[ "$(s DOH 0)" = 1 ] && [ "$(s EXPERT 0)" != 1 ] && job_start apply do_apply >/dev/null
	doh_status
}
doh_probe() {
	local u="$1" r code ct ms
	doh_valid "$u" || { err "некорректная ссылка"; return 1; }
	r="$(curl -s -o /dev/null --connect-timeout 5 -m 8 -H 'accept: application/dns-message' -w '%{http_code} %{content_type} %{time_total}' "$u?dns=AAABAAABAAAAAAAAA3d3dwdleGFtcGxlA2NvbQAAAQAB" 2>/dev/null)"
	set -- $r
	code="$1"; ct="$2"; ms="$(awk -v t="${3:-0}" 'BEGIN { printf "%d", t * 1000 }')"
	if [ "$code" = 200 ] && printf '%s' "$ct" | grep -qi 'dns-message'; then ok "\"ms\":$ms"; else printf '{"ok":false,"code":"%s"}\n' "$(esc "$code")"; fi
}

hosts_list() { rci_get ip/host | jq -c '[(if type == "array" then .[] elif type == "object" then (if has("domain") then . else .[]? end) else empty end) | select(type == "object" and has("domain")) | {domain, address}]' 2>/dev/null || echo '[]'; }
hosts_status() { printf '{"rci":%s,"items":%s,"limit":64}\n' "$(jb rci_up)" "$(hosts_list)"; }
hosts_add() {
	local d="$1" a="$2" n
	re "$d" '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$' || { err "некорректный домен"; return 1; }
	re "$a" '^([0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:]+:[0-9A-Fa-f:]*$' || { err "некорректный IP-адрес"; return 1; }
	rci_up || { err "RCI роутера недоступен"; return 1; }
	n="$(hosts_list | jq length)"
	[ "${n:-0}" -ge 64 ] && { err "в Keenetic не больше 64 статических DNS-записей"; return 1; }
	rci_post "$(jq -nc --arg d "$d" --arg a "$a" '[{ip: {host: {domain: $d, address: $a}}}]')" > "$ZM_TMP/rci.out"
	n="$(rci_err < "$ZM_TMP/rci.out")"
	[ -n "$n" ] && { err "роутер не принял запись: $n"; return 1; }
	cfg_save
	hosts_status
}
hosts_del() {
	local d="$1" a="$2"
	rci_up || { err "RCI роутера недоступен"; return 1; }
	rci_post "$(jq -nc --arg d "$d" --arg a "$a" '[{ip: {host: {domain: $d, address: $a, no: true}}}]')" >/dev/null
	cfg_save
	hosts_status
}

tg_link() {
	[ -x "$TG_INIT" ] || return 1
	"$TG_INIT" status 2>/dev/null | grep -o 'tg://proxy?[^ ]*' | head -n 1
}
tg_status() {
	local inst=false run=false ver="" port="" link=""
	[ -f "$TG_INIT" ] && inst=true
	pgrep -f tg-ws-proxy-rs >/dev/null 2>&1 && run=true
	[ -x "$TG_BIN" ] && ver="$("$TG_BIN" --version 2>/dev/null | head -n 1 | grep -oE '[0-9]+(\.[0-9]+)+' | head -n 1)"
	port="$(sed -n 's/^TG_PORT=["'\'']*\([0-9]*\).*/\1/p' "$TG_CONF_DIR/config.conf" 2>/dev/null | head -n 1)"
	[ "$run" = true ] && link="$(tg_link)"
	printf '{"installed":%s,"running":%s,"enabled":%s,"version":"%s","port":"%s","link":"%s","arch_ok":%s}\n' "$inst" "$run" "$(jb [ -x "$TG_INIT" ])" "$(esc "$ver")" "${port:-1443}" "$(esc "$link")" "$(jb zm_arch)"
}
do_tg_install() {
	local t="$ZM_ROOT/opt/tmp/tg-install.sh"
	say "Скачиваем официальный установщик TG WS Proxy (valnesfjord/tg-ws-proxy-rs)"
	mkdir -p "${t%/*}"
	fetch "$TG_INSTALL_URL" "$t" 60 || { echo "ОШИБКА: $ZM_FETCH_ERR"; return 1; }
	say "Запускаем установщик"
	sh "$t" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
	rm -f "$t"
	[ -f "$TG_INIT" ] || { echo "ОШИБКА: установщик не поставил службу"; return 1; }
	good "TG WS Proxy установлен"
	return 0
}
do_tg_remove() {
	say "Останавливаем TG WS Proxy"
	[ -x "$TG_INIT" ] && "$TG_INIT" stop >/dev/null 2>&1
	pkill -f tg-ws-proxy-rs 2>/dev/null
	say "Удаляем файлы"
	rm -rf "${TG_CONF_DIR:?}" "$TG_INIT" "$TG_BIN" "$TG_LOG" "$TG_LOG.1" "$ZM_ROOT/opt/var/tg-ws-proxy-backups"
	good "TG WS Proxy удалён"
	return 0
}
tg_action() {
	case "$1" in
		install|update) job_start tg do_tg_install ;;
		remove) job_start tg do_tg_remove ;;
		start) [ -f "$TG_INIT" ] || { err "не установлен"; return 1; }; chmod +x "$TG_INIT"; "$TG_INIT" start >/dev/null 2>&1; sleep 2; tg_status ;;
		stop) [ -f "$TG_INIT" ] || { err "не установлен"; return 1; }; "$TG_INIT" stop >/dev/null 2>&1; chmod -x "$TG_INIT"; tg_status ;;
		restart) [ -x "$TG_INIT" ] || { err "служба выключена"; return 1; }; "$TG_INIT" restart >/dev/null 2>&1; sleep 2; tg_status ;;
		*) err "неизвестное действие"; return 1 ;;
	esac
}

lan_ip() {
	local i
	i="$(ip -4 addr show br0 2>/dev/null | sed -n 's/.*inet \([0-9.]*\).*/\1/p' | head -n 1)"
	echo "${i:-192.168.1.1}"
}
sys_info() {
	local ver model fw mt mf ma up la df_t df_u
	ver="$(rci_get show/version)"
	model="$(printf '%s' "$ver" | jq -r '.model // .description // empty' 2>/dev/null)"
	fw="$(printf '%s' "$ver" | jq -r '.title // .release // empty' 2>/dev/null)"
	mt="$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)"; mf="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
	[ -n "$mf" ] || mf="$(awk '/^MemFree:|^Buffers:|^Cached:/ { s += $2 } END { print s }' /proc/meminfo)"
	up="$(cut -d. -f1 /proc/uptime)"; la="$(cut -d' ' -f1-3 /proc/loadavg)"
	set -- $(df -k /opt 2>/dev/null | awk 'NR == 2 { print $2, $3 }')
	df_t="${1:-0}"; df_u="${2:-0}"
	printf '"model":"%s","firmware":"%s","arch":"%s","kernel":"%s","mem_total":%s,"mem_free":%s,"uptime":%s,"load":"%s","opt_total":%s,"opt_used":%s,"lan_ip":"%s","kmods_missing":"%s","iptables":%s,"rci":%s' \
		"$(esc "$model")" "$(esc "$fw")" "$(zm_arch)" "$(uname -r)" "${mt:-0}" "${mf:-0}" "${up:-0}" "$la" "$df_t" "$df_u" "$(lan_ip)" "$(kmods_missing)" "$(jb zm_has iptables)" "$(jb rci_up)"
}
status() {
	conf_defaults
	printf '{"version":"%s","nfqws":"%s","installed":%s,"running":%s,"enabled":%s,"label":"%s","wan":"%s","other_nfqws":%s,"job":"%s",%s}\n' \
		"$ZM_VERSION" "$(esc "$(nfqws_ver)")" "$(jb [ -x "$NFQWS" ])" "$(jb nfqws_running)" "$(jb [ "$(c ENABLED 1)" = 1 ])" \
		"$(esc "$(strategy_label)")" "$(esc "$(wan_ifaces)")" "$(jb other_nfqws)" "$(jobs_busy)" "$(sys_info)"
}
SITES='YouTube|https://www.youtube.com/
Видео YouTube|https://redirector.googlevideo.com/
Discord|https://discord.com/
Instagram|https://www.instagram.com/
X (Twitter)|https://x.com/
Facebook|https://www.facebook.com/
Rutracker|https://rutracker.org/
Telegram Web|https://web.telegram.org/
Google|https://www.google.com/
Яндекс|https://ya.ru/'
check_sites() {
	local d="$ZM_TMP/sites" i=0 name url
	rm -rf "${d:?}"; mkdir -p "$d"
	printf '%s\n' "$SITES" > "$d.list"
	while IFS='|' read -r name url; do
		[ -n "$url" ] || continue
		i=$((i + 1))
		( r="$(curl -s -o /dev/null -r 0-0 --connect-timeout 6 -m 9 -A "Mozilla/5.0" -w '%{http_code} %{time_total}' "$url" 2>/dev/null)"; printf '%s|%s|%s\n' "$name" "$url" "$r" > "$d/$i" ) &
	done < "$d.list"
	wait
	rm -f "$d.list"
	cat "$d"/* 2>/dev/null | sort -t'|' -k1,1 | awk -F'|' '{ split($3, a, " "); code = a[1] + 0; ms = int(a[2] * 1000); printf "%s{\"name\":\"%s\",\"url\":\"%s\",\"ok\":%s,\"code\":%d,\"ms\":%d}", (NR > 1 ? "," : ""), $1, $2, (code > 0 ? "true" : "false"), code, ms }' | { printf '{"items":['; cat; printf ']}\n'; }
	rm -rf "${d:?}"
}

auth_set() {
	local p="$1" salt
	[ "${#p}" -ge 6 ] || return 1
	salt="$(rnd_hex 16)"
	mkdir -p "$ZM_ETC"
	printf '%s:%s\n' "$salt" "$(printf '%s:%s' "$salt" "$p" | sha256sum | cut -d' ' -f1)" > "$ZM_ETC/auth"
	chmod 600 "$ZM_ETC/auth"
}
auth_check() {
	local salt h
	[ -s "$ZM_ETC/auth" ] || return 1
	IFS=: read -r salt h < "$ZM_ETC/auth"
	[ -n "$h" ] && [ "$(printf '%s:%s' "$salt" "$1" | sha256sum | cut -d' ' -f1)" = "$h" ]
}

backup_make() {
	local t="$ZM_TMP/backup.tgz" f l=""
	mkdir -p "$ZM_TMP"
	for f in opt/etc/zapret-manager/zapret.conf opt/etc/zapret-manager/strategy.conf opt/etc/zapret-manager/nfqws.opt opt/etc/zapret-manager/youtube.txt opt/etc/zapret-manager/flowseal.txt \
		opt/zapret/ipset/zapret-hosts-user.txt opt/zapret/ipset/zapret-hosts-user-exclude.txt opt/zapret/ipset/zapret-hosts-google.txt opt/zapret/ipset/zapret-hosts-auto.txt opt/zapret/ipset/zapret-ip-user.txt opt/zapret/ipset/zapret-ip-exclude.txt; do
		[ -f "$ZM_ROOT/$f" ] && l="$l $f"
	done
	(cd "$ZM_ROOT/" && tar -czf "$t" $l) || return 1
	echo "$t"
}
backup_restore() {
	local f="$1" bad
	gzip -t "$f" 2>/dev/null || { err "это не архив резервной копии"; return 1; }
	bad="$(tar -tzf "$f" 2>/dev/null | grep -vE '^(opt/etc/zapret-manager/(zapret\.conf|strategy\.conf|nfqws\.opt|youtube\.txt|flowseal\.txt)|opt/zapret/ipset/zapret-[a-z-]+\.txt)$' | head -n 1)"
	[ -n "$bad" ] && { err "в архиве лишний файл: $bad"; return 1; }
	[ -n "$(tar -tzf "$f" 2>/dev/null)" ] || { err "архив пустой"; return 1; }
	(cd "$ZM_ROOT/" && tar -xzf "$f") || { err "не удалось распаковать"; return 1; }
	zm_log "настройки восстановлены из резервной копии"
	job_start apply do_apply
}

do_panel_update() {
	local t="$ZM_ROOT/opt/tmp/zm-keenetic.sh"
	say "Скачиваем новую версию панели"
	mkdir -p "${t%/*}"
	fetch "$ZM_SCRIPT_URL" "$t" 120 || { echo "ОШИБКА: $ZM_FETCH_ERR"; return 1; }
	grep -q 'Zapret Manager для Keenetic' "$t" || { echo "ОШИБКА: скачался не тот файл"; rm -f "$t"; return 1; }
	say "Устанавливаем"
	ZM_UNATTENDED=1 sh "$t" 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
	rm -f "$t"
	return 0
}
zm_uninstall() {
	local keep="$1"
	say "Останавливаем Zapret"
	zapret_stop >/dev/null 2>&1
	for t in iptables ip6tables; do command -v "$t" >/dev/null 2>&1 && fw_unchain "$t" filter zm_fwd FORWARD; done
	good "Правила файрвола сняты"
	say "Удаляем файлы панели"
	rm -f "$INIT" "$ZM_ROOT/opt/etc/ndm/netfilter.d/100-zapret-manager.sh" "$ZM_ROOT/opt/etc/lighttpd/conf.d/80-zapret-manager.conf" "$ZM_ROOT/opt/bin/zm"
	[ -x "$ZM_ROOT/opt/etc/init.d/S80lighttpd" ] && "$ZM_ROOT/opt/etc/init.d/S80lighttpd" restart >/dev/null 2>&1
	if [ "$keep" = 1 ]; then
		rm -rf "${ZM_DIR:?}" "$ZAP/nfq"
		good "Панель удалена, настройки и списки оставлены в /opt/etc/zapret-manager и /opt/zapret"
	else
		rm -rf "${ZM_DIR:?}" "${ZM_ETC:?}" "${ZAP:?}" "$ZM_LOG"
		good "Панель, Zapret, настройки и списки удалены"
	fi
	rm -rf "${ZM_TMP:?}"
	return 0
}
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/lib.sh.zm-new' '/opt/zapret-manager/lib.sh'
cat > '/opt/zapret-manager/www/api.cgi.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
. "${ZM_LIB:-/opt/zapret-manager/lib.sh}"
SESS_DIR="$ZM_TMP/sess"
BODY="$ZM_TMP/req.$$"
mkdir -p "$SESS_DIR" 2>/dev/null
chmod 700 "$ZM_TMP" "$SESS_DIR" 2>/dev/null
trap 'rm -f "$BODY" "$BODY".*' EXIT

hdr() {
	local ct="${1:-application/json; charset=utf-8}" st="${2:-200 OK}" h
	if [ $# -ge 2 ]; then shift 2; else set --; fi
	printf 'Status: %s\r\nContent-Type: %s\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\n' "$st" "$ct"
	for h in "$@"; do printf '%s\r\n' "$h"; done
	printf '\r\n'
}
deny() { hdr "" "$1"; printf '{"error":"%s","auth":%s}\n' "$(esc "$2")" "${3:-false}"; exit 0; }
qs() { printf '%s' "$QUERY_STRING" | tr '&' '\n' | sed -n "s/^$1=\([A-Za-z0-9_.-]*\)\$/\1/p" | head -n 1; }
cookie_sid() { printf '%s' "$HTTP_COOKIE" | tr ';' '\n' | sed -n 's/^[[:space:]]*zmsid=\([0-9a-f]\{32\}\)$/\1/p' | head -n 1; }
sess_ok() {
	SID="$(cookie_sid)"
	[ -n "$SID" ] && [ -f "$SESS_DIR/$SID" ] || return 1
	[ -n "$(find "$SESS_DIR/$SID" -mmin -720 2>/dev/null)" ] || { rm -f "$SESS_DIR/$SID"; return 1; }
	touch "$SESS_DIR/$SID"
}
p() { jq -r --arg k "$1" '.[$k] // empty | tostring' "$BODY" 2>/dev/null | head -n 1; }
pf() { jq -r --arg k "$1" '.[$k] // "" | tostring' "$BODY" > "$2" 2>/dev/null; }
b01() { case "$(p "$1")" in true|1) echo 1 ;; *) echo 0 ;; esac; }

A="$(qs a)"
[ "$REQUEST_METHOD" = POST ] && [ "$A" != restore ] && {
	[ "${CONTENT_LENGTH:-0}" -le 4194304 ] 2>/dev/null || deny "413 Payload Too Large" "слишком большой запрос"
	head -c "${CONTENT_LENGTH:-0}" > "$BODY"
	[ -s "$BODY" ] || echo '{}' > "$BODY"
	jq -e 'type == "object"' "$BODY" >/dev/null 2>&1 || deny "400 Bad Request" "некорректный запрос"
}
if [ "$REQUEST_METHOD" = POST ] && [ "$HTTP_X_ZM" != 1 ]; then deny "403 Forbidden" "запрос без заголовка панели"; fi

case "$A" in
	login)
		[ "$REQUEST_METHOD" = POST ] || deny "405 Method Not Allowed" "нужен POST"
		find "$SESS_DIR" -type f -mmin +720 -exec rm -f {} \; 2>/dev/null
		if auth_check "$(jq -r '.password // ""' "$BODY")"; then
			SID="$(rnd_hex 16)"
			echo 1 > "$SESS_DIR/$SID"
			zm_log "вход в панель с ${REMOTE_ADDR:-?}"
			hdr "" "" "Set-Cookie: zmsid=$SID; Path=/; HttpOnly; SameSite=Strict; Max-Age=43200"
			ok '"auth":true'
		else
			zm_log "неверный пароль с ${REMOTE_ADDR:-?}"
			sleep 2
			deny "401 Unauthorized" "неверный пароль"
		fi
		exit 0 ;;
	session)
		hdr; if sess_ok; then printf '{"auth":true,"version":"%s"}\n' "$ZM_VERSION"; else printf '{"auth":false,"version":"%s"}\n' "$ZM_VERSION"; fi
		exit 0 ;;
esac

sess_ok || deny "401 Unauthorized" "нужно войти" false

case "$A" in
	backup)
		f="$(backup_make)" || deny "500 Internal Server Error" "не удалось собрать архив"
		hdr "application/gzip" "" "Content-Disposition: attachment; filename=\"zapret-manager-keenetic-$(date +%Y%m%d-%H%M).tar.gz\"" "Content-Length: $(wc -c < "$f")"
		cat "$f"; rm -f "$f"
		exit 0 ;;
	restore)
		[ "$REQUEST_METHOD" = POST ] || deny "405 Method Not Allowed" "нужен POST"
		[ "${CONTENT_LENGTH:-0}" -le 4194304 ] 2>/dev/null || deny "413 Payload Too Large" "архив слишком большой"
		head -c "${CONTENT_LENGTH:-0}" > "$BODY.tgz"
		hdr; backup_restore "$BODY.tgz"
		exit 0 ;;
esac

hdr
case "$A" in
	logout) rm -f "$SESS_DIR/$SID"; ok ;;
	status) status ;;
	settings_get) settings_get ;;
	settings_set) settings_set "$(p wan)" "$(b01 ipv6)" "$(p policy)" "$(b01 policy_exclude)" "$(b01 quic_block)" "$(b01 log)" "$(p pkt_tcp)" "$(p pkt_udp)" ;;
	zapret) zapret_action "$(p action)" ;;
	strategy_get) strategy_get ;;
	strategy_set) strategy_set "$(p main)" "$(p yt)" "$(b01 quic)" "$(p discord)" "$(p game)" "$(b01 xtreme)" "$(p lists)" "$(b01 doh)" ;;
	strategy_preview) strategy_preview "$(p main)" "$(p yt)" "$(b01 quic)" "$(p discord)" "$(p game)" "$(b01 xtreme)" "$(p lists)" "$(b01 doh)" ;;
	opt_set) pf content "$BODY.opt"; opt_set "$BODY.opt" ;;
	opt_reset) opt_reset ;;
	yv_refresh) job_start youtube do_yv_download ;;
	fs_refresh) job_start flowseal do_fs_download ;;
	rkn_refresh) job_start rkn do_rkn_update ;;
	lists_status) lists_status ;;
	list_get) list_get "$(p id)" ;;
	list_set) pf content "$BODY.list"; list_set "$(p id)" "$BODY.list" ;;
	list_restore) list_restore "$(p id)" ;;
	check_sites) check_sites ;;
	doh_status) doh_status ;;
	doh_add) doh_add "$(p url)" ;;
	doh_del) doh_del "$(p url)" ;;
	doh_probe) doh_probe "$(p url)" ;;
	hosts_status) hosts_status ;;
	hosts_add) hosts_add "$(p domain)" "$(p address)" ;;
	hosts_del) hosts_del "$(p domain)" "$(p address)" ;;
	tg_status) tg_status ;;
	tg) tg_action "$(p action)" ;;
	job) job_status "$(p job)" ;;
	svc_log) printf '{"lines":%s}\n' "$( [ -f "$ZM_LOG" ] && tail -n 200 "$ZM_LOG" | jq -Rs . || echo '""')" ;;
	passwd)
		auth_check "$(jq -r '.old // ""' "$BODY")" || { sleep 1; err "текущий пароль неверный"; exit 0; }
		auth_set "$(jq -r '.new // ""' "$BODY")" || { err "новый пароль — не короче 6 символов"; exit 0; }
		find "$SESS_DIR" -type f ! -name "$SID" -exec rm -f {} \; 2>/dev/null
		zm_log "пароль панели изменён"
		ok ;;
	panel_update) job_start panel do_panel_update ;;
	uninstall) job_start uninstall zm_uninstall "$(b01 keep)" ;;
	*) err "неизвестная команда" ;;
esac
exit 0
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/www/api.cgi.zm-new' '/opt/zapret-manager/www/api.cgi'
cat > '/opt/zapret-manager/www/index.html.zm-new' << 'ZM_INSTALLER_EOF'
<!doctype html>
<html lang="ru" data-theme="light">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="#f4f5f8">
<title>Zapret Manager · Keenetic</title>
<link rel="icon" href="data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27%20viewBox=%270%200%201250%201250%27%3E%3Cdefs%3E%3ClinearGradient%20id=%27z%27%20x1=%270%27%20y1=%270%27%20x2=%270%27%20y2=%271%27%3E%3Cstop%20offset=%270%27%20stop-color=%27%2300b6ff%27/%3E%3Cstop%20offset=%271%27%20stop-color=%27%230090ff%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Cg%20fill=%27url%28%23z%29%27%20stroke=%27%230a0a0a%27%20stroke-width=%2722%27%3E%3Cpolygon%20points=%27455,170%201072,118%201215,25%20688,615%2025,1235%20735,338%20262,383%27/%3E%3Cpolygon%20points=%271025,462%20722,860%201215,800%201005,1022%20315,1095%27/%3E%3C/g%3E%3C/svg%3E">
<link rel="stylesheet" href="app.css?v=__ZMW_BUILD__">
<script>
(function(){try{var t=localStorage.getItem('zmk.theme');if(t!=='dark'&&t!=='light')t=(window.matchMedia&&matchMedia('(prefers-color-scheme: dark)').matches)?'dark':'light';document.documentElement.setAttribute('data-theme',t);}catch(e){}})();
</script>
</head>
<body>
<div id="app"></div>
<noscript><p style="padding:24px;font-family:sans-serif">Для работы панели Zapret Manager нужен JavaScript.</p></noscript>
<script src="app.js?v=__ZMW_BUILD__"></script>
</body>
</html>
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/www/index.html.zm-new' '/opt/zapret-manager/www/index.html'
cat > '/opt/zapret-manager/www/app.css.zm-new' << 'ZM_INSTALLER_EOF'
:root {
	--font: system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
	--mono: ui-monospace, "SF Mono", "Cascadia Code", Consolas, "Liberation Mono", monospace;
	--bg: #f4f5f8;
	--side: #ffffff;
	--card: #ffffff;
	--card-2: #f6f7fb;
	--line: #e3e6ee;
	--line-2: #d3d8e4;
	--text: #0b0d12;
	--text-2: #3a4252;
	--muted: #6b7385;
	--accent: #2d5bff;
	--accent-ink: #ffffff;
	--accent-soft: rgba(45, 91, 255, .10);
	--ok: #0f8a5f; --ok-bg: rgba(16, 185, 129, .13); --ok-dot: #10b981;
	--bad: #c62828; --bad-bg: rgba(239, 68, 68, .11); --bad-dot: #ef4444;
	--warn: #a45d00; --warn-bg: rgba(245, 158, 11, .15); --warn-dot: #f59e0b;
	--off: #5b6475; --off-bg: rgba(100, 116, 139, .13);
	--console: #0d1220; --console-ink: #d7deef;
	--radius: 20px;
	--radius-sm: 12px;
	--shadow: 0 1px 2px rgba(0, 0, 0, .04);
	--shadow-lg: 0 24px 60px -24px rgba(15, 23, 42, .35);
	color-scheme: light;
}
html[data-theme="dark"] {
	--bg: #0a0c12;
	--side: #10131b;
	--card: #141824;
	--card-2: #1a1f2d;
	--line: #232a3a;
	--line-2: #2f384c;
	--text: #e9edf6;
	--text-2: #c4cad8;
	--muted: #8b94a8;
	--accent: #4f78ff;
	--accent-soft: rgba(79, 120, 255, .16);
	--ok: #34d399; --ok-bg: rgba(52, 211, 153, .13); --ok-dot: #34d399;
	--bad: #f87171; --bad-bg: rgba(248, 113, 113, .13); --bad-dot: #f87171;
	--warn: #fbbf24; --warn-bg: rgba(251, 191, 36, .13); --warn-dot: #fbbf24;
	--off: #9aa3b5; --off-bg: rgba(148, 163, 184, .13);
	--console: #070a12; --console-ink: #cfd7ea;
	--shadow: 0 1px 0 rgba(255, 255, 255, .02) inset;
	--shadow-lg: 0 30px 80px -30px rgba(0, 0, 0, .9);
	color-scheme: dark;
}
*, *::before, *::after { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body { font-family: var(--font); font-size: 14px; line-height: 1.5; color: var(--text); background: var(--bg); min-height: 100vh; -webkit-font-smoothing: antialiased; overflow-x: hidden; }
button, input, select, textarea { font: inherit; color: inherit; }
a { color: var(--accent); }
::selection { background: rgba(45, 91, 255, .25); }
.ico { width: 20px; height: 20px; flex-shrink: 0; display: block; }

.logo { width: 42px; height: 42px; border-radius: 13px; display: grid; place-items: center; flex-shrink: 0; background: radial-gradient(120% 90% at 30% 0%, rgba(56, 189, 248, .35), transparent 60%), linear-gradient(160deg, #13223f 0%, #0a1426 55%, #060c18 100%); box-shadow: 0 8px 22px -8px rgba(14, 165, 233, .75), inset 0 0 0 1px rgba(56, 189, 248, .28); }
.logo svg { width: 30px; height: 30px; }
.logo.big { width: 64px; height: 64px; border-radius: 19px; }
.logo.big svg { width: 46px; height: 46px; }

.shell { display: grid; grid-template-columns: 264px 1fr; min-height: 100vh; }
.side { background: var(--side); border-right: 1px solid var(--line); padding: 20px 14px; display: flex; flex-direction: column; gap: 18px; position: sticky; top: 0; height: 100vh; overflow-y: auto; }
.brand { display: flex; align-items: center; gap: 12px; padding: 4px 8px; }
.brand-name { font-weight: 800; font-size: 16px; letter-spacing: -.01em; }
.brand-sub { font-size: 12px; color: var(--muted); }
.nav { display: flex; flex-direction: column; gap: 4px; }
.nav-item { display: flex; align-items: center; gap: 12px; padding: 10px 12px; border-radius: 12px; border: 0; background: transparent; cursor: pointer; text-align: left; font-weight: 600; color: var(--text); }
.nav-item:hover { background: var(--card-2); }
.nav-item.active { background: var(--accent); color: var(--accent-ink); box-shadow: inset 0 0 0 2px #000; }
html[data-theme="dark"] .nav-item.active { box-shadow: inset 0 0 0 2px rgba(255, 255, 255, .85); }
.side-foot { margin-top: auto; display: flex; flex-direction: column; gap: 10px; font-size: 12px; color: var(--muted); padding: 0 8px; }
.meter { height: 6px; border-radius: 6px; background: var(--line); overflow: hidden; }
.meter i { display: block; height: 100%; background: var(--accent); border-radius: inherit; transition: width .4s; }
.meter.warn i { background: var(--warn-dot); }
.meter.bad i { background: var(--bad-dot); }
.meter-row { display: flex; justify-content: space-between; gap: 8px; margin-bottom: 4px; }

.main { min-width: 0; display: flex; flex-direction: column; }
.top { position: sticky; top: 0; z-index: 5; display: flex; align-items: center; gap: 12px; padding: 16px 28px; background: var(--bg); border-bottom: 1px solid transparent; }
.top.scrolled { border-bottom-color: var(--line); }
.top h1 { margin: 0; font-size: 22px; letter-spacing: -.02em; font-weight: 800; }
.top .sp { flex: 1; }
.burger { display: none; }
.view { padding: 8px 28px 120px; display: flex; flex-direction: column; gap: 16px; max-width: 1180px; width: 100%; }
.grid { display: grid; gap: 16px; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); }
.grid.two { grid-template-columns: repeat(auto-fit, minmax(380px, 1fr)); }

.card { background: var(--card); border: 1px solid var(--line); border-radius: var(--radius); box-shadow: var(--shadow); padding: 20px 22px; min-width: 0; }
.card h3 { margin: 0 0 4px; font-size: 16px; display: flex; align-items: center; gap: 10px; letter-spacing: -.01em; }
.card h3::before { content: ""; width: 4px; height: 16px; border-radius: 4px; background: var(--accent); }
.card .hint { color: var(--muted); font-size: 13px; margin: 2px 0 14px; }
.card .row { display: flex; flex-wrap: wrap; align-items: center; gap: 10px; }
.card .row + .row { margin-top: 12px; }
.kv { display: grid; grid-template-columns: auto 1fr; gap: 6px 14px; font-size: 13px; }
.kv dt { color: var(--muted); }
.kv dd { margin: 0; font-weight: 600; word-break: break-word; }
.big-num { font-size: 26px; font-weight: 800; letter-spacing: -.02em; }
.muted { color: var(--muted); }
.mono { font-family: var(--mono); font-size: 12.5px; }

.hero { display: flex; align-items: center; gap: 18px; flex-wrap: wrap; }
.hero .state { display: flex; align-items: center; gap: 14px; flex: 1; min-width: 240px; }
.dot { width: 14px; height: 14px; border-radius: 50%; background: var(--off); flex-shrink: 0; }
.dot.ok { background: var(--ok-dot); box-shadow: 0 0 0 6px var(--ok-bg); }
.dot.bad { background: var(--bad-dot); box-shadow: 0 0 0 6px var(--bad-bg); }
.dot.warn { background: var(--warn-dot); box-shadow: 0 0 0 6px var(--warn-bg); }
.hero .title { font-size: 20px; font-weight: 800; }
.hero .sub { color: var(--muted); font-size: 13px; }

.pill { display: inline-flex; align-items: center; gap: 6px; padding: 4px 10px; border-radius: 999px; font-size: 12px; font-weight: 700; background: var(--off-bg); color: var(--off); white-space: nowrap; }
.pill::before { content: ""; width: 7px; height: 7px; border-radius: 50%; background: currentColor; }
.pill.ok { background: var(--ok-bg); color: var(--ok); }
.pill.bad { background: var(--bad-bg); color: var(--bad); }
.pill.warn { background: var(--warn-bg); color: var(--warn); }

.btn { display: inline-flex; align-items: center; justify-content: center; gap: 8px; padding: 9px 16px; border-radius: 12px; border: 1px solid var(--line-2); background: var(--card); cursor: pointer; font-weight: 700; font-size: 13.5px; white-space: nowrap; transition: transform .06s, background .15s, border-color .15s; }
.btn:hover { border-color: var(--text-2); }
.btn:active { transform: translateY(1px); }
.btn.primary { background: var(--accent); border-color: var(--accent); color: var(--accent-ink); box-shadow: inset 0 0 0 2px #000; }
html[data-theme="dark"] .btn.primary { box-shadow: none; }
.btn.danger { color: var(--bad); border-color: var(--bad-bg); background: var(--bad-bg); }
.btn.ghost { border-color: transparent; background: transparent; }
.btn.sm { padding: 6px 11px; font-size: 12.5px; border-radius: 10px; }
.btn[disabled] { opacity: .5; cursor: not-allowed; transform: none; }
.btn .ico { width: 16px; height: 16px; }

.chips { display: flex; flex-wrap: wrap; gap: 8px; }
.chip { padding: 8px 14px; border-radius: 12px; border: 1px solid var(--line-2); background: var(--card); cursor: pointer; font-weight: 700; font-size: 13px; }
.chip:hover { border-color: var(--text-2); }
.chip.on { background: var(--accent); color: var(--accent-ink); border-color: var(--accent); }
.chip.sm { padding: 5px 10px; font-size: 12px; }

.field { display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.field > label { font-size: 12px; font-weight: 700; color: var(--text-2); }
.input, .select, .textarea { width: 100%; padding: 9px 12px; border-radius: 12px; border: 1px solid var(--line-2); background: var(--card); outline: none; min-width: 0; }
.input:focus, .select:focus, .textarea:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
.select { appearance: none; padding-right: 34px; background-image: linear-gradient(45deg, transparent 50%, var(--muted) 50%), linear-gradient(135deg, var(--muted) 50%, transparent 50%); background-position: calc(100% - 18px) 52%, calc(100% - 13px) 52%; background-size: 5px 5px; background-repeat: no-repeat; }
.textarea { font-family: var(--mono); font-size: 12.5px; min-height: 260px; resize: vertical; line-height: 1.55; white-space: pre; }
.form { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); align-items: end; }

.switch { display: flex; align-items: center; justify-content: space-between; gap: 14px; padding: 10px 0; cursor: pointer; }
.switch + .switch { border-top: 1px dashed var(--line); }
.switch .lbl { font-weight: 700; }
.switch .lbl small { display: block; font-weight: 400; color: var(--muted); font-size: 12.5px; }
.tgl { position: relative; width: 44px; height: 26px; flex-shrink: 0; }
.tgl input { opacity: 0; width: 0; height: 0; position: absolute; }
.tgl span { position: absolute; inset: 0; border-radius: 26px; background: var(--line-2); transition: background .2s; }
.tgl span::after { content: ""; position: absolute; width: 20px; height: 20px; left: 3px; top: 3px; border-radius: 50%; background: #fff; box-shadow: 0 1px 3px rgba(0, 0, 0, .25); transition: transform .2s; }
.tgl input:checked + span { background: var(--accent); }
.tgl input:checked + span::after { transform: translateX(18px); }

.seg { display: inline-flex; padding: 4px; border-radius: 14px; background: var(--card-2); border: 1px solid var(--line); gap: 4px; flex-wrap: wrap; }
.seg button { border: 0; background: transparent; padding: 7px 14px; border-radius: 10px; cursor: pointer; font-weight: 700; font-size: 13px; color: var(--text-2); }
.seg button.on { background: var(--card); color: var(--text); box-shadow: 0 1px 3px rgba(0, 0, 0, .12), inset 0 0 0 1px var(--line-2); }

.note { border-radius: 14px; padding: 12px 14px; font-size: 13px; background: var(--card-2); border: 1px solid var(--line); }
.note.warn { background: var(--warn-bg); border-color: transparent; color: var(--text); }
.note.bad { background: var(--bad-bg); border-color: transparent; }
.note.ok { background: var(--ok-bg); border-color: transparent; }
.note b { font-weight: 800; }
.note ol, .note ul { margin: 6px 0 0; padding-left: 20px; }

.sites { display: grid; grid-template-columns: repeat(auto-fill, minmax(170px, 1fr)); gap: 10px; margin-top: 12px; }
.site { border: 1px solid var(--line); border-radius: 14px; padding: 10px 12px; display: flex; align-items: center; gap: 10px; background: var(--card-2); }
.site .dot { width: 10px; height: 10px; }
.site .dot.ok, .site .dot.bad { box-shadow: none; }
.site b { display: block; font-size: 13px; }
.site small { color: var(--muted); }

.table { width: 100%; border-collapse: collapse; font-size: 13px; }
.table th { text-align: left; color: var(--muted); font-weight: 700; font-size: 12px; padding: 8px 10px; border-bottom: 1px solid var(--line); }
.table td { padding: 9px 10px; border-bottom: 1px solid var(--line); word-break: break-all; }
.table tr:last-child td { border-bottom: 0; }
.table td.act { width: 1%; white-space: nowrap; text-align: right; }

.console { background: var(--console); color: var(--console-ink); border-radius: 14px; padding: 14px 16px; font-family: var(--mono); font-size: 12.5px; line-height: 1.55; white-space: pre-wrap; word-break: break-word; max-height: 360px; overflow: auto; margin: 0; }
.console .ok { color: #4ade80; }
.console .er { color: #f87171; }
.console .st { color: #7dd3fc; }

.applybar { position: sticky; bottom: 16px; z-index: 4; display: flex; align-items: center; gap: 12px; flex-wrap: wrap; padding: 12px 14px 12px 20px; border-radius: 18px; background: var(--card); border: 1px solid var(--line-2); box-shadow: var(--shadow-lg); }
.applybar .sp { flex: 1; min-width: 120px; }
.applybar .lbl { font-weight: 700; font-size: 13px; }

.tabs { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 14px; }
.tab { border: 1px solid var(--line-2); background: var(--card); padding: 7px 12px; border-radius: 11px; cursor: pointer; font-weight: 700; font-size: 12.5px; display: inline-flex; gap: 8px; align-items: center; }
.tab.on { background: var(--text); color: var(--bg); border-color: var(--text); }
.tab small { font-weight: 600; opacity: .7; }

.overlay { position: fixed; inset: 0; z-index: 50; display: grid; place-items: center; padding: 16px; background: rgba(8, 12, 20, .45); backdrop-filter: blur(3px); -webkit-backdrop-filter: blur(3px); }
.modal { width: min(720px, 100%); max-height: calc(100vh - 32px); overflow: auto; background: var(--card); border: 1px solid var(--line); border-radius: 22px; box-shadow: var(--shadow-lg); padding: 22px; display: flex; flex-direction: column; gap: 14px; }
.modal h2 { margin: 0; font-size: 18px; }
.modal .foot { display: flex; justify-content: flex-end; gap: 10px; flex-wrap: wrap; }

#toasts { position: fixed; right: 16px; bottom: 16px; z-index: 60; display: flex; flex-direction: column; gap: 8px; max-width: min(420px, calc(100vw - 32px)); }
.toast { padding: 12px 16px; border-radius: 14px; background: var(--text); color: var(--bg); font-weight: 600; font-size: 13px; box-shadow: var(--shadow-lg); animation: tin .2s ease-out; }
.toast.bad { background: var(--bad); color: #fff; }
.toast.ok { background: var(--ok); color: #fff; }
@keyframes tin { from { transform: translateY(8px); opacity: 0; } }

.login { min-height: 100vh; display: grid; place-items: center; padding: 16px; }
.login .card { width: min(400px, 100%); padding: 30px 28px; display: flex; flex-direction: column; gap: 16px; text-align: center; align-items: stretch; }
.login .card h3 { justify-content: center; font-size: 20px; }
.login .card h3::before { display: none; }
.login .logo { margin: 0 auto; }

.spin { width: 16px; height: 16px; border-radius: 50%; border: 2px solid currentColor; border-right-color: transparent; animation: sp .7s linear infinite; display: inline-block; }
@keyframes sp { to { transform: rotate(360deg); } }
.skeleton { color: var(--muted); padding: 30px 0; display: flex; gap: 10px; align-items: center; }

@media (max-width: 900px) {
	.shell { grid-template-columns: 1fr; }
	.side { position: fixed; z-index: 30; left: 0; top: 0; bottom: 0; width: 264px; transform: translateX(-102%); transition: transform .2s; box-shadow: var(--shadow-lg); }
	.side.open { transform: none; }
	.burger { display: inline-flex; }
	.top { padding: 12px 16px; }
	.top h1 { font-size: 18px; }
	.view { padding: 8px 16px 110px; }
	.grid.two { grid-template-columns: 1fr; }
	.card { padding: 16px; }
	.applybar { bottom: 10px; }
	.hide-sm { display: none; }
}
.table td:first-child { white-space: nowrap; word-break: normal; }
.table td.act .btn + .btn { margin-left: 6px; }
.muted.wrap, .hint { overflow-wrap: anywhere; }
@media (max-width: 600px) {
	.table td.act { white-space: normal; text-align: left; }
	.table td.act .btn { margin: 2px 0; }
	.table td { padding: 8px 6px; }
}
a.btn { text-decoration: none; color: inherit; }
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/www/app.css.zm-new' '/opt/zapret-manager/www/app.css'
cat > '/opt/zapret-manager/www/app.js.zm-new' << 'ZM_INSTALLER_EOF'
(function () {
'use strict';

var BUILD = '__ZMW_BUILD__';
var ICONS = {
	home: '<path d="M3 11.5 12 4l9 7.5"/><path d="M5 10v10h14V10"/><path d="M10 20v-6h4v6"/>',
	bolt: '<path d="M13 2 4 14h7l-1 8 9-12h-7z"/>',
	list: '<path d="M8 6h13M8 12h13M8 18h13"/><circle cx="3.5" cy="6" r="1"/><circle cx="3.5" cy="12" r="1"/><circle cx="3.5" cy="18" r="1"/>',
	globe: '<circle cx="12" cy="12" r="9"/><path d="M3 12h18"/><path d="M12 3a14 14 0 0 1 0 18M12 3a14 14 0 0 0 0 18"/>',
	send: '<path d="M21 3 3 10.5l7 2.5 2.5 7z"/><path d="m10 13 4.5-4.5"/>',
	gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/>',
	logout: '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5M21 12H9"/>',
	sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/>',
	moon: '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>',
	menu: '<path d="M4 6h16M4 12h16M4 18h16"/>',
	play: '<path d="m7 4 13 8-13 8z"/>',
	stop: '<rect x="5" y="5" width="14" height="14" rx="2"/>',
	refresh: '<path d="M21 12a9 9 0 1 1-2.6-6.4L21 8"/><path d="M21 3v5h-5"/>',
	check: '<path d="m5 12 5 5 9-10"/>',
	download: '<path d="M12 3v12m0 0-5-5m5 5 5-5"/><path d="M4 21h16"/>',
	upload: '<path d="M12 21V9m0 0-5 5m5-5 5 5"/><path d="M4 3h16"/>',
	trash: '<path d="M4 7h16M10 11v6M14 11v6"/><path d="M6 7l1 13h10l1-13M9 7V4h6v3"/>',
	copy: '<rect x="8" y="8" width="13" height="13" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/>',
	eye: '<path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/>'
};
var PAGES = [
	{ id: 'dashboard', title: 'Дашборд', icon: 'home' },
	{ id: 'zapret', title: 'Zapret', icon: 'bolt' },
	{ id: 'lists', title: 'Списки', icon: 'list' },
	{ id: 'dns', title: 'DNS', icon: 'globe' },
	{ id: 'telegram', title: 'Telegram', icon: 'send' },
	{ id: 'system', title: 'Система', icon: 'gear' }
];

function isNode(x) { return x != null && typeof x === 'object' && typeof x.nodeType === 'number'; }
function h(tag, attrs, kids) {
	var n = document.createElement(tag);
	if (attrs != null && (typeof attrs !== 'object' || Array.isArray(attrs) || isNode(attrs))) { kids = attrs; attrs = null; }
	if (attrs) Object.keys(attrs).forEach(function (k) {
		var v = attrs[k];
		if (v == null || v === false) return;
		if (k === 'class') n.className = v;
		else if (k === 'html') n.innerHTML = v;
		else if (k.slice(0, 2) === 'on' && typeof v === 'function') n.addEventListener(k.slice(2), v);
		else if (k === 'value') n.value = v;
		else if (k === 'checked') n.checked = !!v;
		else n.setAttribute(k, v === true ? '' : v);
	});
	add(n, kids);
	return n;
}
function add(n, kids) {
	if (kids == null) return;
	if (Array.isArray(kids)) kids.forEach(function (k) { add(n, k); });
	else if (isNode(kids)) n.appendChild(kids);
	else n.appendChild(document.createTextNode(String(kids)));
}
function clear(n) { while (n.firstChild) n.removeChild(n.firstChild); return n; }
function icon(name) {
	var s = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
	s.setAttribute('viewBox', '0 0 24 24'); s.setAttribute('fill', 'none'); s.setAttribute('stroke', 'currentColor');
	s.setAttribute('stroke-width', '2'); s.setAttribute('stroke-linecap', 'round'); s.setAttribute('stroke-linejoin', 'round');
	s.setAttribute('class', 'ico'); s.innerHTML = ICONS[name] || '';
	return s;
}
var logoN = 0;
function logo(big) {
	var id = 'zl' + (++logoN);
	return h('div', { 'class': 'logo' + (big ? ' big' : ''), html: '<svg viewBox="0 0 1250 1250" aria-hidden="true"><defs><linearGradient id="' + id + '" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#00b6ff"/><stop offset="1" stop-color="#0090ff"/></linearGradient></defs><g fill="url(#' + id + ')" stroke="#0a0a0a" stroke-width="22"><polygon points="455,170 1072,118 1215,25 688,615 25,1235 735,338 262,383"/><polygon points="1025,462 722,860 1215,800 1005,1022 315,1095"/></g></svg>' });
}
function btn(text, opts) {
	opts = opts || {};
	var b = h('button', { 'class': 'btn' + (opts.kind ? ' ' + opts.kind : '') + (opts.sm ? ' sm' : ''), type: 'button', title: opts.title, disabled: opts.disabled }, [opts.icon ? icon(opts.icon) : null, text]);
	if (opts.onclick) b.addEventListener('click', function () {
		if (b.disabled) return;
		var r = opts.onclick(b);
		if (r && typeof r.then === 'function') {
			var old = Array.prototype.slice.call(b.childNodes);
			b.disabled = true; clear(b); add(b, [h('span', { 'class': 'spin' }), text]);
			r.catch(function () {}).then(function () { b.disabled = false; clear(b); add(b, old); });
		}
	});
	return b;
}
function pill(text, kind) { return h('span', { 'class': 'pill' + (kind ? ' ' + kind : '') }, text); }
function card(title, hint, kids, cls) { return h('div', { 'class': 'card' + (cls ? ' ' + cls : '') }, [title ? h('h3', title) : null, hint ? h('p', { 'class': 'hint' }, hint) : null, kids]); }
function toggle(label, desc, checked, onchange, disabled) {
	var inp = h('input', { type: 'checkbox', checked: checked, disabled: disabled });
	if (onchange) inp.addEventListener('change', function () { onchange(inp.checked); });
	var l = h('label', { 'class': 'switch' }, [h('span', { 'class': 'lbl' }, [label, desc ? h('small', desc) : null]), h('span', { 'class': 'tgl' }, [inp, h('span')])]);
	l.input = inp;
	return l;
}
function field(label, input) { return h('div', { 'class': 'field' }, [h('label', label), input]); }
function select(options, value, onchange) {
	var s = h('select', { 'class': 'select' }, options.map(function (o) { return h('option', { value: o[0] }, o[1]); }));
	s.value = value;
	if (onchange) s.addEventListener('change', function () { onchange(s.value); });
	return s;
}
function fmtKB(kb) { kb = +kb || 0; if (kb >= 1048576) return (kb / 1048576).toFixed(1) + ' ГБ'; if (kb >= 1024) return Math.round(kb / 1024) + ' МБ'; return kb + ' КБ'; }
function fmtUp(s) { s = +s || 0; var d = Math.floor(s / 86400), hh = Math.floor(s % 86400 / 3600), m = Math.floor(s % 3600 / 60); return (d ? d + ' д ' : '') + hh + ' ч ' + m + ' мин'; }
function pct(a, b) { return b > 0 ? Math.max(0, Math.min(100, Math.round(a * 100 / b))) : 0; }
function meter(p) { return h('div', { 'class': 'meter' + (p >= 90 ? ' bad' : p >= 75 ? ' warn' : '') }, h('i', { style: 'width:' + p + '%' })); }

function toast(msg, kind) {
	var c = document.getElementById('toasts');
	if (!c) { c = h('div', { id: 'toasts' }); document.body.appendChild(c); }
	var t = h('div', { 'class': 'toast' + (kind ? ' ' + kind : '') }, msg);
	c.appendChild(t);
	setTimeout(function () { t.remove(); }, kind === 'bad' ? 7000 : 3500);
}

function api(a, data) {
	return fetch('api.cgi?a=' + encodeURIComponent(a), {
		method: 'POST', credentials: 'same-origin', cache: 'no-store',
		headers: { 'Content-Type': 'application/json', 'X-ZM': '1' },
		body: JSON.stringify(data || {})
	}).then(function (r) {
		return r.text().then(function (t) {
			var j;
			try { j = JSON.parse(t); } catch (e) { throw new Error(r.ok ? 'роутер прислал непонятный ответ' : 'ошибка ' + r.status); }
			if (r.status === 401 && a !== 'login') { showLogin(); throw new Error('нужно войти заново'); }
			if (j && j.error) throw new Error(j.error);
			return j;
		});
	});
}
function fail(e) { toast(String((e && e.message) || e), 'bad'); throw e; }

function modal(title, body, buttons, wide) {
	var ov = h('div', { 'class': 'overlay' });
	var close = function () { ov.remove(); document.removeEventListener('keydown', esc); };
	var esc = function (e) { if (e.key === 'Escape' && !ov.locked) close(); };
	var foot = h('div', { 'class': 'foot' });
	var m = h('div', { 'class': 'modal', style: wide ? 'width:min(900px,100%)' : null }, [h('h2', title), body, foot]);
	(buttons || [['Закрыть']]).forEach(function (b) {
		foot.appendChild(btn(b[0], { kind: b[2], onclick: function () { var r = b[1] ? b[1]() : null; if (r === false) return; close(); } }));
	});
	ov.appendChild(m);
	ov.addEventListener('click', function (e) { if (e.target === ov && !ov.locked) close(); });
	document.addEventListener('keydown', esc);
	document.body.appendChild(ov);
	return { close: close, overlay: ov, foot: foot, modal: m };
}
function ask(title, text, okText, danger) {
	return new Promise(function (ok) {
		modal(title, h('p', { style: 'margin:0' }, text), [['Отмена', function () { ok(false); }], [okText || 'Да', function () { ok(true); }, danger ? 'danger' : 'primary']]);
	});
}
function paintLog(pre, text) {
	clear(pre);
	String(text || '').split('\n').forEach(function (l, i, arr) {
		var cls = /^==>/.test(l) ? 'st' : /✓/.test(l) ? 'ok' : /(ОШИБКА|^\s*!|не скачал|не удалось)/i.test(l) ? 'er' : null;
		pre.appendChild(cls ? h('span', { 'class': cls }, l) : document.createTextNode(l));
		if (i < arr.length - 1) pre.appendChild(document.createTextNode('\n'));
	});
	pre.scrollTop = pre.scrollHeight;
}
function runJob(job, title, opts) {
	opts = opts || {};
	return new Promise(function (resolve) {
		var pre = h('pre', { 'class': 'console' }, 'Запускаем…');
		var stateEl = h('div', { 'class': 'row' }, [h('span', { 'class': 'spin' }), h('span', ' Выполняется — не закрывайте страницу')]);
		var m = modal(title, h('div', [stateEl, pre]), [['Скрыть']], true);
		var errs = 0, done = false;
		function tick() {
			api('job', { job: job }).then(function (r) {
				errs = 0;
				paintLog(pre, r.lines);
				if (r.done || (!r.running && r.lines)) {
					done = true;
					var okk = r.rc === '0' || (r.rc === '' && !r.running);
					clear(stateEl); add(stateEl, okk ? pill('Готово', 'ok') : pill('Ошибка', 'bad'));
					toast(okk ? title + ': готово' : title + ': ошибка', okk ? 'ok' : 'bad');
					resolve(okk);
					return;
				}
				setTimeout(tick, 1000);
			}).catch(function () {
				if (++errs > (opts.tolerate || 5)) { clear(stateEl); add(stateEl, pill(opts.lostText || 'Связь с роутером потеряна', 'warn')); resolve(!!opts.lostOk); return; }
				setTimeout(tick, 2000);
			});
		}
		setTimeout(tick, 600);
		m.onDone = function () { return done; };
	});
}
function startJob(a, data, job, title, opts) {
	return api(a, data).then(function (r) { return runJob(r.job || job, title, opts); }, fail);
}

var root = document.getElementById('app');
var cur = null, timer = null, sideEl = null, topTitle = null, viewEl = null, footEl = null;

function setTheme(t) {
	document.documentElement.setAttribute('data-theme', t);
	try { localStorage.setItem('zmk.theme', t); } catch (e) {}
}
function showLogin(msg) {
	if (timer) { clearInterval(timer); timer = null; }
	clear(root);
	var pass = h('input', { 'class': 'input', type: 'password', placeholder: 'Пароль панели', autocomplete: 'current-password' });
	var err = h('div', { 'class': 'note bad', style: msg ? null : 'display:none' }, msg || '');
	var go = function () {
		return api('login', { password: pass.value }).then(function () { start(); }, function (e) { err.style.display = ''; err.textContent = e.message; pass.select(); });
	};
	pass.addEventListener('keydown', function (e) { if (e.key === 'Enter') go(); });
	root.appendChild(h('div', { 'class': 'login' }, h('div', { 'class': 'card' }, [
		logo(true), h('h3', 'Zapret Manager'), h('div', { 'class': 'muted', style: 'margin-top:-10px' }, 'для Keenetic'),
		err, pass, btn('Войти', { kind: 'primary', onclick: go }),
		h('div', { 'class': 'muted', style: 'font-size:12px' }, 'Забыли пароль? Задайте новый командой zm passwd в SSH-консоли роутера (Entware).')
	])));
	setTimeout(function () { pass.focus(); }, 50);
}
function layout() {
	clear(root);
	var nav = h('nav', { 'class': 'nav' }, PAGES.map(function (p) {
		return h('button', { 'class': 'nav-item', 'data-id': p.id, type: 'button', onclick: function () { location.hash = p.id; sideEl.classList.remove('open'); } }, [icon(p.icon), p.title]);
	}));
	footEl = h('div', { 'class': 'side-foot' });
	sideEl = h('aside', { 'class': 'side' }, [
		h('div', { 'class': 'brand' }, [logo(), h('div', [h('div', { 'class': 'brand-name' }, 'Zapret Manager'), h('div', { 'class': 'brand-sub' }, 'для Keenetic')])]),
		nav, footEl
	]);
	topTitle = h('h1', '');
	var themeBtn = btn('', { kind: 'ghost', sm: true, icon: document.documentElement.getAttribute('data-theme') === 'dark' ? 'sun' : 'moon', title: 'Тема', onclick: function () {
		var t = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
		setTheme(t); clear(themeBtn); add(themeBtn, icon(t === 'dark' ? 'sun' : 'moon'));
	} });
	var top = h('header', { 'class': 'top' }, [
		btn('', { kind: 'ghost', sm: true, icon: 'menu', onclick: function () { sideEl.classList.toggle('open'); } }),
		topTitle, h('div', { 'class': 'sp' }), themeBtn,
		btn('Выйти', { kind: 'ghost', sm: true, icon: 'logout', onclick: function () { return api('logout').catch(function () {}).then(function () { showLogin(); }); } })
	]);
	top.firstChild.classList.add('burger');
	viewEl = h('section', { 'class': 'view' });
	root.appendChild(h('div', { 'class': 'shell' }, [sideEl, h('main', { 'class': 'main' }, [top, viewEl])]));
	window.addEventListener('scroll', function () { top.classList.toggle('scrolled', window.scrollY > 4); });
}
function sideFoot(st) {
	if (!footEl || !st) return;
	var mu = st.mem_total - st.mem_free, mp = pct(mu, st.mem_total), op = pct(st.opt_used, st.opt_total);
	clear(footEl);
	add(footEl, [
		h('div', [h('div', { 'class': 'meter-row' }, [h('span', 'Память'), h('span', fmtKB(mu) + ' / ' + fmtKB(st.mem_total))]), meter(mp)]),
		h('div', [h('div', { 'class': 'meter-row' }, [h('span', 'Entware (/opt)'), h('span', fmtKB(st.opt_used) + ' / ' + fmtKB(st.opt_total))]), meter(op)]),
		h('div', 'Версия панели ' + st.version)
	]);
}
function route() {
	var id = (location.hash || '#dashboard').slice(1);
	var p = PAGES.filter(function (x) { return x.id === id; })[0] || PAGES[0];
	cur = p.id;
	if (timer) { clearInterval(timer); timer = null; }
	Array.prototype.forEach.call(document.querySelectorAll('.nav-item'), function (n) { n.classList.toggle('active', n.getAttribute('data-id') === p.id); });
	topTitle.textContent = p.title;
	document.title = p.title + ' · Zapret Manager';
	clear(viewEl); viewEl.appendChild(h('div', { 'class': 'skeleton' }, [h('span', { 'class': 'spin' }), 'Загружаем…']));
	window.scrollTo(0, 0);
	(VIEWS[p.id] || VIEWS.dashboard)(viewEl).catch(function (e) {
		if (cur !== p.id) return;
		clear(viewEl); viewEl.appendChild(card('Не удалось загрузить страницу', null, h('div', { 'class': 'note bad' }, String(e.message || e))));
	});
}
function start() {
	layout();
	window.onhashchange = route;
	route();
	api('status').then(sideFoot).catch(function () {});
}

var VIEWS = {};

VIEWS.dashboard = function (v) {
	var sites = h('div');
	function render(st) {
		if (cur !== 'dashboard') return;
		sideFoot(st);
		clear(v);
		var stState = !st.installed ? ['warn', 'nfqws не установлен'] : st.running ? ['ok', 'Zapret работает'] : st.enabled ? ['bad', 'Zapret не запущен'] : ['', 'Zapret выключен'];
		var warns = [];
		if (st.kmods_missing) warns.push(h('div', { 'class': 'note warn' }, [h('b', 'Нет модулей ядра: ' + st.kmods_missing + '. '), 'В веб-интерфейсе роутера откройте «Общие настройки» → «Изменить набор компонентов» и поставьте «Модули ядра подсистемы Netfilter» (на старых прошивках он появляется после компонента «Протокол IPv6»). Затем перезагрузите роутер.']));
		if (!st.iptables) warns.push(h('div', { 'class': 'note bad' }, [h('b', 'Нет iptables. '), 'Выполните в SSH: opkg install iptables']));
		if (st.other_nfqws) warns.push(h('div', { 'class': 'note warn' }, [h('b', 'Работает ещё один nfqws (например, nfqws-keenetic). '), 'Два обхода одновременно мешают друг другу — остановите второй.']));
		if (st.enabled && st.installed && !st.running) warns.push(h('div', { 'class': 'note bad' }, [h('b', 'Zapret включён, но nfqws не работает. '), 'Посмотрите журнал на странице «Система» или нажмите «Перезапустить».']));
		if (!st.wan) warns.push(h('div', { 'class': 'note warn' }, [h('b', 'Не найден интерфейс провайдера. '), 'Нет маршрута по умолчанию — проверьте интернет или укажите интерфейс в Zapret → Параметры.']));
		add(v, warns);
		add(v, card(null, null, h('div', { 'class': 'hero' }, [
			h('div', { 'class': 'state' }, [h('span', { 'class': 'dot ' + stState[0] }), h('div', [h('div', { 'class': 'title' }, stState[1]), h('div', { 'class': 'sub' }, st.label)])]),
			h('div', { 'class': 'row' }, [
				st.running ? btn('Остановить', { icon: 'stop', onclick: function () { return api('zapret', { action: 'stop' }).then(render, fail); } })
					: btn('Запустить', { kind: 'primary', icon: 'play', disabled: !st.installed, onclick: function () { return api('zapret', { action: 'start' }).then(function (r) { render(r); toast('Zapret запущен', 'ok'); }, fail); } }),
				btn('Перезапустить', { icon: 'refresh', disabled: !st.installed, onclick: function () { return api('zapret', { action: 'restart' }).then(function (r) { render(r); toast('Zapret перезапущен', 'ok'); }, fail); } }),
				btn('Стратегии', { icon: 'bolt', onclick: function () { location.hash = 'zapret'; } })
			])
		])));
		var mu = st.mem_total - st.mem_free;
		add(v, h('div', { 'class': 'grid' }, [
			card('Роутер', null, h('dl', { 'class': 'kv' }, [
				h('dt', 'Модель'), h('dd', st.model ? (/keenetic/i.test(st.model) ? st.model : 'Keenetic ' + st.model) : '—'),
				h('dt', 'KeeneticOS'), h('dd', st.firmware || '—'),
				h('dt', 'Архитектура'), h('dd', st.arch || '—'),
				h('dt', 'Адрес'), h('dd', st.lan_ip)
			])),
			card('Zapret', null, h('dl', { 'class': 'kv' }, [
				h('dt', 'nfqws'), h('dd', st.nfqws || 'не установлен'),
				h('dt', 'Провайдер'), h('dd', st.wan || '—'),
				h('dt', 'Автозапуск'), h('dd', st.enabled ? 'включён' : 'выключен'),
				h('dt', 'Ядро'), h('dd', st.kernel)
			])),
			card('Нагрузка', null, [
				h('div', { 'class': 'big-num' }, st.load.split(' ')[0]),
				h('div', { 'class': 'muted', style: 'margin-bottom:12px' }, 'средняя нагрузка · работает ' + fmtUp(st.uptime)),
				h('div', { 'class': 'meter-row' }, [h('span', 'Память'), h('span', fmtKB(mu) + ' из ' + fmtKB(st.mem_total))]), meter(pct(mu, st.mem_total))
			])
		]));
		add(v, card('Доступ к сайтам', 'Роутер сам открывает сайты — так видно, работает ли обход прямо сейчас.', [
			h('div', { 'class': 'row' }, [btn('Проверить', { kind: 'primary', icon: 'check', onclick: function () {
				clear(sites); add(sites, h('div', { 'class': 'skeleton' }, [h('span', { 'class': 'spin' }), 'Проверяем 10 сайтов…']));
				return api('check_sites').then(function (r) {
					clear(sites);
					add(sites, h('div', { 'class': 'sites' }, r.items.map(function (s) {
						return h('div', { 'class': 'site' }, [h('span', { 'class': 'dot ' + (s.ok ? 'ok' : 'bad') }), h('div', [h('b', s.name), h('small', s.ok ? s.ms + ' мс · HTTP ' + s.code : 'нет ответа')])]);
					})));
				}, function (e) { clear(sites); fail(e); });
			} })]),
			sites
		]));
		if (st.job) add(v, h('div', { 'class': 'note' }, ['Сейчас выполняется задача «' + st.job + '». ', h('a', { href: '#', onclick: function (e) { e.preventDefault(); runJob(st.job, 'Задача ' + st.job); } }, 'Показать')]));
	}
	return api('status').then(function (st) {
		render(st);
		timer = setInterval(function () { if (!document.hidden && !document.querySelector('.overlay')) api('status').then(render).catch(function () {}); }, 15000);
	});
};

VIEWS.zapret = function (v) {
	return Promise.all([api('strategy_get'), api('settings_get')]).then(function (res) {
		var s = res[0], cfg = res[1];
		var draft = { main: s.main, yt: s.yt, quic: s.quic, discord: s.discord, game: s.game, xtreme: s.xtreme, lists: s.lists, doh: s.doh };
		var saved = JSON.stringify(draft);
		var dirtyLbl = h('span', { 'class': 'lbl' });
		var applyBtn;
		function dirty() {
			var d = JSON.stringify(draft) !== saved;
			dirtyLbl.textContent = d ? 'Есть изменения — нажмите «Применить»' : (s.expert ? 'Работает свой блок (экспертный режим)' : 'Применено: ' + s.label);
			applyBtn.classList.toggle('primary', d || s.expert);
			paint();
		}
		var isFs = function () { return /^fs:/.test(draft.main); };
		var mainChips = h('div', { 'class': 'chips' });
		var fsSel = h('div');
		var subCards = h('div', { 'class': 'grid two' });
		function paintMain() {
			clear(mainChips);
			['v1', 'v2', 'v3', 'v4', 'v5', 'v6', 'v7', 'v8', 'v9', 'v10'].forEach(function (id) {
				mainChips.appendChild(h('button', { type: 'button', 'class': 'chip' + (draft.main === id ? ' on' : ''), onclick: function () { draft.main = id; dirty(); } }, id));
			});
			mainChips.appendChild(h('button', { type: 'button', 'class': 'chip' + (draft.main === 'off' ? ' on' : ''), onclick: function () { draft.main = 'off'; dirty(); } }, 'Без основной'));
			clear(fsSel);
			if (s.flowseal.length) {
				var opts = [['', '— выберите стратегию Flowseal —']].concat(s.flowseal.map(function (n) { return ['fs:' + n, n]; }));
				var sel = select(opts, isFs() ? draft.main : '', function (val) { if (val) { draft.main = val; dirty(); } });
				add(fsSel, h('div', { 'class': 'row' }, [h('div', { style: 'flex:1;min-width:220px' }, sel), btn('Обновить список', { sm: true, icon: 'refresh', onclick: function () { return startJob('fs_refresh', {}, 'flowseal', 'Стратегии Flowseal').then(function () { route(); }); } })]));
			} else {
				add(fsSel, h('div', { 'class': 'row' }, [h('span', { 'class': 'muted' }, 'Стратегии Flowseal (zapret-discord-youtube) ещё не загружены.'), btn('Скачать стратегии Flowseal', { sm: true, icon: 'download', onclick: function () { return startJob('fs_refresh', {}, 'flowseal', 'Стратегии Flowseal').then(function () { route(); }); } })]));
			}
		}
		function paint() {
			paintMain();
			clear(subCards);
			var dis = isFs();
			var fsNote = dis ? h('div', { 'class': 'note', style: 'margin-bottom:10px' }, 'В стратегии Flowseal уже есть свои блоки для YouTube, Discord и игр.') : null;
			var yts = [['off', 'Выключено']].concat(s.youtube.map(function (y) { return [y, y + (y === 'Yv08' ? ' (по умолчанию)' : '')]; }));
			var ytSel = select(yts, draft.yt, function (val) { draft.yt = val; dirty(); });
			ytSel.disabled = dis;
			add(subCards, card('YouTube', 'Отдельная стратегия для доменов YouTube и Google Play (список «Google»).', [fsNote,
				h('div', { 'class': 'row' }, [h('div', { style: 'flex:1;min-width:180px' }, ytSel), btn(s.yt_loaded ? 'Обновить список' : 'Скачать все Yv', { sm: true, icon: 'refresh', onclick: function () { return startJob('yv_refresh', {}, 'youtube', 'Стратегии YouTube').then(function () { route(); }); } })]),
				toggle('QUIC для YouTube', 'Обход для UDP 443 (QUIC) на доменах YouTube.', draft.quic, function (c) { draft.quic = c; dirty(); })
			]));
			var dvs = [['off', 'Выключено']];
			for (var i = 1; i <= 17; i++) dvs.push([String(i), 'Dv' + i + (i === 1 ? ' (по умолчанию)' : '')]);
			var dvSel = select(dvs, draft.discord, function (val) { draft.discord = val; dirty(); }); dvSel.disabled = dis;
			add(subCards, card('Discord', 'Голос (UDP 19294–19344, 50000–50100) и медиасерверы discord.media.', [fsNote, dvSel]));
			var gvs = [['off', 'Выключено'], ['1', 'Gv1'], ['2', 'Gv2'], ['3', 'Gv3'], ['4', 'Gv4']];
			var gvSel = select(gvs, draft.game, function (val) { draft.game = val; if (val === 'off') draft.xtreme = false; dirty(); }); gvSel.disabled = dis;
			add(subCards, card('Игры', 'Порты игр (Steam, Riot, Battle.net, Minecraft и др.). Xtreme — почти все порты: сильнее нагружает роутер.', [fsNote, gvSel,
				toggle('Xtreme', 'TCP/UDP 80, 88, 443–65535', draft.xtreme, function (c) { draft.xtreme = c; dirty(); }, dis || draft.game === 'off')]));
			var seg = h('div', { 'class': 'seg' }, [['all', 'Все сайты'], ['user', 'Только свой список'], ['rkn', 'Свой список + РКН']].map(function (o) {
				return h('button', { type: 'button', 'class': draft.lists === o[0] ? 'on' : '', onclick: function () { draft.lists = o[0]; dirty(); } }, o[1]);
			}));
			var ldesc = { all: 'Основная стратегия работает для всех сайтов, кроме списка исключений.', user: 'Только для доменов из своего списка (' + s.user_count + ' шт.).', rkn: 'Для своего списка и списка РКН (' + s.rkn_count + ' доменов).' };
			add(subCards, card('Какие сайты обходить', isFs() ? 'Для Flowseal не действует — у него свои списки.' : ldesc[draft.lists], [seg,
				h('div', { 'class': 'row' }, [btn('Изменить списки', { sm: true, icon: 'list', onclick: function () { location.hash = 'lists'; } }), btn(s.rkn_count ? 'Обновить список РКН' : 'Скачать список РКН', { sm: true, icon: 'download', onclick: function () { return startJob('rkn_refresh', {}, 'rkn', 'Список РКН').then(function () { route(); }); } })])]));
			add(subCards, card('DoH через Zapret', 'Обход для серверов DNS-over-HTTPS, которые настроены в роутере (страница DNS).', [
				toggle('Включить блок DoH', 'Пригодится, если провайдер мешает DoH.', draft.doh, function (c) { draft.doh = c; dirty(); })]));
		}
		applyBtn = btn('Применить', { icon: 'check', onclick: function () {
			return startJob('strategy_set', draft, 'apply', 'Применяем стратегию').then(function () { route(); });
		} });
		var bar = h('div', { 'class': 'applybar' }, [dirtyLbl, h('div', { 'class': 'sp' }),
			btn('Предпросмотр', { sm: true, icon: 'eye', onclick: function () {
				return api('strategy_preview', draft).then(function (r) {
					modal('Блок стратегий (NFQWS_OPT)', h('div', [h('div', { 'class': 'muted' }, 'Профилей: ' + r.profiles + ' · TCP: ' + r.ports_tcp + (r.ports_udp ? ' · UDP: ' + r.ports_udp : '')), h('pre', { 'class': 'console' }, r.opt)]), null, true);
				}, fail);
			} }), applyBtn]);
		var ta = h('textarea', { 'class': 'textarea', spellcheck: 'false' });
		ta.value = s.opt;
		var expert = card('Экспертный режим', 'Свой блок NFQWS_OPT: одна опция на строку, профили разделяются строкой --new, комментарии — строки с #. Маркеры <HOSTLIST> и <HOSTLIST_NOAUTO> подставляют свои списки. Перед сохранением блок проверяет nfqws.', [
			s.expert ? h('div', { 'class': 'note warn', style: 'margin-bottom:12px' }, 'Сейчас работает свой блок — настройки выше не действуют, пока не вернётесь к конструктору.') : null,
			ta, h('div', { 'class': 'row', style: 'margin-top:12px' }, [
				btn('Сохранить свой блок', { icon: 'check', onclick: function () { return startJob('opt_set', { content: ta.value }, 'apply', 'Применяем свой блок').then(function () { route(); }); } }),
				s.expert ? btn('Вернуться к конструктору', { icon: 'refresh', onclick: function () { return startJob('opt_reset', {}, 'apply', 'Возвращаем конструктор').then(function () { route(); }); } }) : null,
				h('span', { 'class': 'muted wrap', style: 'font-size:12px' }, 'Порты для iptables берутся из --filter-tcp/--filter-udp. Сейчас: TCP ' + s.ports_tcp + (s.ports_udp ? ', UDP ' + s.ports_udp : ''))
			])
		]);
		var wan = h('input', { 'class': 'input', value: cfg.wan, placeholder: 'авто: ' + (cfg.wan_auto || 'не найден') });
		var pol = h('input', { 'class': 'input', value: cfg.policy, placeholder: 'например, ZAPRET' });
		var pt = h('input', { 'class': 'input', type: 'number', min: 2, max: 20, value: cfg.pkt_tcp });
		var pu = h('input', { 'class': 'input', type: 'number', min: 2, max: 20, value: cfg.pkt_udp });
		var t6 = toggle('IPv6', 'Обрабатывать и IPv6-трафик (нужен компонент «Протокол IPv6»).', cfg.ipv6);
		var tpe = toggle('Политика — исключение', 'Вкл.: обход для всех, кроме устройств из политики. Выкл.: только для устройств из политики.', cfg.policy_exclude);
		var tq = toggle('Блокировать QUIC (UDP 443)', 'Браузеры перейдут на TCP — помогает, если QUIC-обход не работает.', cfg.quic_block);
		var tl = toggle('Отладочный журнал nfqws', 'Пишет в системный журнал роутера. Включайте только на время проверки.', cfg.log);
		var settings = card('Параметры', 'Обычно менять не нужно.', [
			h('div', { 'class': 'form' }, [field('Интерфейс провайдера (WAN)', wan), field('Политика доступа Keenetic', pol), field('Пакетов TCP в nfqws', pt), field('Пакетов UDP в nfqws', pu)]),
			h('div', { 'class': 'muted', style: 'font-size:12.5px;margin:8px 0' }, cfg.policy ? (cfg.policy_found ? 'Политика «' + cfg.policy + '» найдена.' : 'Политика «' + cfg.policy + '» не найдена — обход идёт для всех устройств.') : 'Без политики обход идёт для всех устройств. Политику создают в «Приоритеты подключений» → «Политики доступа в интернет».'),
			t6, tpe, tq, tl,
			h('div', { 'class': 'row', style: 'margin-top:8px' }, [btn('Сохранить параметры', { icon: 'check', onclick: function () {
				return api('settings_set', { wan: wan.value.trim(), ipv6: t6.input.checked, policy: pol.value.trim(), policy_exclude: tpe.input.checked, quic_block: tq.input.checked, log: tl.input.checked, pkt_tcp: pt.value, pkt_udp: pu.value }).then(function () { toast('Параметры сохранены', 'ok'); }, fail);
			} })])
		]);
		clear(v);
		add(v, card('Основная стратегия', 'Стратегии v1–v10 из Zapret Manager или готовые наборы Flowseal. Если сайты не открываются — пробуйте по очереди и проверяйте на дашборде.', [mainChips, h('div', { style: 'margin-top:14px' }, fsSel)]));
		add(v, subCards);
		add(v, bar);
		add(v, expert);
		add(v, settings);
		dirty();
	});
};

var LISTS = {
	user: ['Свой список', 'Домены, которые обходить в режимах «Только свой список» и «Свой список + РКН». По одному на строку, поддомены включаются.'],
	exclude: ['Исключения', 'Эти домены никогда не трогаются. Стандартный список берётся из репозитория Zapret Manager.'],
	google: ['Google / YouTube', 'Домены для стратегий YouTube (Yv) и QUIC.'],
	rkn: ['РКН', 'Список заблокированных доменов (zapret4rocket). Обновляется кнопкой «Стандартный».'],
	auto: ['Автосписок', 'Сюда nfqws сам добавляет домены, если в своём блоке используется маркер <HOSTLIST>.'],
	ipuser: ['IP: свои', 'IP-адреса и подсети для своих правил (--ipset=).'],
	ipexclude: ['IP: исключения', 'Подсети, которые никогда не обрабатываются. По умолчанию — локальные сети.']
};
VIEWS.lists = function (v) {
	var active = VIEWS.lists.active || 'user';
	return api('lists_status').then(function (st) {
		var tabs = h('div', { 'class': 'tabs' });
		var body = h('div');
		function open(id) {
			active = VIEWS.lists.active = id;
			Array.prototype.forEach.call(tabs.children, function (t) { t.classList.toggle('on', t.getAttribute('data-id') === id); });
			clear(body); add(body, h('div', { 'class': 'skeleton' }, [h('span', { 'class': 'spin' }), 'Загружаем список…']));
			api('list_get', { id: id }).then(function (r) {
				var ta = h('textarea', { 'class': 'textarea', spellcheck: 'false', style: 'min-height:420px' });
				ta.value = r.content;
				var big = st[id] && st[id].size > 400000;
				clear(body);
				add(body, [h('p', { 'class': 'hint' }, LISTS[id][1]),
					big ? h('div', { 'class': 'note', style: 'margin-bottom:10px' }, 'Список большой — редактор может работать медленно.') : null,
					ta,
					h('div', { 'class': 'row', style: 'margin-top:12px' }, [
						btn('Сохранить', { kind: 'primary', icon: 'check', onclick: function () { return api('list_set', { id: id, content: ta.value }).then(function (x) { st[id].count = x.count; tabs.querySelector('[data-id="' + id + '"] small').textContent = x.count; toast('Сохранено: ' + x.count + ' строк', 'ok'); }, fail); } }),
						/^(exclude|google|rkn|auto|ipexclude)$/.test(id) ? btn('Стандартный', { icon: 'refresh', onclick: function () {
							return ask('Вернуть стандартный список?', 'Текущее содержимое списка «' + LISTS[id][0] + '» будет заменено.', 'Заменить', true).then(function (y) {
								if (!y) return;
								return api('list_restore', { id: id }).then(function (x) { ta.value = x.content; toast('Список заменён', 'ok'); }, fail);
							});
						} }) : null
					])]);
			}, function (e) { clear(body); add(body, h('div', { 'class': 'note bad' }, e.message)); });
		}
		Object.keys(LISTS).forEach(function (id) {
			tabs.appendChild(h('button', { type: 'button', 'class': 'tab', 'data-id': id, onclick: function () { open(id); } }, [LISTS[id][0], h('small', String((st[id] || {}).count || 0))]));
		});
		clear(v);
		add(v, card('Списки доменов и адресов', 'После сохранения nfqws перечитывает списки сам — перезапуск не нужен.', [tabs, body]));
		open(active);
	});
};

VIEWS.dns = function (v) {
	return Promise.all([api('doh_status'), api('hosts_status')]).then(function (r) {
		var d = r[0], hs = r[1];
		clear(v);
		if (!d.rci) add(v, h('div', { 'class': 'note bad' }, 'Панель не может связаться с RCI роутера (127.0.0.1:79). Управление DNS недоступно.'));
		var list = h('table', { 'class': 'table' }, [h('tr', [h('th', 'Тип'), h('th', 'Сервер'), h('th', '')])].concat(d.items.length ? d.items.map(function (it) {
			return h('tr', [h('td', it.type === 'https' ? 'DoH' : 'DoT'), h('td', [it.addr, it.type === 'tls' && it.extra ? h('div', { 'class': 'muted' }, 'SNI ' + it.extra) : null]),
				h('td', { 'class': 'act' }, it.type === 'https' ? [
					btn('Проверить', { sm: true, onclick: function () { return api('doh_probe', { url: it.addr }).then(function (x) { toast(x.ok ? it.addr + ' отвечает: ' + x.ms + ' мс' : it.addr + ' не ответил (HTTP ' + (x.code || '—') + ')', x.ok ? 'ok' : 'bad'); }, fail); } }),
					btn('', { sm: true, kind: 'ghost', icon: 'trash', title: 'Убрать', onclick: function () { return api('doh_del', { url: it.addr }).then(function () { toast('Сервер убран', 'ok'); route(); }, fail); } })
				] : h('span', { 'class': 'muted', style: 'font-size:12px' }, 'DoT — правится в веб-интерфейсе'))]);
		}) : [h('tr', h('td', { colspan: 3, 'class': 'muted' }, 'Серверы DoH/DoT не настроены — роутер ходит к DNS провайдера.'))]));
		var preset = select([['', '— готовый сервер —']].concat(d.presets.map(function (p) { return [p.url, p.name]; })), '');
		var url = h('input', { 'class': 'input', placeholder: 'https://сервер/dns-query' });
		preset.addEventListener('change', function () { if (preset.value) url.value = preset.value; });
		add(v, card('DNS-over-HTTPS', 'Шифрованный DNS средствами KeeneticOS. Нужен компонент «Прокси-сервер DNS-over-HTTPS». Чтобы роутер не брал DNS провайдера, включите «Игнорировать DNS IPv4/IPv6» в настройках подключения к интернету.', [
			list,
			h('div', { 'class': 'form', style: 'margin-top:16px' }, [field('Готовые', preset), field('Адрес DoH', url)]),
			h('div', { 'class': 'row', style: 'margin-top:12px' }, [
				btn('Проверить', { icon: 'check', onclick: function () { return api('doh_probe', { url: url.value.trim() }).then(function (x) { toast(x.ok ? 'Сервер отвечает: ' + x.ms + ' мс' : 'Сервер не ответил (HTTP ' + (x.code || '—') + ')', x.ok ? 'ok' : 'bad'); }, fail); } }),
				btn('Добавить', { kind: 'primary', icon: 'check', onclick: function () { return api('doh_add', { url: url.value.trim() }).then(function () { toast('Сервер добавлен', 'ok'); route(); }, fail); } })
			])
		]));
		var dom = h('input', { 'class': 'input', placeholder: 'example.com' });
		var ip = h('input', { 'class': 'input', placeholder: '1.2.3.4' });
		add(v, card('Статические DNS-записи (hosts)', 'Записи «ip host» в KeeneticOS — домен будет открываться по указанному IP для всех устройств. Не больше ' + hs.limit + ' записей.', [
			h('table', { 'class': 'table' }, [h('tr', [h('th', 'Домен'), h('th', 'IP'), h('th', '')])].concat(hs.items.length ? hs.items.map(function (it) {
				return h('tr', [h('td', it.domain), h('td', { 'class': 'mono' }, it.address), h('td', { 'class': 'act' }, btn('', { sm: true, kind: 'ghost', icon: 'trash', title: 'Удалить', onclick: function () { return api('hosts_del', it).then(function () { toast('Запись удалена', 'ok'); route(); }, fail); } }))]);
			}) : [h('tr', h('td', { colspan: 3, 'class': 'muted' }, 'Записей нет.'))])),
			h('div', { 'class': 'form', style: 'margin-top:16px' }, [field('Домен', dom), field('IP-адрес', ip),
				h('div', btn('Добавить запись', { kind: 'primary', icon: 'check', onclick: function () { return api('hosts_add', { domain: dom.value.trim(), address: ip.value.trim() }).then(function () { toast('Запись добавлена', 'ok'); route(); }, fail); } }))])
		]));
	});
};

VIEWS.telegram = function (v) {
	return api('tg_status').then(function (t) {
		clear(v);
		var head = h('div', { 'class': 'hero' }, [
			h('div', { 'class': 'state' }, [h('span', { 'class': 'dot ' + (t.running ? 'ok' : t.installed ? 'bad' : '') }), h('div', [
				h('div', { 'class': 'title' }, t.running ? 'TG WS Proxy работает' : t.installed ? 'TG WS Proxy остановлен' : 'TG WS Proxy не установлен'),
				h('div', { 'class': 'sub' }, t.installed ? 'Версия ' + (t.version || '—') + ' · порт ' + t.port : 'MTProto-прокси для Telegram через WebSocket. Ставится официальным установщиком valnesfjord/tg-ws-proxy-rs.')
			])]),
			h('div', { 'class': 'row' }, t.installed ? [
				t.running ? btn('Остановить', { icon: 'stop', onclick: function () { return api('tg', { action: 'stop' }).then(function () { route(); }, fail); } }) : btn('Запустить', { kind: 'primary', icon: 'play', onclick: function () { return api('tg', { action: 'start' }).then(function () { route(); }, fail); } }),
				btn('Обновить', { icon: 'refresh', onclick: function () { return startJob('tg', { action: 'update' }, 'tg', 'TG WS Proxy').then(function () { route(); }); } }),
				btn('Удалить', { kind: 'danger', icon: 'trash', onclick: function () { return ask('Удалить TG WS Proxy?', 'Программа, служба и секрет будут удалены. Устройства придётся настроить заново.', 'Удалить', true).then(function (y) { if (y) return startJob('tg', { action: 'remove' }, 'tg', 'Удаляем TG WS Proxy').then(function () { route(); }); }); } })
			] : [btn('Установить', { kind: 'primary', icon: 'download', disabled: !t.arch_ok, onclick: function () { return startJob('tg', { action: 'install' }, 'tg', 'Ставим TG WS Proxy').then(function () { route(); }); } })])
		]);
		add(v, card(null, null, head));
		if (t.link) {
			var inp = h('input', { 'class': 'input mono', value: t.link, readonly: true });
			add(v, card('Подключение', 'Откройте ссылку на устройстве с Telegram или добавьте прокси вручную: тип MTProto, сервер — адрес роутера, порт ' + t.port + '.', [
				h('div', { 'class': 'row' }, [h('div', { style: 'flex:1;min-width:240px' }, inp), btn('Копировать', { icon: 'copy', onclick: function () { inp.select(); try { navigator.clipboard.writeText(t.link); } catch (e) { document.execCommand('copy'); } toast('Ссылка скопирована', 'ok'); } }), h('a', { 'class': 'btn', href: t.link }, 'Открыть в Telegram')])
			]));
		} else if (t.installed) {
			add(v, h('div', { 'class': 'note' }, 'Ссылка tg:// появится, когда прокси запустится.'));
		}
	});
};

VIEWS.system = function (v) {
	return Promise.all([api('status'), api('svc_log')]).then(function (r) {
		var st = r[0], lg = r[1];
		clear(v);
		var logPre = h('pre', { 'class': 'console' });
		paintLog(logPre, lg.lines || 'Журнал пуст.');
		var file = h('input', { type: 'file', accept: '.gz,.tgz,application/gzip', style: 'display:none' });
		file.addEventListener('change', function () {
			var f = file.files[0]; if (!f) return;
			fetch('api.cgi?a=restore', { method: 'POST', credentials: 'same-origin', headers: { 'X-ZM': '1', 'Content-Type': 'application/octet-stream' }, body: f })
				.then(function (x) { return x.json(); }).then(function (j) { if (j.error) throw new Error(j.error); return runJob(j.job || 'apply', 'Восстанавливаем настройки'); }).then(function () { route(); }, fail);
			file.value = '';
		});
		var op = h('input', { 'class': 'input', type: 'password', autocomplete: 'current-password' });
		var np = h('input', { 'class': 'input', type: 'password', autocomplete: 'new-password' });
		add(v, h('div', { 'class': 'grid two' }, [
			card('Панель', null, [
				h('dl', { 'class': 'kv' }, [h('dt', 'Версия'), h('dd', st.version), h('dt', 'nfqws'), h('dd', st.nfqws || '—'), h('dt', 'Адрес'), h('dd', location.host)]),
				h('div', { 'class': 'row', style: 'margin-top:14px' }, [
					btn('Обновить панель', { icon: 'download', onclick: function () { return ask('Обновить панель?', 'Скачаем свежий установщик Zapret Manager для Keenetic и поставим его поверх. Настройки сохранятся.', 'Обновить').then(function (y) { if (y) return startJob('panel_update', {}, 'panel', 'Обновляем панель', { tolerate: 20, lostOk: true }).then(function () { setTimeout(function () { location.reload(); }, 1500); }); }); } }),
					btn('Обновить nfqws', { icon: 'refresh', onclick: function () { return startJob('zapret', { action: 'update' }, 'engine', 'Обновляем zapret (nfqws)').then(function () { route(); }); } })
				])
			]),
			card('Пароль панели', 'Не короче 6 символов. Остальные сессии будут закрыты.', [
				h('div', { 'class': 'form' }, [field('Текущий пароль', op), field('Новый пароль', np)]),
				h('div', { 'class': 'row', style: 'margin-top:12px' }, btn('Сменить пароль', { icon: 'check', onclick: function () { return api('passwd', { old: op.value, new: np.value }).then(function () { op.value = np.value = ''; toast('Пароль изменён', 'ok'); }, fail); } }))
			]),
			card('Резервная копия', 'Настройки, стратегии и списки в одном архиве.', h('div', { 'class': 'row' }, [
				h('a', { 'class': 'btn', href: 'api.cgi?a=backup', download: '' }, [icon('download'), 'Скачать']),
				btn('Восстановить из файла', { icon: 'upload', onclick: function () { file.click(); } }), file
			])),
			card('Удаление', 'Снимает правила, останавливает Zapret и удаляет панель.', h('div', { 'class': 'row' }, [
				btn('Удалить, настройки оставить', { onclick: function () { return ask('Удалить панель?', 'Zapret остановится, панель удалится. Настройки и списки останутся в /opt/etc/zapret-manager и /opt/zapret.', 'Удалить', true).then(function (y) { if (y) return startJob('uninstall', { keep: true }, 'uninstall', 'Удаляем панель', { tolerate: 2, lostOk: true, lostText: 'Панель удалена' }); }); } }),
				btn('Удалить всё', { kind: 'danger', icon: 'trash', onclick: function () { return ask('Удалить всё?', 'Будут удалены панель, Zapret, стратегии и все списки.', 'Удалить всё', true).then(function (y) { if (y) return startJob('uninstall', { keep: false }, 'uninstall', 'Удаляем всё', { tolerate: 2, lostOk: true, lostText: 'Панель удалена' }); }); } })
			]))
		]));
		add(v, card('Журнал панели', 'Запуски, остановки, ошибки и входы.', [logPre, h('div', { 'class': 'row', style: 'margin-top:12px' }, btn('Обновить', { sm: true, icon: 'refresh', onclick: function () { return api('svc_log').then(function (x) { paintLog(logPre, x.lines || 'Журнал пуст.'); }, fail); } }))]));
		add(v, card('Что нужно в KeeneticOS', null, h('div', { 'class': 'note' }, h('ol', [
			h('li', 'Компоненты: «Поддержка открытых пакетов» (OPKG), «Модули ядра подсистемы Netfilter», «Протокол IPv6» (для IPv6), «Прокси-сервер DNS-over-HTTPS» (для страницы DNS).'),
			h('li', 'Сетевой ускоритель (аппаратный NAT) иногда пропускает пакеты мимо Zapret. Если обход не работает — попробуйте его выключить.'),
			h('li', 'Не используйте одновременно другой обход (nfqws-keenetic, zapret из install_easy).')
		]))));
	});
};

api('session').then(function (r) { if (r.auth) start(); else showLogin(); }, function () { showLogin('Роутер не отвечает. Обновите страницу.'); });
})();
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/www/app.js.zm-new' '/opt/zapret-manager/www/app.js'
cat > '/opt/zapret-manager/defaults/zapret-hosts-google.txt.zm-new' << 'ZM_INSTALLER_EOF'
cdn.youtube.com
fonts.googleapis.com
fonts.gstatic.com
ggpht.com
googleapis.com
googleusercontent.com
googlevideo.com
i.ytimg.com
i9.ytimg.com
jnn-pa.googleapis.com
kids.youtube.com
m.youtube.com
manifest.googlevideo.com
music.youtube.com
nhacmp3youtube.com
returnyoutubedislikeapi.com
s.ytimg.com
signaler-pa.youtube.com
studio.youtube.com
tv.youtube.com
wide-youtube.l.google.com
withyoutube.com
youtu.be
youtube.com
youtube.googleapis.com
youtubeeducation.com
youtubeembeddedplayer.googleapis.com
youtubefanfest.com
youtubegaming.com
youtubei.googleapis.com
youtubekids.com
youtubemobilesupport.com
youtube-nocookie.com
youtube-ui.l.google.com
yt.be
yt3.ggpht.com
yt3.googleusercontent.com
yt4.ggpht.com
ytimg.com
ytimg.l.google.com
yting.com
yt-video-upload.l.google.com
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
youtubego.co.id
youtubego.co.in
youtubego.com
youtubego.com.br
youtubego.id
youtubego.in
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/defaults/zapret-hosts-google.txt.zm-new' '/opt/zapret-manager/defaults/zapret-hosts-google.txt'
cat > '/opt/zapret-manager/defaults/zapret-ip-exclude.txt.zm-new' << 'ZM_INSTALLER_EOF'
127.0.0.0/8
10.0.0.0/8
172.16.0.0/12
192.168.0.0/16
169.254.0.0/16
100.64.0.0/10
::1
fc00::/7
fe80::/10
ZM_INSTALLER_EOF
mv -f '/opt/zapret-manager/defaults/zapret-ip-exclude.txt.zm-new' '/opt/zapret-manager/defaults/zapret-ip-exclude.txt'
cat > '/opt/etc/init.d/S51zapret-manager.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
. /opt/zapret-manager/lib.sh
case "$1" in
	start)
		conf_defaults
		fw_table iptables filter
		fw_table ip6tables filter
		[ "$(c ENABLED 1)" = 1 ] || exit 0
		zapret_start
		;;
	stop) zapret_stop ;;
	restart) zapret_restart ;;
	status)
		if nfqws_running; then echo "Zapret работает (pid $(nfqws_pid)), WAN: $(wan_ifaces)"; else echo "Zapret остановлен"; exit 1; fi
		;;
	firewall) fw_hook "$2" "$3" ;;
	*) echo "Использование: $0 {start|stop|restart|status}" ;;
esac
ZM_INSTALLER_EOF
mv -f '/opt/etc/init.d/S51zapret-manager.zm-new' '/opt/etc/init.d/S51zapret-manager'
cat > '/opt/etc/ndm/netfilter.d/100-zapret-manager.sh.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
[ -x /opt/etc/init.d/S51zapret-manager ] || exit 0
case "$table" in mangle|nat|filter) ;; *) exit 0 ;; esac
/opt/etc/init.d/S51zapret-manager firewall "$type" "$table" >/dev/null 2>&1
exit 0
ZM_INSTALLER_EOF
mv -f '/opt/etc/ndm/netfilter.d/100-zapret-manager.sh.zm-new' '/opt/etc/ndm/netfilter.d/100-zapret-manager.sh'
cat > '/opt/bin/zm.zm-new' << 'ZM_INSTALLER_EOF'
#!/bin/sh
. /opt/zapret-manager/lib.sh
G="\033[1;32m"; C="\033[1;36m"; Y="\033[1;33m"; R="\033[1;31m"; N="\033[0m"
port() { sed -n 's/.*"socket"[^:]*:\([0-9]*\)".*/\1/p' /opt/etc/lighttpd/conf.d/80-zapret-manager.conf 2>/dev/null | head -n 1; }
case "$1" in
	''|status)
		conf_defaults
		echo -e "${C}Zapret Manager для Keenetic $ZM_VERSION${N}"
		if nfqws_running; then echo -e "Zapret:    ${G}работает${N} (nfqws $(nfqws_ver), WAN: $(wan_ifaces))"; else echo -e "Zapret:    ${Y}остановлен${N}"; fi
		echo "Стратегия: $(strategy_label)"
		echo "Панель:    http://$(lan_ip):$(port)"
		[ -n "$(kmods_missing)" ] && echo -e "${R}Нет модулей ядра: $(kmods_missing) — поставьте компонент «Модули ядра подсистемы Netfilter»${N}"
		echo
		echo "Команды: zm start | stop | restart | apply | strategy | sites | passwd | log | update | uninstall"
		;;
	start|stop|restart) zapret_action "$1" | jq -r 'if .error then "Ошибка: " + .error elif .running then "Zapret работает" else "Zapret остановлен" end' ;;
	apply) conf_defaults; do_apply ;;
	strategy) conf_defaults; echo "$(strategy_label)"; echo; cat "$OPT" ;;
	sites) check_sites | jq -r '.items[] | (if .ok then "  ✓ " else "  ✗ " end) + .name + (if .ok then "  (" + (.ms | tostring) + " мс)" else "" end)' ;;
	passwd)
		printf 'Новый пароль панели (не короче 6 символов): '
		stty -echo 2>/dev/null; read -r p; stty echo 2>/dev/null; echo
		if auth_set "$p"; then rm -rf "${ZM_TMP:?}/sess"; echo -e "${G}Пароль изменён${N}"; else echo -e "${R}Слишком короткий пароль${N}"; exit 1; fi
		;;
	log) tail -n "${2:-50}" "$ZM_LOG" 2>/dev/null ;;
	update) do_panel_update ;;
	uninstall)
		printf 'Удалить панель и Zapret? Настройки и списки оставить? [Y — оставить / n — удалить всё / q — отмена]: '
		read -r a
		case "$a" in q|Q) exit 0 ;; n|N) zm_uninstall 0 ;; *) zm_uninstall 1 ;; esac
		;;
	*) echo "Использование: zm [status|start|stop|restart|apply|strategy|sites|passwd|log|update|uninstall]" ;;
esac
ZM_INSTALLER_EOF
mv -f '/opt/bin/zm.zm-new' '/opt/bin/zm'
chmod 0755 /opt/zapret-manager/lib.sh /opt/zapret-manager/www/api.cgi /opt/etc/init.d/S51zapret-manager /opt/etc/ndm/netfilter.d/100-zapret-manager.sh /opt/bin/zm
chmod 0644 /opt/zapret-manager/www/index.html /opt/zapret-manager/www/app.js /opt/zapret-manager/www/app.css
ZMW_BUILD="$(date +%s)"
sed -i "s/__ZMW_BUILD__/$ZMW_BUILD/g" /opt/zapret-manager/www/index.html /opt/zapret-manager/www/app.js
_zmi_ok "Файлы записаны"

. /opt/zapret-manager/lib.sh
conf_defaults
[ -f "$L_IPEXCL" ] || cp -f /opt/zapret-manager/defaults/zapret-ip-exclude.txt "$L_IPEXCL"
google_list_ensure

_zmi_say "Ставим zapret (nfqws)"
if [ -x "$NFQWS" ] && [ -n "$(nfqws_ver)" ] && [ -z "$ZM_ENGINE_UPDATE" ]; then
	_zmi_ok "nfqws $(nfqws_ver) уже стоит — обновить можно в панели: Система → «Обновить nfqws»"
else
	cfg_set "$CONF" ENABLED 0
	if do_engine_update > /opt/tmp/zm-engine.log 2>&1; then sed 's/^/   /' /opt/tmp/zm-engine.log; rm -f /opt/tmp/zm-engine.log
	else sed 's/^/   /' /opt/tmp/zm-engine.log; rm -f /opt/tmp/zm-engine.log; _zmi_die "не удалось поставить nfqws — проверьте доступ к github.com"; fi
	cfg_set "$CONF" ENABLED 1
fi

_zmi_say "Проверяем модули ядра"
kmods
_zm_km="$(kmods_missing)"
if [ -n "$_zm_km" ]; then
	_zmi_warn "Нет модулей: $_zm_km"
	_zmi_warn "В веб-интерфейсе роутера: «Общие настройки» → «Изменить набор компонентов» → «Модули ядра подсистемы Netfilter», затем перезагрузка"
else
	_zmi_ok "NFQUEUE, connbytes и multiport на месте"
fi
if pgrep -f /opt/usr/bin/nfqws >/dev/null 2>&1 || [ -x /opt/etc/init.d/S51nfqws ]; then
	_zmi_warn "Найден nfqws-keenetic — два обхода мешают друг другу. Остановите его: /opt/etc/init.d/S51nfqws stop и chmod -x /opt/etc/init.d/S51nfqws"
fi

_zmi_say "Применяем стратегию"
if [ "$_zm_had_lib" = 1 ] && [ -s "$OPT" ]; then
	if zapret_restart >/dev/null; then _zmi_ok "Zapret перезапущен со старыми настройками: $(strategy_label)"; else _zmi_warn "Zapret не запустился — смотрите журнал в панели"; fi
else
	do_apply | sed 's/^/   /'
fi

_zmi_say "Включаем веб-панель"
ZMW_PORT=7788
cat > /opt/etc/lighttpd/conf.d/80-zapret-manager.conf << EOF
\$SERVER["socket"] == ":$ZMW_PORT" {
    server.document-root = "/opt/zapret-manager/www"
    index-file.names = ( "index.html" )
    cgi.assign = ( ".cgi" => "/bin/sh" )
    static-file.exclude-extensions = ( ".cgi", ".sh" )
}
EOF
grep -rqs 'mod_cgi' /opt/etc/lighttpd/conf.d/ /opt/etc/lighttpd/lighttpd.conf || sed -i '1i server.modules += ( "mod_cgi" )' /opt/etc/lighttpd/conf.d/80-zapret-manager.conf
if ! grep -rqsE '^[[:space:]]*server\.port' /opt/etc/lighttpd/lighttpd.conf /opt/etc/lighttpd/conf.d/; then
	echo 'server.port := 8088' > /opt/etc/lighttpd/conf.d/00-zm-port.conf
	_zmi_ok "Основной порт lighttpd: 8088 (порт 80 занят веб-интерфейсом Keenetic)"
fi
[ -f /opt/etc/init.d/S80lighttpd ] && sed -i -E 's#^PROCS=lighttpd$#PROCS=/opt/sbin/lighttpd#' /opt/etc/init.d/S80lighttpd
if lighttpd -tt -f /opt/etc/lighttpd/lighttpd.conf >/dev/null 2>&1; then
	/opt/etc/init.d/S80lighttpd restart >/dev/null 2>&1
	sleep 1
	if pgrep -f /opt/sbin/lighttpd >/dev/null 2>&1 || pidof lighttpd >/dev/null 2>&1; then _zmi_ok "Веб-сервер запущен"; else _zmi_warn "lighttpd не запустился — проверьте /opt/var/log/lighttpd/error.log"; fi
else
	_zmi_warn "lighttpd не принял настройки: $(lighttpd -tt -f /opt/etc/lighttpd/lighttpd.conf 2>&1 | tail -n 1)"
fi

ZM_PASS_SHOW=""
if [ ! -s "$ZM_ETC/auth" ]; then
	_zmi_say "Пароль для входа в панель"
	if [ -z "$ZM_UNATTENDED" ] && [ -t 0 ]; then
		printf '   Придумайте пароль (не короче 6 символов, Enter — сгенерировать): '
		stty -echo 2>/dev/null; read -r _zm_p; stty echo 2>/dev/null; echo
	fi
	if [ "${#_zm_p}" -lt 6 ]; then _zm_p="$(rnd_hex 5)"; ZM_PASS_SHOW="$_zm_p"; fi
	auth_set "$_zm_p" && _zmi_ok "Пароль сохранён" || _zmi_warn "Пароль не сохранился — задайте его командой zm passwd"
fi

ZMW_IP="$(lan_ip)"
echo -e "\n${GREEN}Готово: Zapret Manager для Keenetic $ZM_NEW_VER установлен${NC}\n"
echo -e "${CYAN}Панель:  ${NC}http://$ZMW_IP:$ZMW_PORT"
[ -n "$ZM_PASS_SHOW" ] && echo -e "${CYAN}Пароль:  ${NC}$ZM_PASS_SHOW   (сменить: zm passwd или в панели → Система)"
echo -e "${CYAN}Консоль: ${NC}zm — состояние, zm restart, zm sites, zm passwd"
if nfqws_running; then echo -e "${CYAN}Zapret:  ${NC}работает · $(strategy_label)"; else echo -e "${YELLOW}Zapret:  не запущен — откройте панель${NC}"; fi
echo
