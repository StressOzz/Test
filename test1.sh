#!/bin/sh

DOMAIN_MAIN="youtube.com"
DOMAIN_VIDEO="rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"

DNS_LIST="1.1.1.1 8.8.8.8 77.88.8.8"

echo "=== Проверка DNS (YouTube, IPv4 only) ==="
echo

get_ip4() {
    nslookup -type=A "$1" $2 2>/dev/null | awk '/^Address: /{print $2}' | grep -E '^[0-9.]+' | tail -n1
}

check_domain() {
    DOMAIN="$1"

    echo "Домен: $DOMAIN"

    SYS_IP=$(get_ip4 "$DOMAIN")
    echo "  Системный DNS : ${SYS_IP:-НЕ РЕЗОЛВИТ}"

    MATCH=0
    TOTAL=0

    for DNS in $DNS_LIST; do
        IP=$(get_ip4 "$DOMAIN" "$DNS")
        [ -z "$IP" ] && continue

        echo "  $DNS : $IP"

        TOTAL=$((TOTAL+1))

        [ "$SYS_IP" = "$IP" ] && MATCH=$((MATCH+1))
    done

    if [ -z "$SYS_IP" ]; then
        RESULT="БЛОКИРОВКА"
    elif [ $MATCH -eq 0 ]; then
        RESULT="ПОДМЕНА"
    elif [ $MATCH -lt $TOTAL ]; then
        RESULT="ПОДОЗРЕНИЕ"
    else
        RESULT="OK"
    fi

    echo "  Итог: $RESULT"
    echo
}

check_domain "$DOMAIN_MAIN"
check_domain "$DOMAIN_VIDEO"

echo "=== Проверка перехвата DNS (UDP 53) ==="
echo

tcpdump -ni any udp port 53 -c 5 2>/dev/null | grep -E '1\.1\.1\.1|8\.8\.8\.8|77\.88\.8\.8' >/dev/null

if [ $? -eq 0 ]; then
    echo "DNS запросы уходят на внешние сервера"
else
    echo "ВНИМАНИЕ: возможен перехват DNS или блокировка"
fi
