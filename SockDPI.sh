#!/bin/sh

# Архитектура
Arch="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"

cd /tmp
opkg update
# Скачиваем и ставим ByeDPI
wget https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/byedpi_0.17.3-r1_${Arch}.ipk
opkg install byedpi_0.17.3-r1_${Arch}.ipk

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
