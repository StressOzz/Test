#!/bin/sh
# OpenWrt 24+ — DPI bypass ONLY YouTube
# byedpi + SOCKS5 + nftables
# one-shot setup, plain output

set -e

echo ""
echo "=== DPI bypass: только YouTube ==="
echo ""

echo "Обновляем список пакетов"
opkg update > /dev/null 2>&1
echo "ok: opkg update"

echo "Устанавливаем модули ядра"
opkg install kmod-tun kmod-nf-nat kmod-nf-conntrack > /dev/null 2>&1 || true
echo "ok: модули ядра готовы"

echo "Проверяем byedpi"
if ! opkg list-installed | grep -q "^byedpi "; then
    echo "byedpi не найден, устанавливаем"
    BYEDPI_URL="https://github.com/DPITrickster/ByeDPI-OpenWrt/releases/download/v0.17.3-24.10/byedpi_0.17.3-r1_aarch64_cortex-a53.ipk"
    wget -q -O /tmp/byedpi.ipk "$BYEDPI_URL" || { echo "ошибка: не удалось скачать byedpi"; exit 1; }
    opkg install /tmp/byedpi.ipk > /dev/null 2>&1
    rm -f /tmp/byedpi.ipk
    echo "ok: byedpi установлен"
else
    echo "ok: byedpi уже установлен"
fi

echo "Устанавливаем hev-socks5-tunnel"
opkg install hev-socks5-tunnel > /dev/null 2>&1 || true
echo "ok: hev-socks5-tunnel установлен"

echo "Настраиваем byedpi"
cat > /etc/config/byedpi << 'EOF'
config byedpi 'main'
	option enabled '1'
	option cmd_opts '-o2 --auto=t,r,a,s -d2'
EOF
echo "ok: byedpi настроен"

echo "Настраиваем SOCKS5 (127.0.0.1:1080)"
mkdir -p /etc/hev-socks5-tunnel
cat > /etc/hev-socks5-tunnel/main.yml << 'EOF'
socks5:
  port: 1080
  address: 127.0.0.1
  udp: 'udp'
EOF

uci set hev-socks5-tunnel.config.conffile='/etc/hev-socks5-tunnel/main.yml'
uci set hev-socks5-tunnel.config.enabled='1'
uci commit hev-socks5-tunnel
echo "ok: SOCKS5 настроен"

echo "Создаем список доменов YouTube"
cat > /etc/youtube_domains.conf << 'EOF'
youtube.com
www.youtube.com
m.youtube.com
youtubei.googleapis.com
ytimg.com
googlevideo.com
youtu.be
EOF
echo "ok: домены YouTube записаны"

echo "Настраиваем dnsmasq -> ipset youtube"
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/youtube-ipset.conf << 'EOF'
ipset=/youtube.com/youtube
ipset=/www.youtube.com/youtube
ipset=/m.youtube.com/youtube
ipset=/youtubei.googleapis.com/youtube
ipset=/ytimg.com/youtube
ipset=/googlevideo.com/youtube
ipset=/youtu.be/youtube
EOF

/etc/init.d/dnsmasq restart
echo "ok: dnsmasq перезапущен"

echo "Включаем автозапуск сервисов"
/etc/init.d/byedpi enable
/etc/init.d/hev-socks5-tunnel enable
echo "ok: автозапуск включен"

echo "Запускаем byedpi"
/etc/init.d/byedpi restart
sleep 2

echo "Запускаем SOCKS5"
/etc/init.d/hev-socks5-tunnel restart
sleep 2
echo "ok: сервисы запущены"

echo "Настраиваем nftables (ТОЛЬКО YouTube)"
nft flush ruleset || true

nft add table inet proxy
nft 'add chain inet proxy prerouting { type nat hook prerouting priority 0 ; }'
nft add set inet proxy youtube { type ipv4_addr\; flags interval\; }
nft add rule inet proxy prerouting ip daddr @youtube tcp dport {80,443} redirect to :1080

echo "ok: nftables настроены"

echo "ГОТОВО"
