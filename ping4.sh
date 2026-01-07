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
    START=$(date +%s%N)

    OUT=$(ping -c 1 -W $TIMEOUT "$d" 2>/dev/null)

    END=$(date +%s%N)
    TOTAL_MS=$(( (END - START) / 1000000 ))

    PING_MS=$(echo "$OUT" | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)

    if [ -n "$PING_MS" ]; then
        printf "%-25s PING OK    %sms (total %sms)\n" "$d" "$PING_MS" "$TOTAL_MS"
    else
        printf "%-25s NO PING    timeout %sms\n" "$d" "$TOTAL_MS"
    fi
done
