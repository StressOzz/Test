#!/bin/sh
# ==========================================================================
#  FakeDPI для OpenWrt — FakeSIP (UDP) + FakeHTTP (TCP) «из коробки»
#  Version: 1.00
#
#  Использование:
#    sh fakedpi.sh            — установить / переустановить и запустить
#    fakedpi status           — состояние, очереди, счётчики пакетов
#    fakedpi restart|stop|start
#    fakedpi update           — скачать свежие бинарники и перезапустить
#    fakedpi remove           — полностью удалить
#
#  Настройки: /etc/config/fakedpi  (после правки: fakedpi restart)
#  Проекты:   github.com/MikeWang000000/FakeSIP
#             github.com/MikeWang000000/FakeHTTP
# ==========================================================================

VERSION="1.00"
BIN_DIR="/usr/bin"
INIT="/etc/init.d/fakedpi"
CFG="/etc/config/fakedpi"
SELF="/usr/bin/fakedpi"
GH="https://github.com/MikeWang000000"

if [ -t 1 ]; then
	G='\033[1;32m'; R='\033[1;31m'; Y='\033[1;33m'; B='\033[1;36m'; N='\033[0m'
else
	G=''; R=''; Y=''; B=''; N=''
fi
ok()   { printf "${G}[✓]${N} %s\n" "$*"; }
info() { printf "${B}[•]${N} %s\n" "$*"; }
warn() { printf "${Y}[!]${N} %s\n" "$*"; }
die()  { printf "${R}[✗]${N} %s\n" "$*"; exit 1; }

[ "$(id -u)" = "0" ] || die "Запустите от root"
[ -f /etc/openwrt_release ] || die "Это не OpenWrt"

# ---------- архитектура -> имя сборки ----------
detect_arch() {
	. /etc/openwrt_release
	a="$DISTRIB_ARCH"
	[ -n "$a" ] || a="$(uname -m)"
	case "$a" in
		aarch64*|arm64*)            echo arm64 ;;
		x86_64*)                    echo x86_64 ;;
		i386_pentium4*|i686*)       echo i686 ;;
		i386*|i486*|i586*)          echo i586 ;;
		arm_cortex-a*vfp*|arm_cortex-a*neon*) echo arm32v7hf ;;
		arm_cortex-a*|armv7*)       echo arm32v7 ;;
		arm_*vfp*)                  echo arm32hf ;;
		arm*)                       echo arm32 ;;
		mipsel_*|mipsel*)           echo mips32elsf ;;
		mips64el*)                  echo mips64el ;;
		mips64*)                    echo mips64 ;;
		mips_*|mips*)               echo mips32sf ;;
		riscv64*)                   echo riscv64 ;;
		powerpc64*)                 echo powerpc64 ;;
		powerpc*)                   echo powerpc ;;
		loongarch64*)               echo loong64 ;;
		*)                          echo "" ;;
	esac
}

fetch() { # url file
	rm -f "$2"
	if command -v wget >/dev/null 2>&1; then
		wget -q -T 30 -O "$2" "$1" 2>/dev/null
	else
		curl -fsSL --max-time 60 -o "$2" "$1" 2>/dev/null
	fi
	[ -s "$2" ]
}

# ---------- зависимости ----------
install_deps() {
	if [ -e /sys/module/nft_queue ] || modprobe nft_queue 2>/dev/null; then
		ok "Модуль ядра nft_queue уже есть"
		return 0
	fi
	info "Устанавливаю kmod-nft-queue..."
	if command -v apk >/dev/null 2>&1; then
		apk update >/dev/null 2>&1
		apk add kmod-nft-queue >/dev/null 2>&1
	else
		opkg update >/dev/null 2>&1
		opkg install kmod-nft-queue >/dev/null 2>&1
	fi
	modprobe nft_queue 2>/dev/null
	[ -e /sys/module/nft_queue ] || die "Не удалось установить kmod-nft-queue"
	ok "kmod-nft-queue установлен"
}

