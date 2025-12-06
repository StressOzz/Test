echo "Установка универсального ttyd для OpenWrt..."

# Определяем архитектуру
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        TTYD_URL="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.x86_64"
        ;;
    aarch64)
        TTYD_URL="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.aarch64"
        ;;
    arm*)
        TTYD_URL="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.armhf"
        ;;
    mips)
        TTYD_URL="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.mips"
        ;;
    mipsel)
        TTYD_URL="https://github.com/tsl0922/ttyd/releases/latest/download/ttyd.mipsel"
        ;;
    *)
        echo "Неизвестная архитектура: $ARCH"
        echo "Скажи вывод uname -m — добавлю поддержку."
        exit 1
        ;;
esac

echo "Архитектура: $ARCH"
echo "Загрузка ttyd: $TTYD_URL"

# Скачиваем ttyd
curl -L -o /usr/bin/ttyd "$TTYD_URL"
chmod +x /usr/bin/ttyd

# Создаём init-скрипт
cat > /etc/init.d/ttyd <<'EOF'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
SERVICE_NAME="ttyd"

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/ttyd -p 17681 -W -a login -- bash /root/Zapret-Manager.sh
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/ttyd

# Создаём UCI-конфиг ttyd (чтобы LuCI его видела)
mkdir -p /etc/config
cat > /etc/config/ttyd <<'EOF'
config ttyd main
        option interface ''
        option command '/usr/bin/ttyd -p 17681 -W -a login -- bash /root/Zapret-Manager.sh'
EOF

# Запуск
/etc/init.d/ttyd enable
/etc/init.d/ttyd restart

# Проверка
if pidof ttyd >/dev/null; then
    echo "Готово: ttyd запущен."
    echo "Открывай http://IP:17681"
else
    echo "Ошибка: ttyd не запустился."
fi
