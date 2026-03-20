#!/bin/sh
set -e

echo "=== Обновляем пакеты и ставим Python ==="
apk update || opkg update
if command -v apk >/dev/null 2>&1; then
    apk add python3 ca-certificates wget tar
else
    opkg install python3-light ca-certificates wget tar
fi

# Устанавливаем pip вручную через get-pip.py
echo "=== Ставим pip ==="
wget -O /tmp/get-pip.py https://bootstrap.pypa.io/get-pip.py
python3 /tmp/get-pip.py

# Скачиваем tg-ws-proxy архивом
WORKDIR="/root/tg-ws-proxy"
if [ ! -d "$WORKDIR" ]; then
    cd /root
    wget -O tg-ws.tar.gz https://github.com/Flowseal/tg-ws-proxy/archive/refs/heads/master.tar.gz
    tar xzf tg-ws.tar.gz
    mv tg-ws-proxy-master tg-ws-proxy
fi

# Устанавливаем tg-ws-proxy
cd "$WORKDIR"
pip3 install -e .

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

echo "=== Готово ==="
echo "Telegram прокси доступен на IP роутера :1080"
