#!/bin/sh
# ==========================================
# zapret blockcheck (авто) for OpenWRT 24+
# by StressOzz edition
# ==========================================

TMPDIR="/tmp/blockcheck"
OUTFILE="/tmp/blockcheck_result.txt"
SITES="youtube.com rutracker.org cloudflare.com gosuslugi.ru"
PORTS="80 443"
METHODS="fake fakedsplit split disorder multidisorder"
LOGFILE="$TMPDIR/log.txt"

mkdir -p "$TMPDIR"
echo "=== zapret blockcheck auto mode ===" > "$OUTFILE"
echo "Start time: $(date)" >> "$OUTFILE"
echo >> "$OUTFILE"

check_site() {
    local site="$1" port="$2" method="$3"
    echo -n "[$(date +%H:%M:%S)] $site:$port ($method) ... " >> "$OUTFILE"
    nfqws --dpi-desync="$method" --filter-tcp="$port" --hostlist "$site" \
        --qnum=100 --daemon >/dev/null 2>&1
    sleep 2
    if wget -T3 -q -O /dev/null "http://$site" 2>/dev/null || \
       wget -T3 -q -O /dev/null "https://$site" 2>/dev/null; then
        echo "OK" >> "$OUTFILE"
        echo "$site:$port → $method" >> "$LOGFILE"
    else
        echo "FAIL" >> "$OUTFILE"
    fi
    killall nfqws >/dev/null 2>&1
    sleep 1
}

for site in $SITES; do
  for port in $PORTS; do
    for method in $METHODS; do
      check_site "$site" "$port" "$method"
    done
  done
done

echo >> "$OUTFILE"
echo "=== Best results ===" >> "$OUTFILE"
sort "$LOGFILE" | uniq >> "$OUTFILE"
echo "Done! Results saved to $OUTFILE"
