#!/bin/bash

		echo "Скачиваем /opt/bin/z4r"
        curl -L -o /opt/bin/z4r https://raw.githubusercontent.com/IndeecFOX/z4r/main/z4r
        chmod +x /opt/bin/z4r

	echo "Скачиваем /usr/bin/z4r"
    curl -L -o /usr/bin/z4r https://raw.githubusercontent.com/IndeecFOX/z4r/main/z4r
    chmod +x /usr/bin/z4r


	echo -e $'\033[33mВведите логин для доступа к zeefeer через браузер (0 - отказ от логина через web в z4r и переход на логин в ssh (может помочь в safari). Enter - пустой логин, \033[31mно не рекомендуется, панель может быть доступна из интернета!)\033[0m'
 read ttyd_login
 echo -e "${yellow}Если вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки${plain}"
 
 ttyd_login_have="-c "${ttyd_login}": bash z4r"
 if [[ "$ttyd_login" == "0" ]]; then
	echo "Отключение логина в веб. Перевод с z4r на CLI логин."
    ttyd_login_have="login"
 fi
 

	echo -e "${yellow}Установка ttyd for WRT${plain}"
	/etc/init.d/ttyd stop
	opkg update
	opkg install ttyd
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd

	
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start

  if netstat -tuln | grep -q ':17681'; then
	echo -e "${green}Порт 17681 для службы ttyd слушается${plain}"
  else
	echo -e "${red}Порт 17681 для службы ttyd не прослушивается${plain}"
  fi

 if pidof ttyd >/dev/null; then
	echo -e "Проверка...${green}Служба ttyd запущена.${plain}"
 else
	echo -e "Проверка...${red}Служба ttyd не запущена! Если у вас Entware, то после перезагрузки роутера служба скорее всего заработает!${plain}"
 fi
 echo -e "${plain}Выполнение установки завершено. ${green}Доступ по ip вашего роутера/VPS в формате ip:17681, например 192.168.1.1:17681 или mydomain.com:17681 ${yellow}логин: ${ttyd_login} пароль - не испольузется.${plain} Был выполнен выход из скрипта для сохранения состояния."
