#!/bin/sh

echo "Установка универсального ttyd для OpenWrt с автозапуском Zapret-Manager.sh..."

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

URL="https://github.com/eastlondoner/ttyd/releases/latest/download/$BIN"
echo "Архитектура: $ARCH"
echo "Загрузка ttyd: $URL"

# Скачиваем ttyd через wget
wget -O /usr/bin/ttyd "$URL" 2>/dev/null
chmod +x /usr/bin/ttyd

# Проверяем наличие скрипта Zapret-Manager.sh
if [ ! -f /root/Zapret-Manager.sh ]; then
    echo "Ошибка: /root/Zapret-Manager.sh не найден!"
    exit 1
fi

# Создаём init-скрипт для автозапуска ttyd
cat << 'EOF' > /etc/init.d/ttyd
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    # ttyd без логина, сразу запускаем Zapret-Manager.sh
    procd_set_param command /usr/bin/ttyd -p 17681 -W -a "" -- bash /root/Zapret-Manager.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/ttyd

# Включаем и перезапускаем сервис
/etc/init.d/ttyd enable
/etc/init.d/ttyd restart

# Проверка
if pidof ttyd >/dev/null; then
    echo "Готово! Доступ через браузер: http://<IP-роутера>:17681"
    echo "При подключении сразу запускается Zapret-Manager.sh"
else
    echo "Ошибка: ttyd не запустился."
fi
