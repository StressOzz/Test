#!/bin/bash
echo -e $'\033[33mВведите логин для доступа к zeefeer через браузер (0 - отказ от логина через web в z4r и переход на логин в ssh (может помочь в safari). Enter - пустой логин, \033[31mно не рекомендуется, панель может быть доступна из интернета!)\033[0m'
read -r ttyd_login
 echo -e "${yellow}Если вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки${plain}"
 
 ttyd_login_have="-c "${ttyd_login}": bash z4r"
 if [[ "$ttyd_login" == "0" ]]; then
	echo "Отключение логина в веб. Перевод с z4r на CLI логин."
    ttyd_login_have="login"
 fi
 
 if [[ "$OSystem" == "VPS" ]]; then
	echo -e "${yellow}Установка ttyd for VPS${plain}"
	systemctl stop ttyd 2>/dev/null || true
	curl -L -o /usr/bin/ttyd https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64
	chmod +x /usr/bin/ttyd
	
	cat > /etc/systemd/system/ttyd.service <<EOF
[Unit]
Description=ttyd WebSSH Service
After=network.target

[Service]
ExecStart=/usr/bin/ttyd -p 17681 -W -a ${ttyd_login_have}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

	systemctl daemon-reload
	systemctl enable ttyd
	systemctl start ttyd
 elif [[ "$OSystem" == "WRT" ]]; then
	echo -e "${yellow}Установка ttyd for WRT${plain}"
	/etc/init.d/ttyd stop 2>/dev/null || true
	opkg install ttyd
    uci set ttyd.@ttyd[0].interface=''
    uci set ttyd.@ttyd[0].command="-p 17681 -W -a ${ttyd_login_have}"
	uci commit ttyd
	/etc/init.d/ttyd enable
	/etc/init.d/ttyd start
 elif [[ "$OSystem" == "entware" ]]; then
	echo -e "${yellow}Установка ttyd for Entware${plain}"
	/opt/etc/init.d/S99ttyd stop 2>/dev/null || true
	opkg install ttyd
	
	cat > /opt/etc/init.d/S99ttyd <<EOF
#!/bin/sh

START=99

case "\$1" in
  start)
    echo "Starting ttyd..."
    ttyd -p 17681 -W -a ${ttyd_login_have} &
    ;;
  stop)
    echo "Stopping ttyd..."
    killall ttyd
    ;;
  restart)
    \$0 stop
    sleep 1
    \$0 start
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart}"
    exit 1
    ;;
esac
EOF

  chmod +x /opt/etc/init.d/S99ttyd
  /opt/etc/init.d/S99ttyd start
  sleep 1
  if netstat -tuln | grep -q ':17681'; then
	echo -e "${green}Порт 17681 для службы ttyd слушается${plain}"
  else
	echo -e "${red}Порт 17681 для службы ttyd не прослушивается${plain}"
  fi
 fi

 if pidof ttyd >/dev/null; then
	echo -e "Проверка...${green}Служба ttyd запущена.${plain}"
 else
	echo -e "Проверка...${red}Служба ttyd не запущена! Если у вас Entware, то после перезагрузки роутера служба скорее всего заработает!${plain}"
 fi
 echo -e "${plain}Выполнение установки завершено. ${green}Доступ по ip вашего роутера/VPS в формате ip:17681, например 192.168.1.1:17681 или mydomain.com:17681 ${yellow}логин: ${ttyd_login} пароль - не испольузется.${plain} Был выполнен выход из скрипта для сохранения состояния."
