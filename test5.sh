#!/bin/sh
set -e  # без -u из-за jshn.sh [web:81]

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"
API="https://api.web2core.workers.dev/api"

[ -r "$IN" ] || { echo "Can't read $IN" >&2; exit 1; }
[ -r /usr/share/libubox/jshn.sh ] || { echo "Missing /usr/share/libubox/jshn.sh" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "Missing curl" >&2; exit 1; }

JSON_PREFIX="W2C_"
. /usr/share/libubox/jshn.sh

INPUT="$(cat "$IN")"
TMP="$(mktemp)"
REQ="$(mktemp)"

# jshn-часть
set +u
json_init
json_add_string core "mihomo"
json_add_string input "$INPUT"
json_add_object options
json_add_boolean webUI 1
json_add_boolean addTun 0
json_close_object
json_dump > "$REQ"
json_cleanup
set -u 2>/dev/null || true

curl -fsS -X POST "$API" \
  -H "Content-Type: application/json" \
  --data-binary @"$REQ" > "$TMP"

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