# ---------- бинарники ----------
install_bin() { # name(fakesip|fakehttp) repo(FakeSIP|FakeHTTP) arch
	name="$1"; repo="$2"; arch="$3"
	tgz="/tmp/$name-linux-$arch.tar.gz"
	d="/tmp/fakedpi_$name.$$"
	if [ -s "$tgz" ]; then
		info "$name: беру локальный архив $tgz"
	else
		info "$name: скачиваю сборку $arch с GitHub..."
		fetch "$GH/$repo/releases/latest/download/$name-linux-$arch.tar.gz" "$tgz" \
			|| die "$name: не удалось скачать. Положите $name-linux-$arch.tar.gz в /tmp и запустите снова"
	fi
	rm -rf "$d"; mkdir -p "$d"
	tar -xzf "$tgz" -C "$d" 2>/dev/null || { rm -rf "$d" "$tgz"; die "$name: архив повреждён"; }
	f="$(find "$d" -type f -name "$name" | head -n1)"
	[ -n "$f" ] || { rm -rf "$d"; die "$name: бинарник не найден в архиве"; }
	"$f" 2>&1 | grep -q "Usage" || { rm -rf "$d"; die "$name: бинарник не запускается на этой архитектуре ($arch)"; }
	cp -f "$f" "$BIN_DIR/$name" && chmod 755 "$BIN_DIR/$name"
	rm -rf "$d" "$tgz"
	ok "$name установлен в $BIN_DIR/$name"
}

# ---------- конфиг ----------
write_config() {
	if [ -f "$CFG" ]; then
		ok "Конфиг $CFG уже есть — сохраняю ваши настройки"
		return
	fi
	cat > "$CFG" <<'EOF'
config main 'main'
	# 1 — включено, 0 — выключено
	option fakesip '1'
	option fakehttp '1'
	# WAN-интерфейс(ы) через пробел; пусто = определить автоматически
	option iface ''
	# TTL фейка в % от числа хопов до цели (0 = фиксированный TTL 3)
	option ttl_pct '50'
	# сколько раз повторять фейковый пакет
	option repeat '2'
	# домены, под которые FakeHTTP маскирует TCP (HTTP / HTTPS)
	option http_host 'ya.ru'
	option https_host 'ya.ru'
	# порты, которые не трогать (через пробел, можно диапазоны 50000-50100)
	option exclude_udp '53 67 68 123 5353'
	option exclude_tcp '22 53'
	# 1 — не трогать порты, которые уже обрабатывает zapret/zapret2
	option zapret_compat '1'
	option ipv6 '1'
	# 1 — писать подробный лог в logread (много строк!)
	option log '0'
EOF
	ok "Создан конфиг $CFG"
}

# ---------- init-скрипт (procd) ----------
write_init() {
	cat > "$INIT" <<'EOF'
#!/bin/sh /etc/rc.common
# FakeDPI: FakeSIP + FakeHTTP
START=99
STOP=10
USE_PROCD=1

TABLE="fakedpi"
STATE="/var/run/fakedpi.state"
NFT="/var/run/fakedpi.nft"

wan_devs() {
	local devs="" n d
	for n in wan wan6 wwan; do
		d="$(ifstatus "$n" 2>/dev/null | jsonfilter -q -e '@.l3_device')"
		[ -n "$d" ] && case " $devs " in *" $d "*) ;; *) devs="$devs $d" ;; esac
	done
	if [ -z "$devs" ]; then
		devs="$(ip route show default 2>/dev/null | awk '{for(i=1;i<NF;i++) if($i=="dev"){print $(i+1); exit}}')"
	fi
	echo $devs
}

# занятые номера NFQUEUE (одиночные и диапазоны a-b)
queue_used() { # q
	local q="$1" e a b
	for e in $(nft -n list ruleset 2>/dev/null | grep -w queue | grep -oE '(to|num) [0-9]+(-[0-9]+)?' | awk '{print $2}'); do
		a="${e%-*}"; b="${e#*-}"
		[ "$q" -ge "$a" ] && [ "$q" -le "$b" ] && return 0
	done
	return 1
}
free_queue() {
	local q="$1"
	while queue_used "$q"; do q=$((q + 1)); done
	echo "$q"
}

