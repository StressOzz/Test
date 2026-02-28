#!/bin/sh

echo -e "\033[0;32m🔥 НАХОДИМ И УДАЛЯЕМ ВСЁ\033[0m"

# 1. НАХОДИМ ЦЕЛИ
echo -e "\033[1;33mИщем файлы/папки...\033[0m"
find /etc /usr /www /opt -name "*mihom*" -o -name "*hev*" -o -name "*magitri*" -o -name "*clash*" 2>/dev/null | head -20

# 2. СТОП СЕРВИСОВ
echo -e "\033[1;33mСервисы off\033[0m"
killall mihomo hev-socks5-tunnel magitrickle 2>/dev/null
for svc in mihomo hev-socks5-tunnel magitrickle clash; do /etc/init.d/$svc stop 2>/dev/null; done

# 3. ПАКЕТЫ (ВСЕ)
echo -e "\033[1;33mПакеты rm\033[0m"
opkg list-installed | grep -iE "(mihom|hev|magitri|clash|kmod-nft-tproxy)" | cut -d' ' -f1 | xargs opkg remove -y 2>/dev/null

# 4. 🔥 МАССОВЫЙ rm -rf ПО ИМЕНАМ
echo -e "\033[1;33mrm ВСЁ по именам...\033[0m"
rm -rf /etc/mihomo /etc/hev* /etc/magitrickle /etc/openclash /etc/clash
rm -rf /usr/share/mihomo /usr/share/magitrickle /opt/var/lib/magitrickle
rm -rf /www/luci-static/resources/view/mihomo* /www/luci-static/resources/view/magitri* /www/luci-static/resources/view/clash*
rm -f /usr/bin/{mihomo,clash,hev-socks5-tunnel,magitrickle}
rm -f /etc/init.d/{mihomo*,hev*,magitrickle*,clash*}
rm -f /usr/share/luci/menu.d/*{mihom,magitri,hev,clash}*.json
rm -f /usr/share/rpcd/acl.d/*{mihom,clash}.json
rm -f /etc/config/{mihomo*,hev*,magitrickle*,clash*,openclash*}

# 5. LuCI + tmp
rm -rf /tmp/luci-*
/etc/init.d/rpcd restart 2>/dev/null
/etc/init.d/uhttpd restart 2>/dev/null

# ПРОВЕРКА
echo -e "\033[1;33mЧто осталось?\033[0m"
find /etc /usr /www /opt -name "*mihom*" -o -name "*hev*" -o -name "*magitri*" 2>/dev/null || echo "НИЧЕГО!"

echo -e "\n\033[0;32m✅ ЧИСТО! Reboot?\033[0m"
read ans; [ "$ans" = y ] && reboot
