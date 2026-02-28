#!/bin/sh

echo -e "\033[0;32m🔥 ПОЛНАЯ ЧИСТКА ВСЕХ КАТАЛОГОВ\033[0m"

# СТОП СЕРВИСОВ
echo -e "\033[1;33mСервисы off\033[0m"
for svc in mihomo hev-socks5-tunnel magitrickle; do /etc/init.d/$svc stop 2>/dev/null; done

# ПАКЕТЫ
echo -e "\033[1;33mПакеты rm\033[0m"
opkg list-installed | grep -E "(hev-socks5-tunnel|magitrickle|kmod-nft-tproxy)" | cut -d' ' -f1 | xargs opkg remove -y >/dev/null 2>&1

# 🔥 ВСЕ /etc/ + ФАЙЛЫ
echo -e "\033[1;33mВСЕ /etc/ каталоги rm\033[0m"
rm -rf /etc/{mihomo,hev-socks5-tunnel,magitrickle} /etc/config/{hev-socks5-tunnel,mihomo}
rm -rf /www/luci-static/resources/view/{mihomo,magitrickle}
rm -f /usr/bin/mihomo /etc/init.d/{mihomo,hev-socks5-tunnel,magitrickle}
rm -f /usr/share/luci/menu.d/luci-app-*.json /usr/share/rpcd/acl.d/luci-app-mihomo.json

# LuCI
echo -e "\033[1;33mLuCI чистка\033[0m"
rm -rf /tmp/luci-*
/etc/init.d/rpcd restart >/dev/null 2>&1
/etc/init.d/uhttpd restart >/dev/null 2>&1

echo -e "\n\033[0;32m✅ ВСЁ УДАЛЕНО! Reboot? (y/n)\033[0m"
read ans
[ "$ans" = y ] && reboot
