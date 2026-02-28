#!/bin/sh

# СТОП
killall mihomo hev-socks5-tunnel magitrickled 2>/dev/null
for svc in mihomo hev-socks5-tunnel magitrickle; do rm -f /etc/init.d/$svc /etc/rc.d/S99$svc; done

# ПАКЕТЫ С --FORCE
opkg remove --force-removal-of-dependent-packages hev-socks5-tunnel magitrickle kmod-nft-tproxy >/dev/null 2>&1

# rm ВСЁ СИЛЬНО
rm -rf /etc/{mihomo,magitrickle,"hev-socks5-tunnel"} /etc/config/{hev*,magitri*,mihom*}
rm -f /usr/bin/{mihomo,hev*,magitri*}
rm -rf /www/luci-static/resources/view/{mihomo*,magitri*,hev*}
rm -f /usr/share/luci/menu.d/*{mihom,magitri,hev}*.json /usr/share/rpcd/acl.d/*mihom*.json
rm -rf /usr/lib/opkg/info/*{hev,magitri,mihom,kmod-nft}* /tmp/luci-*

/etc/init.d/rpcd restart >/dev/null 2>&1
/etc/init.d/uhttpd restart >/dev/null 2>&1

echo "✅ ЧИСТО! reboot? (y)"
read ans; [ "$ans" = y ] && reboot