# порты, которые zapret отправляет в свою очередь
zapret_ports() { # tcp|udp
	local t
	for t in zapret zapret2; do
		nft list table inet "$t" 2>/dev/null | grep -w queue | grep -E "(l4proto $1|$1 dport)" \
			| grep -oE "(th|$1) dport (\{[^}]*\}|[0-9]+(-[0-9]+)?)" \
			| sed -E 's/^(th|tcp|udp) dport //; s/[{}]//g; s/,/ /g'
	done
}

# "53 67 50000-50100" -> "53, 67, 50000-50100" (только валидные, без повторов)
port_list() {
	echo $* | tr ' ' '\n' | grep -E '^[0-9]+(-[0-9]+)?$' | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g'
}

build_nft() {
	local wanset="" d
	local ew="" eu="" et=""
	for d in $WAN; do wanset="$wanset${wanset:+, }\"$d\""; done
	[ -n "$wanset" ] && ew="elements = { $wanset };"
	[ -n "$EXU" ] && eu="elements = { $EXU };"
	[ -n "$EXT" ] && et="elements = { $EXT };"
	{
	echo "table inet $TABLE {"
	echo "  set wanif { type ifname; $ew }"
	echo "  set local4 { type ipv4_addr; flags interval; elements = { 0.0.0.0/8, 10.0.0.0/8, 100.64.0.0/10, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/3 }; }"
	echo "  set local6 { type ipv6_addr; flags interval; elements = { ::/127, ::ffff:0:0/96, 64:ff9b::/96, 64:ff9b:1::/48, 2002::/16, fc00::/7, fe80::/10 }; }"
	echo "  set ex_udp { type inet_service; flags interval; auto-merge; $eu }"
	echo "  set ex_tcp { type inet_service; flags interval; auto-merge; $et }"
	if [ "$SIP" = 1 ]; then
	cat <<NFT
  chain sip_pre {
    type filter hook prerouting priority mangle - 5; policy accept;
    iifname != @wanif return
    icmp type time-exceeded counter drop
    icmpv6 type time-exceeded counter drop
    ip saddr @local4 return
    ip6 saddr != 2000::/3 return
    jump sip_rules
  }
  chain sip_post {
    type filter hook postrouting priority mangle - 5; policy accept;
    oifname != @wanif return
    ip daddr @local4 return
    ip6 daddr != 2000::/3 return
    jump sip_rules
  }
  chain sip_rules {
    meta mark and $MSIP == $MSIP return
    meta l4proto != udp return
    $NO6
    udp dport @ex_udp return
    udp sport @ex_udp return
    ct packets 1-5 counter queue num $QSIP bypass
  }
NFT
	fi
	if [ "$HTTP" = 1 ]; then
	cat <<NFT
  chain http_pre {
    type filter hook prerouting priority mangle - 5; policy accept;
    iifname != @wanif return
    ip saddr @local4 return
    ip6 saddr @local6 return
    jump http_rules
  }
  chain http_post {
    type filter hook postrouting priority srcnat + 5; policy accept;
    oifname != @wanif return
    ip daddr @local4 return
    ip6 daddr @local6 return
    jump http_rules
  }
  chain http_rules {
    meta mark and $MHTTP == $MHTTP return
    meta l4proto != tcp return
    $NO6
    tcp dport @ex_tcp return
    tcp sport @ex_tcp return
    tcp flags & (syn | fin | rst) == syn counter queue num $QHTTP bypass
    tcp flags & (syn | ack | fin | rst) == ack ct packets 2-4 counter queue num $QHTTP bypass
  }
NFT
	fi
	echo "}"
	} > "$NFT"
}

