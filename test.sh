#!/bin/sh

# Универсальный скрипт установки tg-ws-proxy на OpenWrt 24–25 (opkg/Alpine APK)
set -e

echo "=== Определяем пакетный менеджер ==="
if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    UPDATE="opkg update"
    INSTALL="opkg install"
elif command -v apk >/dev/null 2>&1; then
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
else
    echo "Не найден поддерживаемый пакетный менеджер (opkg или apk)"
    exit 1
fi

echo "=== Обновляем пакеты ($PKG) ==="
$UPDATE

echo "=== Устанавливаем Python и pip ==="
if [ "$PKG" = "opkg" ]; then
    $INSTALL python3-light python3-pip git-http ca-certificates
else
    $INSTALL python3 py3-pip git ca-certificates
fi

WORKDIR="/root/tg-ws-proxy"

# Клонируем репозиторий, если нет
if [ ! -d "$WORKDIR" ]; then
    echo "=== Клонируем tg-ws-proxy ==="
    cd /root
    git clone https://github.com/Flowseal/tg-ws-proxy
else
    echo "=== Репозиторий уже есть, обновляем ==="
    cd "$WORKDIR"
    git pull
fi

echo "=== Устанавливаем tg-ws-proxy ==="
cd "$WORKDIR"
pip install -e .

echo "=== Настраиваем автозапуск через procd ==="
INIT_FILE="/etc/init.d/tg-ws-proxy"
cat << 'EOF' > $INIT_FILE
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/tg-ws-proxy --host 0.0.0.0
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x $INIT_FILE
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo "=== Установка завершена! ==="
echo "Telegram прокси доступен на IP роутера и порту 1080"
