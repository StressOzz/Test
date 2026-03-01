#!/bin/sh
set -eu

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"
API="https://api.web2core.workers.dev/api"

[ -r "$IN" ] || { echo "Can't read $IN" >&2; exit 1; }
[ -r /usr/share/libubox/jshn.sh ] || { echo "Missing jshn.sh (libubox). Install package providing it." >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Missing curl" >&2; exit 1; }

. /usr/share/libubox/jshn.sh

INPUT="$(cat "$IN")"
TMP="$(mktemp)"
REQ="$(mktemp)"

json_init
json_add_string core "mihomo"
json_add_string input "$INPUT"
json_add_object options
json_add_boolean webUI 1
json_add_boolean addTun 0
json_close_object
json_dump > "$REQ"

# Worker: POST / or /api, JSON request; mihomo response is text/yaml [web:49]
curl -fsS -X POST "$API" \
  -H "Content-Type: application/json" \
  --data-binary @"$REQ" > "$TMP" || {
    echo "API request failed" >&2
    rm -f "$TMP" "$REQ"
    exit 2
  }

# Если API вернул JSON-ошибку вида {"error":"..."} — это не YAML [web:49]
if head -c 1 "$TMP" | grep -q '{'; then
  echo "API returned JSON (likely error):" >&2
  cat "$TMP" >&2
  rm -f "$TMP" "$REQ"
  exit 3
fi

chmod 600 "$TMP"
mkdir -p "$(dirname "$OUT")"
mv -f "$TMP" "$OUT"
rm -f "$REQ"
echo "Written: $OUT"
