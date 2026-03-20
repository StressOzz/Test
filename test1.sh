#!/bin/sh

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

echo "=== Ставим Python и python3-py (с pip через ensurepip) ==="
if [ "$PKG" = "opkg" ]; then
    $INSTALL python3-light python3-py git-http ca-certificates || $INSTALL python3-light python3 ca-certificates
else
    $INSTALL python3 python3-py git ca-certificates
fi

echo "=== Проверяем pip3 ==="
if ! command -v pip3 >/dev/null 2>&1; then
    echo "pip3 не найден, создаём через ensurepip"
    python3 -m ensurepip --upgrade || true
fi

# fallback если всё ещё нет pip
if ! command -v pip3 >/dev/null 2>&1; then
    echo "Ставим pip через get-pip.py"
    wget -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
    python3 /tmp/get-pip.py
fi

WORKDIR="/root/tg-ws-proxy"

echo "=== Скачиваем tg-ws-proxy ==="
if [ ! -d "$WORKDIR" ]; then
    cd /root
    if command -v git >/dev/null 2>&1; then
        git clone https://github.com/Flowseal/tg-ws-proxy
    else
        wget -O tg-ws.tar.gz https://github.com/Flowseal/tg-ws-proxy/archive/refs/heads/master.tar.gz
        tar xzf tg-ws.tar.gz
        mv tg-ws-proxy-master tg-ws-proxy
    fi
fi

echo "=== Устанавливаем tg-ws-proxy ==="
cd "$WORKDIR"
pip3 install -e .

echo "=== Создаём init.d для автозапуска ==="
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

echo "=== Установка завершена! ==="
echo "Telegram прокси доступен на IP роутера и порту 1080"
