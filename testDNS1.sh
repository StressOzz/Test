#!/bin/sh

GREEN="\e[32m"; RED="\e[31m"; YELLOW="\e[33m"; NC="\e[0m"

ROUTER_IP="$(uci get network.lan.ipaddr 2>/dev/null)"
[ -z "$ROUTER_IP" ] && ROUTER_IP="192.168.1.1"

DOMAIN="example.com"

ok()   { echo -e "${GREEN}OK${NC}"; }
fail() { echo -e "${RED}FAIL${NC}"; }

echo "DNS TEST RESULT"
echo "----------------"

echo -n "1) Local DNS 127.0.0.1 UDP: "
dig @127.0.0.1 $DOMAIN +time=2 +tries=1 +short >/dev/null && ok || fail

echo -n "2) Local DNS 127.0.0.1 TCP: "
dig @127.0.0.1 $DOMAIN +tcp +time=2 +tries=1 +short >/dev/null && ok || fail

echo -n "3) DNS via router LAN IP ($ROUTER_IP): "
dig @$ROUTER_IP $DOMAIN +time=2 +tries=1 +short >/dev/null && ok || fail

echo -n "4) External DNS UDP 8.8.8.8: "
dig @8.8.8.8 $DOMAIN +time=2 +tries=1 +short >/dev/null && ok || fail

echo -n "5) External DNS TCP 8.8.8.8 (Hijack test): "
dig @8.8.8.8 $DOMAIN +tcp +time=2 +tries=1 +short >/dev/null && ok || fail

echo
echo "SUMMARY"
echo "-------"

if dig @8.8.8.8 $DOMAIN +tcp +short >/dev/null 2>&1; then
    echo -e "DNS Hijack: ${YELLOW}НЕ ПЕРЕХВАТЫВАЕТ TCP/53${NC}"
else
    echo -e "DNS Hijack: ${GREEN}РАБОТАЕТ (TCP/53 перехвачен)${NC}"
fi

if dig @127.0.0.1 $DOMAIN +short >/dev/null 2>&1; then
    echo -e "Local DNS: ${GREEN}РАБОТАЕТ${NC}"
else
    echo -e "Local DNS: ${RED}НЕ РАБОТАЕТ${NC}"
fi
