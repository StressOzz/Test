#!/bin/sh
U="${1:-https://sub.skytunnel.pw/1077208916_StressKVN_bot_NFsey}"
T=/tmp/zm-hdrcheck
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT INT TERM
command -v jq >/dev/null 2>&1 || { echo "Нет jq: apk add jq (или opkg install jq)"; exit 1; }

cat > "$T/red.jq" <<'EOF'
def red:
  walk(if type == "object" then
         with_entries(if (.key | ascii_downcase) as $k
                         | ["id", "uuid", "password", "auth", "publickey", "privatekey", "shortid", "spiderx", "pass", "user", "username", "seed", "obfspassword", "mldsa65verify", "encryption", "decryption"] | index($k)
                      then .value = (if (.value | type) == "string" and (.value | length) > 0 and .value != "none" then "***" else .value end)
                      else . end)
       else . end);
EOF

echo "=== Скачиваем подписку в формате Happ"
curl -fsSL --compressed -m 25 -A 'Happ/4.5.4/Windows/2610141139602' -o "$T/xr.json" "$U"; echo "rc=$?"
jq -e . "$T/xr.json" >/dev/null 2>&1 || { echo "Ответ не JSON: $(head -c 60 "$T/xr.json" | tr -cd 'A-Za-z0-9:/+=._ -')"; exit 1; }
echo "Всего конфигов: $(jq 'if type == "array" then length else 1 end' "$T/xr.json")"
echo "Ключи верхнего уровня, которые встречаются: $(jq -r '[(if type == "array" then .[] else . end) | keys[]] | unique | join(", ")' "$T/xr.json")"

echo
echo "=== Все конфиги со стрелками в названии — целиком, без ключей и паролей"
jq -r -L "$T" 'include "red"; (if type == "array" then . else [.] end) | to_entries[]
  | select((.value.remarks // "") | (contains("⬇") or contains("⬆")))
  | "\n########## #\(.key) \(.value.remarks) ##########\n" + (.value | red | tojson)' "$T/xr.json" > "$T/hdr.txt"
if [ -s "$T/hdr.txt" ]; then
	while IFS= read -r l; do
		case "$l" in '{'*) printf '%s\n' "$l" | jq -L "$T" '.' ;; *) printf '%s\n' "$l" ;; esac
	done < "$T/hdr.txt"
else
	echo "Конфигов со стрелками нет"
fi

echo
echo "=== Для сравнения: группа АВТО (первая с балансировщиком) — только структура"
jq -r '(if type == "array" then . else [.] end) | map(select((.routing.balancers // []) | length > 0)) | .[0] // empty
  | "название: \(.remarks)\nвыходов: \(.outbounds | length) — \([.outbounds[] | "\(.tag):\(.protocol)"] | join(", "))\nбалансировщики: \(.routing.balancers | tojson)\nobservatory: \(.observatory // null | tojson)\nburstObservatory: \(.burstObservatory // null | tojson)"' "$T/xr.json"

echo
echo "=== Формат ссылок: строки со стрелками (без ключей)"
curl -fsSL --compressed -m 25 -A 'v2rayN/7.0' -o "$T/ln.txt" "$U"
if grep -qE '^[a-z0-9]+://' "$T/ln.txt" 2>/dev/null; then cp "$T/ln.txt" "$T/l.txt"; else base64 -d "$T/ln.txt" > "$T/l.txt" 2>/dev/null; fi
grep -E '^[a-z0-9]+://' "$T/l.txt" 2>/dev/null | while IFS= read -r l; do
	n="${l#*#}"; n="$(printf '%b' "$(printf '%s' "$n" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")"
	case "$n" in *⬇*|*⬆*) printf '  %s\n    %s\n' "$n" "$(printf '%s' "${l%%#*}" | sed 's#://[^@]*@#://***@#; s/\(pbk\|sid\|password\|obfs-password\)=[^&]*/\1=***/g')" ;; esac
done
