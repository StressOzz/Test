#!/bin/sh
# Автоустановка tg-ws-proxy на OpenWrt (24/25), определение пакетов

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

echo "=== Ставим Python и необходимые утилиты ==="
if [ "$PKG" = "opkg" ]; then
    $INSTALL python3-light python3-pip git-http ca-certificates
else
    $INSTALL python3 python3-py git ca-certificates wget tar
fi

# Проверка pip
if ! command -v pip3 >/dev/null 2>&1; then
    echo "pip не найден, ставим через get-pip.py"
    wget -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
    python3 /tmp/get-pip.py
fi

# Клонируем tg-ws-proxy
WORKDIR="/root/tg-ws-proxy"
if [ ! -d "$WORKDIR" ]; then
    cd /root
    if command -v git >/dev/null 2>&1; then
        git clone https://github.com/Flowseal/tg-ws-proxy
    else
        echo "git не найден, скачиваем архив tg-ws-proxy"
        wget -O tg-ws.tar.gz https://github.com/Flowseal/tg-ws-proxy/archive/refs/heads/master.tar.gz
        tar xzf tg-ws.tar.gz
        mv tg-ws-proxy-master tg-ws-proxy
    fi
else
    echo "tg-ws-proxy уже есть, обновляем"
    cd "$WORKDIR"
    git pull || true
fi

# Устанавливаем tg-ws-proxy
cd "$WORKDIR"
pip3 install -e .

# Создаём init.d для автозапуска
INIT_FILE="/etc/init.d/tg-ws-proxy"
cat << 'EOF' > "$INIT_FILE"
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

chmod +x "$INIT_FILE"
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo "=== Установка завершена ==="
echo "Telegram прокси доступен на IP роутера :1080"
