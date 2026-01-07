#!/bin/sh

DOMAINS="
xbox-dns.ru
google.com
youtube.com
example.org
"

TIMEOUT=1

for d in $DOMAINS; do
    echo "$d" | grep -q '^#' && continue

    PING_TIME=$(ping -c 1 -W $TIMEOUT "$d" 2>/dev/null | awk -F'time=' '/time=/{print $2}' | cut -d' ' -f1)

    if [ -n "$PING_TIME" ]; then
        printf "%-25s PING OK    %sms\n" "$d" "$PING_TIME"
        continue
    fi

    CURL_TIME=$(curl -o /dev/null -s -w '%{time_total}' --connect-timeout $TIMEOUT "https://$d" 2>/dev/null)
    CURL_MS=$(awk "BEGIN { printf \"%d\", $CURL_TIME * 1000 }")

    if [ "$CURL_MS" -gt 0 ]; then
        printf "%-25s NO PING → HTTPS OK %sms\n" "$d" "$CURL_MS"
    else
        printf "%-25s DEAD\n" "$d"
    fi
done
