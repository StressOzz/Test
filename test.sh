#!/bin/sh
# Автоустановка tg-ws-proxy на OpenWrt (opkg или apk), строго по оригиналу

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
    echo "Не найден пакетный менеджер (opkg или apk)"
    exit 1
fi

echo "=== Обновляем пакеты ($PKG) ==="
$UPDATE

echo "=== Устанавливаем Python, pip и git ==="
$INSTALL python3-light python3-pip git git-http ca-certificates

# Клонируем tg-ws-proxy
WORKDIR="/root/tg-ws-proxy"
if [ ! -d "$WORKDIR" ]; then
    cd /root
    git clone https://github.com/Flowseal/tg-ws-proxy
else
    cd "$WORKDIR"
    git pull || true
fi

# Устанавливаем tg-ws-proxy
cd "$WORKDIR"
pip install -e .

# Создаём init.d для автозапуска
cat << 'EOF' > /etc/init.d/tg-ws-proxy
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

chmod +x /etc/init.d/tg-ws-proxy
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo "=== Установка завершена ==="
echo "Telegram прокси доступен на IP роутера :1080"