start_service() {
	config_load fakedpi
	config_get_bool SIP main fakesip 1
	config_get_bool HTTP main fakehttp 1
	config_get WAN main iface ''
	config_get PCT main ttl_pct 50
	config_get REP main repeat 2
	config_get HHOST main http_host 'ya.ru'
	config_get SHOST main https_host 'ya.ru'
	config_get EXU main exclude_udp '53 67 68 123 5353'
	config_get EXT main exclude_tcp '22 53'
	config_get_bool ZC main zapret_compat 1
	config_get_bool V6 main ipv6 1
	config_get_bool LOG main log 0
	MSIP=0x10000
	MHTTP=0x8000

	[ "$SIP" = 1 ] || [ "$HTTP" = 1 ] || { logger -t fakedpi "всё выключено в /etc/config/fakedpi"; return 0; }
	[ -x /usr/bin/fakesip ] || SIP=0
	[ -x /usr/bin/fakehttp ] || HTTP=0

	modprobe nft_queue 2>/dev/null
	sysctl -q -w net.netfilter.nf_conntrack_acct=1 2>/dev/null

	nft delete table inet "$TABLE" 2>/dev/null
	[ -n "$WAN" ] || WAN="$(wan_devs)"
	[ -n "$WAN" ] || logger -t fakedpi "WAN не найден — правила применятся, когда WAN поднимется"

	ZU=""; ZT=""
	if [ "$ZC" = 1 ] && { [ -x /etc/init.d/zapret ] || [ -x /etc/init.d/zapret2 ]; }; then
		ZU="443 $(zapret_ports udp)"
		ZT="80 443 $(zapret_ports tcp)"
	fi
	EXU="$(port_list $EXU $ZU)"
	EXT="$(port_list $EXT $ZT)"

	QSIP="$(free_queue 513)"
	QHTTP="$(free_queue 512)"
	[ "$QHTTP" = "$QSIP" ] && QHTTP="$(free_queue $((QSIP + 1)))"

	NO6=""; F6=""
	[ "$V6" = 1 ] || { NO6="meta nfproto ipv6 return"; F6="-4"; }

	build_nft
	if ! nft -f "$NFT"; then
		logger -t fakedpi "ошибка загрузки правил nftables ($NFT)"
		return 1
	fi

	local common="-a -f $F6 -r $REP"
	[ "$PCT" -gt 0 ] 2>/dev/null && common="$common -y $PCT"
	[ "$LOG" = 1 ] || common="$common -s"

	if [ "$SIP" = 1 ]; then
		procd_open_instance fakesip
		procd_set_param command /usr/bin/fakesip $common -n "$QSIP" -m "$MSIP"
		procd_set_param respawn 3600 5 0
		[ "$LOG" = 1 ] && procd_set_param stderr 1
		procd_close_instance
	fi
	if [ "$HTTP" = 1 ]; then
		procd_open_instance fakehttp
		procd_set_param command /usr/bin/fakehttp $common -n "$QHTTP" -m "$MHTTP" -h "$HHOST" -e "$SHOST"
		procd_set_param respawn 3600 5 0
		[ "$LOG" = 1 ] && procd_set_param stderr 1
		procd_close_instance
	fi

	cat > "$STATE" <<ST
WAN="$WAN"
SIP="$SIP"
HTTP="$HTTP"
QSIP="$QSIP"
QHTTP="$QHTTP"
EXU="$EXU"
EXT="$EXT"
ZAPRET="$([ -n "$ZT" ] && echo 1 || echo 0)"
ST
	logger -t fakedpi "запущен: WAN=[$WAN] fakesip=$SIP(q$QSIP) fakehttp=$HTTP(q$QHTTP)"
}

stop_service() {
	nft delete table inet "$TABLE" 2>/dev/null
	rm -f "$STATE"
}

reload_service() {
	stop
	start
}

service_triggers() {
	procd_add_reload_trigger fakedpi
	procd_add_interface_trigger "interface.*.up" wan /etc/init.d/fakedpi reload
	procd_add_interface_trigger "interface.*.up" wan6 /etc/init.d/fakedpi reload
}
EOF
	chmod 755 "$INIT"
	ok "Создан сервис $INIT"
}

