#!/bin/sh

GREEN="\033[1;32m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
NC="\033[0m"

LAN_IP=$(uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1)

if command -v opkg >/dev/null 2>&1; then
    PKG="opkg"
    UPDATE="opkg update"
    INSTALL="opkg install"
    REMOVE="opkg remove"
else
    PKG="apk"
    UPDATE="apk update"
    INSTALL="apk add"
    REMOVE="apk del"
fi

echo -e "${MAGENTA}=== Обновляем пакеты ===${NC}"
$UPDATE

echo -e "${MAGENTA}=== Устанавливаем минимально необходимые пакеты ===${NC}"
# Устанавливаем python3-pip, но потом удалим его
$INSTALL python3-light python3-pip git-http

WORKDIR="/root/tg-ws-proxy"
if [ ! -d "$WORKDIR" ]; then
    cd /root
    git clone --depth 1 https://github.com/Flowseal/tg-ws-proxy
else
    cd "$WORKDIR"
    git pull --depth 1 || true
fi

cd "$WORKDIR"

# Устанавливаем зависимости
pip install --no-cache-dir -r requirements.txt

# Создаем init скрипт
cat << 'EOF' > /etc/init.d/tg-ws-proxy
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/python3 /root/tg-ws-proxy/tg_ws_proxy/__main__.py --host 0.0.0.0
    procd_set_param limits memory="262144"
    procd_set_param respawn
    procd_close_instance
}
EOF

chmod +x /etc/init.d/tg-ws-proxy

echo -e "${MAGENTA}=== Очистка ненужных файлов ===${NC}"

# Очищаем pip кэш
pip cache purge 2>/dev/null || true
rm -rf /root/.cache
rm -rf /root/.cache/pip 2>/dev/null

# Удаляем ненужные файлы проекта
cd "$WORKDIR"
find . -name "*.pyc" -delete
find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
rm -rf .git .gitignore .github tests examples docs *.md 2>/dev/null

# Удаляем тесты и документацию Python
echo -e "${YELLOW}Удаляем тесты и документацию Python...${NC}"
find /usr/lib/python3.* -name "test" -type d -exec rm -rf {} + 2>/dev/null
find /usr/lib/python3.* -name "tests" -type d -exec rm -rf {} + 2>/dev/null
find /usr/lib/python3.* -name "*.txt" -delete 2>/dev/null
find /usr/lib/python3.* -name "*.pyc" -delete 2>/dev/null
find /usr/lib/python3.* -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null

# Удаляем документацию и примеры из системы
rm -rf /usr/share/doc 2>/dev/null
rm -rf /usr/share/man 2>/dev/null
rm -rf /usr/share/info 2>/dev/null

# Удаляем git (экономия ~5-10 МБ)
if command -v git >/dev/null 2>&1; then
    echo -e "${YELLOW}Удаляем git...${NC}"
    $REMOVE git-http 2>/dev/null || true
fi

# Удаляем pip и python3-pip (но сохраняем установленные пакеты)
echo -e "${YELLOW}Удаляем pip...${NC}"
# Удаляем сам pip, но оставляем установленные зависимости
$REMOVE python3-pip 2>/dev/null || true
# Дополнительно чистим остатки pip
rm -rf /usr/lib/python3.*/site-packages/pip* 2>/dev/null
rm -rf /usr/lib/python3.*/site-packages/pip-*.dist-info 2>/dev/null
rm -rf /usr/bin/pip* 2>/dev/null

# Опционально: если нужна еще экономия, можно удалить ensurepip
rm -rf /usr/lib/python3.*/ensurepip 2>/dev/null

# Запускаем сервис
/etc/init.d/tg-ws-proxy enable
/etc/init.d/tg-ws-proxy start

echo -e "\n${GREEN}=== Установка завершена ===${NC}"
echo -e "\n${YELLOW}Telegram прокси доступен на ${NC}$LAN_IP:1080"

# Показываем экономию памяти
echo -e "\n${MAGENTA}=== Использование памяти ===${NC}"
free -h

# Показываем размер установленных Python пакетов
echo -e "\n${MAGENTA}=== Размер установленных пакетов ===${NC}"
du -sh /usr/lib/python3.*/site-packages/ 2>/dev/null || true
