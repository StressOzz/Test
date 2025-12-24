#!/bin/sh

GREEN="\e[32m"
RED="\e[31m"
YELLOW="\e[33m"
CYAN="\e[36m"
NC="\e[0m"

ROUTER_IP="$(uci get network.lan.ipaddr 2>/dev/null)"
[ -z "$ROUTER_IP" ] && ROUTER_IP="192.168.1.1"

DOMAINS="example.com google.com openwrt.org cloudflare.com dns.google"
LEAK_DOMAINS="whoami.cloudflare dnsleaktest.com"

echo "======================================="
echo " DNS / DNS Hijack — расширенная проверка"
echo "======================================="
echo

check() {
    SERVER="$1"
    DOMAIN="$2"
    MODE="$3"
    RES=$(dig @"$SERVER" "$DOMAIN" $MODE +time=2 +tries=1 +short)
    if [ -n "$RES" ]; then
        echo -e "  ${CYAN}${DOMAIN}${NC} → ${GREEN}OK${NC} (${RES})"
    else
        echo -e "  ${CYAN}${DOMAIN}${NC} → ${RED}FAIL${NC}"
    fi
}

# -----------------------------
echo "1) Локальный DNS (127.0.0.1) UDP:"
for d in $DOMAINS; do check 127.0.0.1 "$d" ""; done
echo

echo "2) Локальный DNS (127.0.0.1) TCP:"
for d in $DOMAINS; do check 127.0.0.1 "$d" "+tcp"; done
echo

# -----------------------------
echo "3) DNS через LAN IP роутера (${ROUTER_IP}):"
for d in $DOMAINS; do check "$ROUTER_IP" "$d" ""; done
echo

# -----------------------------
echo "4) Прямой внешний DNS (8.8.8.8) — контроль:"
for d in $DOMAINS; do check 8.8.8.8 "$d" ""; done
echo

# -----------------------------
echo "5) Попытка DNS LEAK (через локальный DNS):"
for d in $LEAK_DOMAINS; do check 127.0.0.1 "$d" ""; done
echo

# -----------------------------
echo "6) Проверка перехвата TCP/53 (Hijack):"
check 8.8.8.8 example.com "+tcp"
echo

# -----------------------------
echo "7) Тайминги (latency сравнение):"
for s in 127.0.0.1 8.8.8.8; do
    T=$(dig @"$s" example.com +stats 2>/dev/null | grep "Query time" | awk '{print $4}')
    echo -e "  ${CYAN}${s}${NC} → ${YELLOW}${T} ms${NC}"
done
echo

# -----------------------------
echo "8) Проверка доступности DoT (853 порт):"
timeout 2 nc -z 1.1.1.1 853 2>/dev/null && \
    echo -e "  1.1.1.1:853 → ${YELLOW}доступен${NC}" || \
    echo -e "  1.1.1.1:853 → ${GREEN}блокируется (OK)${NC}"
echo

echo "======================================="
echo " Диагностика завершена"
echo "======================================="
