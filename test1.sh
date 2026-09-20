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
		curl -fsSL --connect-timeout 30 -o "$2" "$1"
	else
		wget -q -T 30 -O "$2" "$1"
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
install_payload() {
	command -v base64 >/dev/null 2>&1 || die "в системе нет base64"
	T=/tmp/ytb-payload
	rm -rf "$T"; mkdir -p "$T"
	base64 -d <<'YTB_PAYLOAD_EOF' | tar -xzf - -C "$T" || die "не удалось распаковать файлы приложения"
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
JmMAyAAA
YTB_PAYLOAD_EOF
	# пользовательский конфиг при обновлении не затираем
	[ -f /etc/config/ytbypass ] && rm -f "$T/etc/config/ytbypass"
	cp -a "$T/." / || die "не удалось скопировать файлы"
	rm -rf "$T"
	chmod 755 /etc/init.d/ytbypass /usr/bin/ytbypass /usr/libexec/ytbypass/*.sh /etc/hotplug.d/firewall/90-ytbypass
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
