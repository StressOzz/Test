#!/bin/sh

DOMAIN="rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"

DNS_LIST="1.1.1.1 8.8.8.8 77.88.8.8"
DOH="127.0.0.1#5053"

echo "=== Проверка googlevideo (YouTube) ==="
echo

get_ip4() {
    nslookup -type=A "$1" $2 2>/dev/null | awk '/^Address: /{print $2}' | grep -E '^[0-9.]+' | tail -n1
}

echo "Домен: $DOMAIN"
echo

SYS_IP=$(get_ip4 "$DOMAIN")
DOH_IP=$(get_ip4 "$DOMAIN" "$DOH")

echo "Системный DNS : ${SYS_IP:-НЕ РЕЗОЛВИТ}"
[ -n "$DOH_IP" ] && echo "DoH           : $DOH_IP"

echo

MATCH=0
TOTAL=0

for DNS in $DNS_LIST; do
    IP=$(get_ip4 "$DOMAIN" "$DNS")
    [ -z "$IP" ] && continue

    echo "$DNS : $IP"

    TOTAL=$((TOTAL+1))
    [ "$SYS_IP" = "$IP" ] && MATCH=$((MATCH+1))
done

echo

# --- DNS вывод ---
if [ -z "$SYS_IP" ]; then
    DNS_RESULT="БЛОКИРОВКА DNS"
elif [ -n "$DOH_IP" ] && [ "$SYS_IP" != "$DOH_IP" ]; then
    DNS_RESULT="ПОДМЕНА DNS"
elif [ $MATCH -eq $TOTAL ]; then
    DNS_RESULT="DNS OK"
else
    DNS_RESULT="СОМНИТЕЛЬНО"
fi

echo "=== Результат DNS: $DNS_RESULT ==="
echo

# --- Проверка DPI ---
echo "=== Проверка доступа (curl) ==="

if [ -n "$SYS_IP" ]; then
    curl -m 5 -I --resolve "$DOMAIN:443:$SYS_IP" "https://$DOMAIN" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        echo "Доступ к серверу есть (DPI нет)"
        DPI_RESULT="OK"
    else
        echo "Нет доступа по HTTPS (возможен DPI)"
        DPI_RESULT="DPI/БЛОК"
    fi
else
    echo "Пропуск проверки (нет IP)"
    DPI_RESULT="UNKNOWN"
fi

echo
echo "=== ИТОГ ==="

if [ "$DNS_RESULT" = "DNS OK" ] && [ "$DPI_RESULT" = "OK" ]; then
    echo "Проблем нет"
elif [ "$DNS_RESULT" != "DNS OK" ]; then
    echo "Проблема с DNS"
else
    echo "Проблема с DPI (трафик режется)"
fi
