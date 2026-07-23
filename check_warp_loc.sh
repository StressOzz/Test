#!/bin/sh

IPV4_PREFIXES="188.114.96. 188.114.97. 188.114.98. 188.114.99. 162.159.192. 162.159.193. 162.159.195. 8.34.146. 8.39.214. 8.39.204. 8.6.112. 8.35.211. 8.39.125. 8.47.69."

get_city_name() {
    case "$1" in
        FRA) echo "Frankfurt (DE)" ;;
        DME|MOW|SVO|VKO|ZIA) echo "Moscow (RU)" ;;
        LED) echo "Saint-Petersburg (RU)" ;;
        KUF) echo "Samara (RU)" ;;
        SVX) echo "Yekaterinburg (RU)" ;;
        OVB) echo "Novosibirsk (RU)" ;;
        HEL) echo "Helsinki (FI)" ;;
        WAW) echo "Warsaw (PL)" ;;
        AMS) echo "Amsterdam (NL)" ;;
        PRG) echo "Prague (CZ)" ;;
        VIE) echo "Vienna (AT)" ;;
        BUD) echo "Budapest (HU)" ;;
        IST) echo "Istanbul (TR)" ;;
        ARN) echo "Stockholm (SE)" ;;
        TLL) echo "Tallinn (EE)" ;;
        RIX) echo "Riga (LV)" ;;
        VNO) echo "Vilnius (LT)" ;;
        *) echo "$1" ;;
    esac
}

generate_ips() {
    count=$1
    awk -v prefixes="$IPV4_PREFIXES" -v count="$count" 'BEGIN {
        srand();
        n = split(prefixes, arr, " ");
        for (i=0; i<count; i++) {
            idx = int(rand() * n) + 1;
            last = int(rand() * 256);
            print arr[idx] last;
        }
    }'
}

check_endpoint() {
    ip="$1"
    
    if command -v curl >/dev/null 2>&1; then
        trace_data=$(curl -s --connect-timeout 2 -H "Host: trace.cloudflare.com" "http://${ip}/cdn-cgi/trace")
    else
        trace_data=$(wget -q -O - --timeout=2 --header="Host: trace.cloudflare.com" "http://${ip}/cdn-cgi/trace")
    fi

    if [ -z "$trace_data" ]; then
        echo "IP: $ip -> [TIMEOUT / BLOCKED]"
        return 1
    fi

    colo=$(echo "$trace_data" | awk -F'=' '$1=="colo"{print $2}')
    loc=$(echo "$trace_data" | awk -F'=' '$1=="loc"{print $2}')

    if [ -n "$colo" ]; then
        city=$(get_city_name "$colo")
        echo "IP: $ip -> $colo ($city) [Country: ${loc:-N/A}]"
    else
        echo "IP: $ip -> [TRACE ERROR]"
    fi
}

COUNT=${1:-50}
echo "Generating $COUNT random IPv4 endpoints and testing in parallel..."
echo "---------------------------------------------------"

for ip in $(generate_ips "$COUNT"); do
    check_endpoint "$ip" &
done

wait
echo "---------------------------------------------------"
echo "Done."
