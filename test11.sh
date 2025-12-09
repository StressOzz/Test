#!/bin/sh

echo -e 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)' > /usr/bin/zms
chmod +x /usr/bin/zms

echo -e "\033[1;36mУстановка ttyd for WRT\033[0m"

/etc/init.d/ttyd stop
opkg update
opkg install ttyd

uci set ttyd.@ttyd[0].interface=''
uci set ttyd.@ttyd[0].command="-W -a sh /usr/bin/zms"
uci commit ttyd

/etc/init.d/ttyd enable
/etc/init.d/ttyd start

if pidof ttyd >/dev/null; then
    echo -e "\033[1;32mСлужба ttyd запущена.\033[0m"
else
    echo -e "\033[1;31mСлужба ttyd не запущена!\033[0m"
fi

echo -e "\033[1;33mУстановка завершена. Доступ: http://192.168.1.1:7681\033[0m"
