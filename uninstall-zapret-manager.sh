#!/bin/sh
# ----------------------------------------------------------------------------
# Zapret Manager LuCI uninstaller
#
# По умолчанию удаляет ТОЛЬКО веб-интерфейс (LuCI-панель) — то, что ставит
# install-zapret-manager.sh. Сам Zapret/Zapret2/DoH/TG WS Proxy, поставленные
# ЧЕРЕЗ панель, при этом не трогаются (их можно удалить кнопками в самом
# интерфейсе ДО того, как вы снесёте сам интерфейс).
#
# Использование на роутере (по SSH):
#   sh uninstall-zapret-manager.sh
# Или прямо с GitHub:
#   wget -O - https://raw.githubusercontent.com/<user>/<repo>/main/uninstall-zapret-manager.sh | sh
#
# Полное удаление ВСЕГО, что когда-либо ставилось через панель
# (Zapret, Zapret2, DoH, все 3 варианта TG WS Proxy) — включая сам интерфейс:
#   PURGE_ALL=1 sh uninstall-zapret-manager.sh
#
# Дополнительно сбросить /etc/hosts к чистому виду (localhost) —
# ОСТОРОЖНО: удалит и любые ваши собственные записи в hosts, не только
# добавленные через панель:
#   PURGE_ALL=1 RESET_HOSTS=1 sh uninstall-zapret-manager.sh
# ----------------------------------------------------------------------------

PURGE_ALL="${PURGE_ALL:-0}"
RESET_HOSTS="${RESET_HOSTS:-0}"

if command -v apk >/dev/null 2>&1; then DELETE="apk del"
else DELETE="opkg remove"; fi

echo "==> Удаляем интерфейс Zapret Manager (LuCI)"
rm -rf \
	/usr/lib/zapret-manager \
	/usr/libexec/rpcd/zapret-manager \
	/usr/share/rpcd/acl.d/luci-app-zapret-manager.json \
	/usr/share/luci/menu.d/luci-app-zapret-manager.json \
	/www/luci-static/resources/view/zapret-manager \
	/www/luci-static/resources/zapret-manager \
	/tmp/zapret-manager

if [ "$PURGE_ALL" = "1" ]; then
	echo "==> PURGE_ALL=1: удаляем всё, что ставилось через панель"

	echo "--> Zapret"
	/etc/init.d/zapret stop >/dev/null 2>&1
	for p in $(pgrep -f /opt/zapret 2>/dev/null); do kill -9 "$p" 2>/dev/null; done
	$DELETE luci-app-zapret >/dev/null 2>&1
	$DELETE zapret >/dev/null 2>&1
	rm -rf /opt/zapret /etc/config/zapret /etc/init.d/zapret /etc/firewall.zapret
	crontab -l 2>/dev/null | grep -v -i zapret | crontab - 2>/dev/null

	echo "--> Zapret2"
	/etc/init.d/zapret2 stop >/dev/null 2>&1
	$DELETE luci-app-zapret2 >/dev/null 2>&1
	$DELETE zapret2 >/dev/null 2>&1
	rm -rf /opt/zapret2 /etc/config/zapret2 /etc/init.d/zapret2

	echo "--> DNS over HTTPS"
	$DELETE https-dns-proxy luci-app-https-dns-proxy >/dev/null 2>&1
	rm -f /etc/config/https-dns-proxy /etc/init.d/https-dns-proxy
	/etc/init.d/dnsmasq restart >/dev/null 2>&1

	echo "--> TG WS Proxy (MTProto/SOCKS5/Rust)"
	/etc/init.d/tg-ws-proxy stop >/dev/null 2>&1
	/etc/init.d/tg-ws-proxy disable >/dev/null 2>&1
	$DELETE tg-ws-proxy >/dev/null 2>&1
	rm -rf /etc/tg-ws-proxy /etc/tg-ws-proxy.conf /etc/tg-ws-proxy.conf-opkg
	[ -x /etc/init.d/tg-ws-proxy-go ] && { /etc/init.d/tg-ws-proxy-go stop >/dev/null 2>&1; /etc/init.d/tg-ws-proxy-go disable >/dev/null 2>&1; }
	rm -f /usr/bin/tg-ws-proxy-go /etc/init.d/tg-ws-proxy-go
	[ -x /etc/init.d/tg-ws-proxy-rs ] && { /etc/init.d/tg-ws-proxy-rs stop >/dev/null 2>&1; /etc/init.d/tg-ws-proxy-rs disable >/dev/null 2>&1; }
	rm -f /usr/bin/tg-ws-proxy-rs /etc/init.d/tg-ws-proxy-rs /etc/tg-ws-proxy-rs.secret

	if [ "$RESET_HOSTS" = "1" ]; then
		echo "--> Сброс /etc/hosts к чистому виду"
		printf '%s\n' "127.0.0.1	localhost" "" "::1	localhost ip6-localhost ip6-loopback" "ff02::1 ip6-allnodes" "ff02::2 ip6-allrouters" > /etc/hosts
	fi
fi

echo "==> Перезапускаем rpcd и uhttpd"
rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
/etc/init.d/rpcd restart >/dev/null 2>&1
/etc/init.d/uhttpd restart >/dev/null 2>&1

echo
echo "==> Готово. Zapret Manager удалён."
[ "$PURGE_ALL" = "1" ] || echo "    (только интерфейс — Zapret/Zapret2/DoH/TG WS Proxy, если ставились, остались нетронуты)"
