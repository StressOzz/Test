#!/bin/sh

echo "\033[33mВведите логин для доступа к Zeefeer через браузер (0 - отключить логин, Enter - пустой логин, не рекомендуется)\033[0m"
read ttyd_login

echo "\033[33mЕсли вы открыли пункт через браузер - вас выкинет. Используйте SSH для установки\033[0m"

# Определяем, что запускать
if [ "$ttyd_login" = "0" ]; then
    echo "Отключение логина в веб. Запуск Zapret-Manager без логина"
    ttyd_login_param="-a \"\""
else
    ttyd_login_param="-a \"$ttyd_login\""
fi

# Определяем архитектуру
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  BIN="ttyd.x86_64" ;;
    aarch64) BIN="ttyd.aarch64" ;;
    arm*)    BIN="ttyd.arm" ;;
    mips)    BIN="ttyd.mips" ;;
    mipsel)  BIN="ttyd.mipsel" ;;
    *) echo "Неизвестная архитектура: $ARCH"; exit 1 ;;
esac

URL="https://github.com/tsl0922/ttyd/releases/latest/download/$BIN"
echo "Архитектура: $ARCH"
echo "Скачивание ttyd: $URL"

# Скачиваем ttyd через wget
wget -O /usr/bin/ttyd "$URL" 2>/dev/null
chmod +x /usr/bin/ttyd

# Проверка скрипта Zapret-Manager
if [ ! -f /root/Zapret-Manager.sh ]; then
    echo "Ошибка: /root/Zapret-Manager.sh не найден!"
    exit 1
fi

# Создаём init-скрипт для OpenWrt
cat << 'EOF' > /etc/init.d/ttyd
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    # ttyd запускается с указанным логином и сразу стартует Zapret-Manager
    procd_set_param command /usr/bin/ttyd -p 17681 -W -a "" -- bash /root/Zapret-Manager.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/ttyd

# Enable & restart ttyd
/etc/init.d/ttyd enable
/etc/init.d/ttyd restart

# Проверка
if pidof ttyd >/dev/null; then
    echo "Готово! Доступ через браузер: http://<IP-роутера>:17681"
else
    echo "Ошибка: ttyd не запустился."
fi
