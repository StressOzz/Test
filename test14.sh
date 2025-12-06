#!/bin/sh
	echo -e "Установка ttyd for WRT"

   ttyd_login_have="-c "${ttyd_login}": bash z4r"
   
 if [[ "$ttyd_login" == "0" ]]; then
	echo "Отключение логина в веб. Перевод с z4r на CLI логин."
    ttyd_login_have="login"
 fi

   
	/etc/init.d/ttyd stop 2>/dev/null || true
	opkg install ttyd
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start
