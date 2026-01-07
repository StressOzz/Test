#!/bin/sh

DOMAINS="
cloudflare-dns.com
dns.google
dns.comss.one
xbox-dns.ru
dns.malw.link
5u35p8m9i7.cloudflare-gateway.com
dns.mafioznik.xyz
dns.astracat.ru
"

TIMEOUT=1

for d in $DOMAINS; do

    # 1. Есть ли маршрут (мгновенно)
    if ! ip route get "$d" >/dev/null 2>&1; then
        printf "%-25s NO ROUTE\n" "$d"
        continue
    fi

    # 2. Быстрый TCP check (443)
    START=$(date +%s%N)
    if nc -z -w$TIMEOUT "$d" 443 >/dev/null 2>&1; then
        END=$(date +%s%N)
        MS=$(( (END - START) / 1000000 ))
        printf "%-25s TCP OK     %sms\n" "$d" "$MS"
        continue
    fi

    # 3. Только если надо — HTTPS
    CURL_TIME=$(curl -o /dev/null -s -w '%{time_total}' --connect-timeout $TIMEOUT "https://$d" 2>/dev/null)
    CURL_MS=$(awk "BEGIN { printf \"%d\", $CURL_TIME * 1000 }")

    if [ "$CURL_MS" -gt 0 ]; then
        printf "%-25s NO PING → HTTPS OK %sms\n" "$d" "$CURL_MS"
    else
        printf "%-25s DEAD\n" "$d"
    fi

done
