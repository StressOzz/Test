#!/bin/sh

echo -e '\033[1;32msh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)\033[0m' > /usr/bin/zms
chmod +x /usr/bin/zms

echo -e "\033[1;36mУстановка ttyd for WRT\033[0m"

/etc/init.d/ttyd stop >/dev/null 2>&1 || true
opkg update
opkg install ttyd bash

uci set ttyd.@ttyd[0].interface=''
uci set ttyd.@ttyd[0].command="-p 17681 -W -a -c : bash zms"
uci commit ttyd

/etc/init.d/ttyd enable
/etc/init.d/ttyd start

if pidof ttyd >/dev/null; then
    echo -e "\033[1;32mСлужба ttyd запущена.\033[0m"
else
    echo -e "\033[1;31mСлужба ttyd не запущена! На Entware она часто стартует после перезагрузки.\033[0m"
fi

echo -e "\033[1;33mУстановка завершена. Доступ: http://192.168.1.1:17681\033[0m"
