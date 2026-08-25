#!/bin/sh
# lib/hev_tunnel.sh — установка hev-socks5-tunnel (TUN-интерфейс для Mihomo)

install_hev_tunnel() {
    log_online "Установка hev-socks5-tunnel"

    if [ "$USE_APK" -eq 1 ]; then
        apk cache clean
        apk add hev-socks5-tunnel >/dev/null 2>&1
    else
        manage_pkg install hev-socks5-tunnel >/dev/null 2>&1
    fi

    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml <<'EOF'
tunnel:
  name: Mihomo
  mtu: 8500
  multi-queue: false
  ipv4: 198.18.0.1
socks5:
  port: 7890
  address: 127.0.0.1
  udp: 'udp'
EOF
    chmod 600 /etc/hev-socks5-tunnel/main.yml

    _reset_uci_section
    _setup_hev_service
    _setup_network_iface
    _setup_firewall_zone
}

_reset_uci_section() {
    echo "Очистка старых настроек UCI"
    uci delete network.Mihomo 2>/dev/null || true

    for fw_section in $(uci show firewall 2>/dev/null | grep -E "\.name='Mihomo'" | sed "s/\.name.*//"); do
        uci delete "$fw_section" 2>/dev/null || true
    done
    for fw_section in $(uci show firewall 2>/dev/null | grep -E "\.(src|dest)='Mihomo'" | sed -E "s/\.(src|dest).*//"); do
        uci delete "$fw_section" 2>/dev/null || true
    done
    uci delete firewall.Mihomo 2>/dev/null || true
    uci delete firewall.lan_to_Mihomo 2>/dev/null || true
    uci commit firewall
    /etc/init.d/firewall restart 2>/dev/null || true
    sleep 1
}

_setup_hev_service() {
    echo "Настройка UCI-сервиса hev-socks5-tunnel"
    uci -q get hev-socks5-tunnel.@instance[0] >/dev/null 2>&1 || uci add hev-socks5-tunnel instance >/dev/null
    uci set hev-socks5-tunnel.@instance[0].enabled='1'
    uci set hev-socks5-tunnel.@instance[0].conffile='/etc/hev-socks5-tunnel/main.yml'
    uci commit hev-socks5-tunnel
    /etc/init.d/hev-socks5-tunnel restart
    sleep 2
}

_setup_network_iface() {
    echo "Настройка сетевого интерфейса"
    uci set network.Mihomo=interface
    uci set network.Mihomo.proto='none'
    uci set network.Mihomo.device='Mihomo'
    uci commit network
    /etc/init.d/network reload
}

_setup_firewall_zone() {
    echo "Настройка firewall"
    fw_zone=$(uci add firewall zone)
    uci set "firewall.${fw_zone}.name=Mihomo"
    uci set "firewall.${fw_zone}.input=REJECT"
    uci set "firewall.${fw_zone}.output=REJECT"
    uci set "firewall.${fw_zone}.forward=REJECT"
    uci set "firewall.${fw_zone}.masq=1"
    uci set "firewall.${fw_zone}.mtu_fix=1"
    uci add_list "firewall.${fw_zone}.network=Mihomo"

    fw_fwd=$(uci add firewall forwarding)
    uci set "firewall.${fw_fwd}.src=lan"
    uci set "firewall.${fw_fwd}.dest=Mihomo"

    uci commit firewall
    /etc/init.d/firewall restart
}
