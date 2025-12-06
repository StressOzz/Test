#!/bin/sh

echo "Установка универсального ttyd для OpenWrt..."

ARCH="$(uname -m)"

case "$ARCH" in
    x86_64)    BIN="ttyd.x86_64" ;;
    aarch64)   BIN="ttyd.aarch64" ;;
    arm*)      BIN="ttyd.arm" ;;
    mips)      BIN="ttyd.mips" ;;
    mipsel)    BIN="ttyd.mipsel" ;;
    *) echo "Неизвестная архитектура: $ARCH"; exit 1 ;;
esac

URL="https://github.com/tsl0922/ttyd/releases/latest/download/$BIN"

echo "Архитектура: $ARCH"
echo "Загрузка: $URL"

wget -O /usr/bin/ttyd "$URL" 2>/dev/null
chmod +x /usr/bin/ttyd

# Создаем init-скрипт с запуском Zapret-Manager.sh
cat << 'EOF' > /etc/init.d/ttyd
#!/bin/sh /etc/rc.common
START=95
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/ttyd -p 17681 -W -a login -- bash /root/Zapret-Manager.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/ttyd

# Enable & restart
/etc/init.d/ttyd enable
/etc/init.d/ttyd restart

# Проверка
if pidof ttyd >/dev/null; then
    echo "Готово! Доступ: http://<IP-роутера>:17681"
else
    echo "Ошибка: ttyd не запустился."
fi
