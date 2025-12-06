#!/bin/sh
	echo -e "Установка ttyd for WRT"

echo -n "Введите логин (0 — отключить логин): "
read ttyd_login

   ttyd_login_have="-c "${ttyd_login}": bash zm"
   
 if [[ "$ttyd_login" == "0" ]]; then
	echo "Отключение логина в веб. Перевод с z4r на CLI логин."
    ttyd_login_have="login"
 fi

   
	/etc/init.d/ttyd stop
	opkg update
	opkg install ttyd
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd

	chmod +x /usr/bin/zm
	chmod +x /zm
	chmod +x /root/zm
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start
