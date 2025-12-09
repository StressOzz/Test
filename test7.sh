#!/bin/sh

echo 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)' > /usr/bin/zms
chmod +x /usr/bin/zms
ttyd_login=""
 
	echo -e "Установка ttyd for WRT"
	/etc/init.d/ttyd stop 2>/dev/null || true
	
	opkg update
	
	opkg install ttyd
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start


 if pidof ttyd >/dev/null; then
	echo -e "Проверка...Служба ttyd запущена."
 else
	echo -e "Проверка...Служба ttyd не запущена! Если у вас Entware, то после перезагрузки роутера служба скорее всего заработает!"
 fi
 echo -e "Выполнение установки завершено. Доступ 192.168.1.1:17681 "
