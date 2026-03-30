#!/bin/sh

BIN_PATH="/usr/bin/tg-ws-proxy-go"
INIT_PATH="/etc/init.d/tg-ws-proxy-go"
TMP_FILE="/tmp/tg-ws-proxy-go"

RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
NC="\033[0m"

get_arch() {
    case "$(uname -m)" in
        aarch64)
            echo "tg-ws-proxy-openwrt-aarch64"
            ;;
        armv7*|armv7l)
            echo "tg-ws-proxy-openwrt-armv7"
            ;;
        mipsel*)
            echo "tg-ws-proxy-openwrt-mipsel_24kc"
            ;;
        mips*)
            echo "tg-ws-proxy-openwrt-mips_24kc"
            ;;
        x86_64)
            echo "tg-ws-proxy-openwrt-x86_64"
            ;;
        *)
            return 1
            ;;
    esac
}

get_router_ip() {
    uci get network.lan.ipaddr 2>/dev/null | cut -d/ -f1
}

remove_all() {
    echo -e "${YELLOW}Удаляем tg-ws-proxy-go...${NC}"

    /etc/init.d/tg-ws-proxy-go stop >/dev/null 2>&1
    /etc/init.d/tg-ws-proxy-go disable >/dev/null 2>&1

    rm -f "$BIN_PATH"
    rm -f "$INIT_PATH"

    echo -e "${GREEN}Удалено.${NC}"
}

install_all() {
    echo -e "${GREEN}Установка tg-ws-proxy-go...${NC}"

    ARCH_FILE="$(get_arch)" || {
        echo -e "${RED}Неизвестная архитектура: $(uname -m)${NC}"
        exit 1
    }

    echo -e "${YELLOW}Архитектура: $ARCH_FILE${NC}"

    LATEST_URL="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/d0mhate/-tg-ws-proxy-Manager-go/releases/latest)"
    DOWNLOAD_URL="$LATEST_URL/$ARCH_FILE"

    echo -e "${YELLOW}Скачивание...${NC}"

    curl -L --fail -o "$TMP_FILE" "$DOWNLOAD_URL" || {
        echo -e "${RED}Ошибка скачивания${NC}"
        exit 1
    }

    mv "$TMP_FILE" "$BIN_PATH"
    chmod +x "$BIN_PATH"

    echo -e "${GREEN}Бинарник установлен.${NC}"

    cat << 'EOF' > "$INIT_PATH"
#!/bin/sh /etc/rc.common

START=99
STOP=10

NAME=tg-ws-proxy-go
PROG=/usr/bin/tg-ws-proxy-go
PIDFILE=/var/run/$NAME.pid

start() {
    echo "Запускаем $NAME..."

    if pidof $NAME >/dev/null; then
        echo "Уже запущен"
        return 0
    fi

    $PROG --host 0.0.0.0 --port 1080 >/dev/null 2>&1 &
    echo $! > $PIDFILE
}

stop() {
    echo "Останавливаем $NAME..."

    if [ -f $PIDFILE ]; then
        kill $(cat $PIDFILE) 2>/dev/null
        rm -f $PIDFILE
    fi

    killall $NAME 2>/dev/null
}

restart() {
    stop
    sleep 1
    start
}

status() {
    if pidof $NAME >/dev/null; then
        echo "$NAME запущен"
        return 0
    else
        echo "$NAME не запущен"
        return 1
    fi
}
EOF

    chmod +x "$INIT_PATH"

    /etc/init.d/tg-ws-proxy-go enable
    /etc/init.d/tg-ws-proxy-go start

    IP="$(get_router_ip)"

    echo -e "\n${GREEN}Установка завершена!${NC}"
    echo -e "${YELLOW}адрес SOCKS5: ${NC}${IP}:1080"
}

main() {
    echo "==== tg-ws-proxy-go installer ===="

    if ! command -v curl >/dev/null 2>&1; then
        echo -e "${RED}curl не установлен${NC}"
        exit 1
    fi

    if [ -f "$BIN_PATH" ] || [ -f "$INIT_PATH" ]; then
        remove_all
    else
        install_all
    fi
}

main "$@"
