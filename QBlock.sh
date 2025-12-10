#!/bin/sh
echo -e "\033[1;32mAdd block QUIC\033[0m"

# Block_UDP_80
if ! uci show firewall | grep -q "name='Block_UDP_80'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Block_UDP_80'
    uci add_list firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='80'
    uci set firewall.@rule[-1].target='REJECT'
fi

# Block_UDP_443
if ! uci show firewall | grep -q "name='Block_UDP_443'"; then
    uci add firewall rule
    uci set firewall.@rule[-1].name='Block_UDP_443'
    uci add_list firewall.@rule[-1].proto='udp'
    uci set firewall.@rule[-1].src='lan'
    uci set firewall.@rule[-1].dest='wan'
    uci set firewall.@rule[-1].dest_port='443'
    uci set firewall.@rule[-1].target='REJECT'
fi

uci commit firewall