# ---------- команды ----------
do_status() {
	printf "\n${B}══════ FakeDPI %s ══════${N}\n" "$VERSION"
	for b in fakesip fakehttp; do
		if [ ! -x "$BIN_DIR/$b" ]; then
			printf "  %-9s ${R}не установлен${N}\n" "$b"
		elif pidof "$b" >/dev/null 2>&1; then
			printf "  %-9s ${G}работает${N} (pid %s)\n" "$b" "$(pidof "$b")"
		else
			printf "  %-9s ${Y}не запущен${N}\n" "$b"
		fi
	done
	if [ -f /var/run/fakedpi.state ]; then
		. /var/run/fakedpi.state
		printf "  WAN:      %s\n" "${WAN:-не найден}"
		printf "  Очереди:  fakesip=%s  fakehttp=%s\n" "$QSIP" "$QHTTP"
		printf "  Не трогаем UDP: %s\n" "${EXU:-—}"
		printf "  Не трогаем TCP: %s\n" "${EXT:-—}"
		[ "$ZAPRET" = 1 ] && printf "  Совместимость с zapret: ${G}вкл${N}\n"
	fi
	if nft list table inet fakedpi >/dev/null 2>&1; then
		ps="$(nft list chain inet fakedpi sip_rules 2>/dev/null | grep -o 'packets [0-9]*' | tail -n1 | awk '{print $2}')"
		ph="$(nft list chain inet fakedpi http_rules 2>/dev/null | grep -o 'packets [0-9]*' | awk '{s+=$2} END{print s+0}')"
		printf "  Обработано пакетов: UDP=%s  TCP=%s\n" "${ps:-0}" "${ph:-0}"
	else
		printf "  Правила nftables: ${R}не загружены${N}\n"
	fi
	echo
}

do_install() {
	printf "\n${B}══════ Установка FakeDPI %s (FakeSIP + FakeHTTP) ══════${N}\n\n" "$VERSION"
	arch="$(detect_arch)"
	[ -n "$arch" ] || die "Неизвестная архитектура: $(. /etc/openwrt_release; echo "$DISTRIB_ARCH")"
	ok "Архитектура: $arch"

	install_deps

	[ -x "$INIT" ] && "$INIT" stop >/dev/null 2>&1
	for b in fakesip fakehttp; do [ -x "$BIN_DIR/$b" ] && "$BIN_DIR/$b" -k >/dev/null 2>&1; done

	install_bin fakesip FakeSIP "$arch"
	install_bin fakehttp FakeHTTP "$arch"

	write_config
	write_init

	if [ -f "$0" ] && [ "$(readlink -f "$0")" != "$SELF" ]; then
		cp -f "$0" "$SELF" && chmod 755 "$SELF" && ok "Команда управления: fakedpi"
	fi

	"$INIT" enable
	"$INIT" start
	sleep 2
	do_status
	ok "Готово. Сервис включён и стартует при загрузке роутера."
	info "Настройки: $CFG  →  после правки: fakedpi restart"
}

do_update() {
	arch="$(detect_arch)"
	[ -n "$arch" ] || die "Неизвестная архитектура"
	"$INIT" stop >/dev/null 2>&1
	install_bin fakesip FakeSIP "$arch"
	install_bin fakehttp FakeHTTP "$arch"
	write_init
	"$INIT" start
	sleep 2
	do_status
}

do_remove() {
	info "Удаляю FakeDPI..."
	if [ -x "$INIT" ]; then
		"$INIT" stop >/dev/null 2>&1
		"$INIT" disable >/dev/null 2>&1
	fi
	for b in fakesip fakehttp; do [ -x "$BIN_DIR/$b" ] && "$BIN_DIR/$b" -k >/dev/null 2>&1; done
	nft delete table inet fakedpi 2>/dev/null
	rm -f "$INIT" "$CFG" "$BIN_DIR/fakesip" "$BIN_DIR/fakehttp" /var/run/fakedpi.state /var/run/fakedpi.nft
	ok "FakeSIP и FakeHTTP удалены (kmod-nft-queue оставлен — он нужен zapret)"
	rm -f "$SELF"
}

case "$1" in
	""|install) do_install ;;
	status)     do_status ;;
	update)     do_update ;;
	remove|uninstall) do_remove ;;
	start|stop|restart|enable|disable)
		[ -x "$INIT" ] || die "Не установлено. Запустите: sh $0"
		"$INIT" "$1"; [ "$1" = start ] || [ "$1" = restart ] && { sleep 2; do_status; } ;;
	*) echo "Использование: $0 [install|status|restart|stop|start|update|remove]"; exit 1 ;;
esac
