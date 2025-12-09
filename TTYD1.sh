#!/bin/sh
echo -e 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)' > /usr/bin/zms
chmod +x /usr/bin/zms; echo -e "\033[1;32Установка ttyd for WRT\033[0m"; opkg update >/dev/null 2>&1;opkg install ttyd >/dev/null 2>&1
uci set ttyd.@ttyd[0].interface=''; uci set ttyd.@ttyd[0].command="-W -a sh /usr/bin/zms"; uci commit ttyd >/dev/null 2>&1
/etc/init.d/ttyd enable >/dev/null 2>&1; /etc/init.d/ttyd start >/dev/null 2>&1
if pidof ttyd >/dev/null; then echo -e "\033[1;32mСлужба ttyd запущена.\nДоступ: http://192.168.1.1:7681\n\033[0m"; else echo -e "\033[1;31mСлужба ttyd не запущена!\033[0m"; fi
