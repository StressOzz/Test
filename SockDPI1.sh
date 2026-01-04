#!/bin/sh

# Архитектура
Arch="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"

cd /tmp
opkg update
# Скачиваем и ставим ByeDPI

   LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)
    [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v noarch | tail -n1 | awk '{print $2}')

    echo -e "\n${MAGENTA}Установка ByeDPI"

    BYEDPI_VER="0.17.3-r1"
    BYEDPI_ARCH="$LOCAL_ARCH"
    BYEDPI_FILE="byedpi_${BYEDPI_VER}_${BYEDPI_ARCH}.ipk"
    BYEDPI_URL="https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/${BYEDPI_FILE}"

    echo -e "Скачиваем ${WHITE}$BYEDPI_FILE"
    mkdir -p "$WORKDIR"
    cd "$WORKDIR" || return

    wget -q -U "Mozilla/5.0" -O "$BYEDPI_FILE" "$BYEDPI_URL" || {
        echo -e "Ошибка загрузки $BYEDPI_FILE"
        read -p "Нажмите Enter..." dummy
        return
    }

    echo -e "Устанавливаем ${WHITE}$BYEDPI_FILE"
    opkg install --force-reinstall "$BYEDPI_FILE" >/dev/null 2>&1

    rm -rf "$WORKDIR"
    /etc/init.d/byedpi enable >/dev/null 2>&1
    /etc/init.d/byedpi start >/dev/null 2>&1

    echo -e "ByeDPI успешно установлен!\n"
    read -p "Нажмите Enter..." dummy
# Ставим туннель
opkg install hev-socks5-tunnel

# Настройка ByeDPI
cat > /etc/config/byedpi << 'EOF'
config byedpi 'main'
	option enabled '1'
	option cmd_opts '-E -s12+s -d18+s -r6+s -a4 -An'
EOF

# Настройка hev-socks5-tunnel
cat > /etc/config/hev-socks5-tunnel << 'EOF'
config socks5 'main'
	option port '1080'
	option address '127.0.0.1'
	option udp 'udp'
	option enabled '1'
EOF

# Включаем автозапуск
/etc/init.d/byedpi enable
/etc/init.d/byedpi start
/etc/init.d/hev-socks5-tunnel enable
/etc/init.d/hev-socks5-tunnel start
