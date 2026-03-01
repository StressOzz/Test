#!/bin/sh
set -eu

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"
API="https://api.web2core.workers.dev/api"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need curl
need mktemp

[ -r "$IN" ] || { echo "Can't read $IN" >&2; exit 1; }

INPUT="$(cat "$IN")"
TMP="$(mktemp)"

# Важно: если API НЕ поддерживает wg-quick ini как "profile", вернет {"error": "..."} [web:49]
curl -fsS -X POST "$API" \
  -H "Content-Type: application/json" \
  --data-binary "$(printf '{"core":"mihomo","input":%s,"options":{"webUI":true,"addTun":false}}' \
    "$(python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))' <<EOF
$INPUT
EOF
)")" > "$TMP"

# Простейшая проверка на JSON-ошибку от API [web:49]
if head -c 1 "$TMP" | grep -q '{'; then
  echo "API returned JSON (likely error). Output:" >&2
  cat "$TMP" >&2
  rm -f "$TMP"
  exit 2
fi

chmod 600 "$TMP"
mv -f "$TMP" "$OUT"
echo "Written: $OUT"
