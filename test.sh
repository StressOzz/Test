URL="https://raw.githubusercontent.com/ImMALWARE/dns.malw.link/refs/heads/master/hosts"
LOCAL_FILE="/etc/dnsmasq.hosts"
TMP_FILE="/tmp/dnsmasq.hosts.new"
TMP_FILTERED="/tmp/dnsmasq.hosts.filtered"
LOG="/tmp/dnsmasq_update.log"

echo "$(date -Iseconds) - starting update" >> "$LOG"

# --- download ---
if command -v wget >/dev/null 2>&1; then
    wget -q -O "$TMP_FILE" "$URL"
    rc=$?
elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$TMP_FILE" "$URL"
    rc=$?
else
    echo "$(date -Iseconds) - ERROR: neither wget nor curl available" >> "$LOG"
    exit 2
fi

if [ "$rc" -ne 0 ] || [ ! -s "$TMP_FILE" ]; then
    echo "$(date -Iseconds) - ERROR: download failed (rc=$rc)" >> "$LOG"
    rm -f "$TMP_FILE"
    exit 3
fi

# CRLF cleanup
if command -v dos2unix >/dev/null 2>&1; then
    dos2unix "$TMP_FILE" >/dev/null 2>&1 || true
fi

# --- filtering ---
awk '
BEGIN {
    IGNORECASE = 1
    pattern = "api[.]github|git|github|4pda"
}
{
    if ($0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) {
        print
        next
    }
    if (NF < 2) { print; next }

    dom = ""
    for (i = 2; i <= NF; i++) {
        dom = dom (i==2 ? "" : " ") $i
    }

    if (dom ~ pattern) {
        next
    }
    print
}
' "$TMP_FILE" > "$TMP_FILTERED" || {
    echo "$(date -Iseconds) - ERROR: filtering failed" >> "$LOG"
    rm -f "$TMP_FILE" "$TMP_FILTERED"
    exit 4
}

orig_lines=$(wc -l < "$TMP_FILE" 2>/dev/null || echo 0)
filtered_lines=$(wc -l < "$TMP_FILTERED" 2>/dev/null || echo 0)
removed=$((orig_lines - filtered_lines))
echo "$(date -Iseconds) - filtered $removed lines" >> "$LOG"

# install or compare
if [ ! -f "$LOCAL_FILE" ]; then
    mv "$TMP_FILTERED" "$LOCAL_FILE"
    chmod 644 "$LOCAL_FILE"
    echo "$(date -Iseconds) - installed new $LOCAL_FILE" >> "$LOG"
    /etc/init.d/dnsmasq restart && echo "$(date -Iseconds) - dnsmasq restarted" >> "$LOG"
    rm -f "$TMP_FILE"
    exit 0
fi

if cmp -s "$TMP_FILTERED" "$LOCAL_FILE"; then
    echo "$(date -Iseconds) - no changes" >> "$LOG"
    rm -f "$TMP_FILE" "$TMP_FILTERED"
    exit 0
fi

mv "$TMP_FILTERED" "$LOCAL_FILE"
chmod 644 "$LOCAL_FILE"
echo "$(date -Iseconds) - updated $LOCAL_FILE" >> "$LOG"
 /etc/init.d/dnsmasq restart && echo "$(date -Iseconds) - dnsmasq restarted" >> "$LOG"
rm -f "$TMP_FILE"
exit 0
