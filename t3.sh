#!/bin/sh

echo -e "\033[0;32m🔥 ЖЁСТКАЯ ЧИСТКА - БЕЗ ОШИБОК\033[0m"

# 1. КИЛЛ + СТОП
killall mihomo hev-socks5-tunnel magitrickled 2>/dev/null
for svc in mihomo hev-socks5-tunnel magitrickle; do 
  /etc/init.d/$svc stop 2>/dev/null; 
  rm -f /etc/init.d/$svc /etc/rc.d/S99$svc;
done

# 2. ПАКЕТЫ - ПРЯМО ПО ИМЁНАМ
echo -e "\033[1;33mПакеты rm ПРЯМО\033[0m"
opkg remove hev-socks5-tunnel magitrickle magitrickle_mod kmod-nft-tproxy 2>/dev/null

# 3. rm -f ВСЕ КОНКРЕТНЫЕ ФАЙЛЫ (НЕ rf)
echo -e "\033[1;33mrm -f КАЖДЫЙ ФАЙЛ\033[0m"
rm -f /etc/config/{magitrickle,hev-socks5-tunnel,mihomo}
rm -f /usr/bin/{mihomo,hev-socks5-tunnel,magitrickled}
rm -rf /etc/{mihomo,magitrickle,"hev-socks5-tunnel"}
rm -f /usr/share/luci/menu.d/luci-app-{magitrickle,mihomo}.json
rm -f /usr/share/rpcd/acl.d/luci-app-mihomo.json

# 4. OPKG INFO мусор
rm -f /usr/lib/opkg/info/*{hev,magitrickle,mihomo,kmod-nft-tproxy}*

# 5. LuCI + остальное
rm -rf /www/luci-static/resources/view/{mihomo,magitrickle} /tmp/luci-*
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

# ПРОВЕРКА
echo -e "\033[1;33mОсталось?\033[0m"
ls -la /etc/config/*trick* /etc/config/*hev* /etc/init.d/* /usr/bin/*trick* /usr/bin/*hev* /usr/bin/mihomo 2>/dev/null || echo "🔥 ЧИСТО!"

echo -e "\n\033[0;32mReboot?\033[0m"
read ans; [ "$ans" = y ] && reboot
