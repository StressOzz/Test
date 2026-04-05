#!/bin/sh

DOMAINS="
rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com
rr1---sn-gvnuxaxjvh-jx3l.googlevideo.com
rr1---sn-gvnuxaxjvh-jx3s.googlevideo.com
"

DNS_LIST="
1.1.1.1
8.8.8.8
77.88.8.8
83.220.169.155
84.21.189.133
45.155.204.190
111.88.96.50
"

DOH="127.0.0.1#5053"

get_ip4() {
    nslookup -type=A "$1" $2 2>/dev/null | awk '/^Address: /{print $2}' | grep -E '^[0-9.]+' | tail -n1
}

echo "=== Проверка googlevideo (YouTube) ==="
echo

FINAL_DNS_OK=1
FINAL_DPI_OK=1

for DOMAIN in $DOMAINS; do
    echo "Домен: $DOMAIN"

    SYS_IP=$(get_ip4 "$DOMAIN")
    DOH_IP=$(get_ip4 "$DOMAIN" "$DOH")

    echo "  Системный DNS : ${SYS_IP:-НЕТ}"
    [ -n "$DOH_IP" ] && echo "  DoH           : $DOH_IP"

    MATCH=0
    TOTAL=0

    for DNS in $DNS_LIST; do
        IP=$(get_ip4 "$DOMAIN" "$DNS")
        [ -z "$IP" ] && continue

        echo "  $DNS : $IP"

        TOTAL=$((TOTAL+1))
        [ "$SYS_IP" = "$IP" ] && MATCH=$((MATCH+1))
    done

    # --- DNS анализ ---
    if [ -z "$SYS_IP" ]; then
        DNS_RESULT="БЛОК DNS"
        FINAL_DNS_OK=0
    elif [ -n "$DOH_IP" ] && [ "$SYS_IP" != "$DOH_IP" ]; then
        DNS_RESULT="ПОДМЕНА DNS"
        FINAL_DNS_OK=0
    elif [ $MATCH -eq $TOTAL ]; then
        DNS_RESULT="OK"
    else
        DNS_RESULT="РАЗНЫЕ CDN (норма)"
    fi

    echo "  DNS итог: $DNS_RESULT"

    # --- DPI проверка ---
    if [ -n "$SYS_IP" ]; then
        curl -m 5 -I --resolve "$DOMAIN:443:$SYS_IP" "https://$DOMAIN" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            DPI_RESULT="OK"
        else
            DPI_RESULT="DPI/БЛОК"
            FINAL_DPI_OK=0
        fi
    else
        DPI_RESULT="SKIP"
        FINAL_DPI_OK=0
    fi

    echo "  Доступ: $DPI_RESULT"
    echo
done

echo "=== ИТОГ ==="

if [ $FINAL_DNS_OK -eq 1 ] && [ $FINAL_DPI_OK -eq 1 ]; then
    echo "✔ Всё чисто (DNS и доступ без проблем)"
elif [ $FINAL_DNS_OK -eq 0 ]; then
    echo "✖ Есть проблемы с DNS"
elif [ $FINAL_DPI_OK -eq 0 ]; then
    echo "✖ Есть проблемы с DPI (режут трафик)"
else
    echo "⚠ Неоднозначный результат"
fi
