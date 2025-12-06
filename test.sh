#!/bin/sh
echo -e $'\033[33mВведите логин для доступа к zeefeer через браузер (0 - отключить логин в web. Enter - пустой логин, \033[31mне рекомендуется!)\033[0m'
read -re -p '' ttyd_login
echo -e "${yellow}Если вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки${plain}"

# Формируем аргумент для ttyd
if [[ "$ttyd_login" == "0" ]]; then
    echo "Отключение логина в веб. Переход на CLI login."
    ttyd_login_have="login"
elif [[ -n "$ttyd_login" ]]; then
    ttyd_login_have="-c ${ttyd_login}: bash /root/Zapret-Manager.sh"
else
    echo -e "${red}Пустой логин — панель может быть доступна из интернета!${plain}"
    ttyd_login_have="-c nopass: bash /root/Zapret-Manager.sh"
fi

echo -e "${yellow}Установка ttyd for WRT${plain}"

# Остановка
/etc/init.d/ttyd stop 2>/dev/null || true

# Установка ttyd
opkg install ttyd

# Настройка
uci set ttyd.@ttyd[0].interface=''
uci set ttyd.@ttyd[0].command="-p 17681 -W -a '${ttyd_login_have}'"
uci commit ttyd

# Запуск
/etc/init.d/ttyd enable
/etc/init.d/ttyd start

# Проверка
if pidof ttyd >/dev/null; then
    echo -e "Проверка...${green}Служба ttyd запущена.${plain}"
else
    echo -e "Проверка...${red}Служба ttyd не запущена!${plain}"
fi

echo -e "${plain}Готово. Доступ: IP-адрес роутера:17681. ${yellow}Логин: ${ttyd_login} (пароль не используется).${plain}"
