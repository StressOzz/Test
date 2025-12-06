#!/bin/sh

yellow='\033[33m'
red='\033[31m'
green='\033[32m'
plain='\033[0m'

# Ввод логина

# printf "${yellow}Введите логин для доступа к zeefeer через браузер (0 - отказ от логина через web в z4r и переход на логин в ssh (может помочь в safari). Enter - пустой логин, ${red}но не рекомендуется, панель может быть доступна из интернета!)${plain}\n"
# printf "> "
# read ttyd_login

# printf "${yellow}Если вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки${plain}\n"

# Остановка ttyd, если уже установлен

/etc/init.d/ttyd stop 2>/dev/null || true

# Установка через opkg

opkg update
opkg install ttyd

# Настройка через UCI

uci set ttyd.@ttyd[0].interface=''
uci set ttyd.@ttyd[0].command="-p 17681 -W -a -c bash z4r"
uci commit ttyd

# Включение и запуск службы

/etc/init.d/ttyd enable
/etc/init.d/ttyd start


# Проверка работы процесса

if pidof ttyd >/dev/null; then
echo -e "Проверка...${green}Служба ttyd запущена.${plain}"
else
echo -e "Проверка...${red}Служба ttyd не запущена! После перезагрузки роутера служба скорее всего заработает!${plain}"
fi

echo -e "${plain}Выполнение установки завершено. ${green}Доступ по ip вашего роутера в формате ip:17681, например 192.168.1.1:17681 ${yellow}логин: ${ttyd_login} пароль не используется.${plain}"
