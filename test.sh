#!/bin/sh

DOMAIN_MAIN="youtube.com"
DOMAIN_VIDEO="rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"

DNS_CF="1.1.1.1"
DOH="127.0.0.1#5053"

echo "=== Проверка DNS (YouTube) ==="
echo

get_ip() {
    nslookup "$1" $2 2>/dev/null | awk '/^Address: /{print $2}' | tail -n1
}

check_domain() {
    DOMAIN="$1"

    echo "Домен: $DOMAIN"

    SYS_IP=$(get_ip "$DOMAIN")
    CF_IP=$(get_ip "$DOMAIN" "$DNS_CF")
    DOH_IP=$(get_ip "$DOMAIN" "$DOH")

    echo "  Системный DNS : ${SYS_IP:-НЕ РЕЗОЛВИТ}"
    echo "  Cloudflare    : ${CF_IP:-НЕ РЕЗОЛВИТ}"
    [ -n "$DOH_IP" ] && echo "  DoH (локальный): $DOH_IP"

    RESULT="OK"

    if [ -n "$CF_IP" ] && [ "$SYS_IP" != "$CF_IP" ]; then
        RESULT="ПОДОЗРЕНИЕ"
    fi

    if [ -n "$DOH_IP" ] && [ "$SYS_IP" != "$DOH_IP" ]; then
        RESULT="ПОДМЕНА"
    fi

    if [ -z "$SYS_IP" ] && [ -n "$CF_IP" ]; then
        RESULT="БЛОКИРОВКА"
    fi

    echo "  Итог: $RESULT"
    echo
}

check_domain "$DOMAIN_MAIN"
check_domain "$DOMAIN_VIDEO"

echo "=== Проверка перехвата DNS ==="
echo

tcpdump -ni any port 53 -c 5 2>/dev/null | grep -q "$DNS_CF"

if [ $? -eq 0 ]; then
    echo "Запросы к $DNS_CF проходят напрямую"
else
    echo "ВНИМАНИЕ: возможен перехват DNS (запросы не видны к $DNS_CF)"
fi
