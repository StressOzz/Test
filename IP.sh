#!/bin/sh
U="${1:-https://sub.skytunnel.pw/1077208916_StressKVN_bot_NFsey}"
T=/tmp/zm-subcheck
mkdir -p "$T"
trap 'rm -rf "$T"' EXIT INT TERM

command -v jq >/dev/null 2>&1 || { echo "Нет jq: apk add jq (или opkg install jq)"; exit 1; }

cat > "$T/q.jq" <<'EOF'
(if type=="array" then . else [.] end) | to_entries[] | .key as $i | .value as $c
| [$c.outbounds[]? | select(.protocol=="vless" or .protocol=="trojan" or .protocol=="shadowsocks" or .protocol=="hysteria" or .protocol=="vmess")
   | (.settings // {}) as $s | ($s.vnext[0] // $s.servers[0] // $s) as $x
   | "\(.tag // "-")=\(.protocol)/\(.streamSettings.network // "tcp")/\(.streamSettings.security // "none")@\($x.address // "?"):\($x.port // "?")"
     + (if (.streamSettings.sockopt.dialerProxy // "") != "" then " (через \(.streamSettings.sockopt.dialerProxy))" else "" end)] as $o
| "#\($i) \($c.remarks // "-") | серверов: \($o|length)"
  + (if ($o|length) > 0 then "\n    " + ($o|join("\n    ")) else "" end)
  + (if (($c.routing.balancers // [])|length) > 0 then "\n    БАЛАНСИР: " + ([$c.routing.balancers[] | "\(.tag) \(.strategy.type // "random") по [\((.selector // [])|join(","))] запасной=\(.fallbackTag // "-")"]|join("; ")) else "" end)
  + (if $c.observatory then "\n    observatory: \($c.observatory.probeUrl // "-") каждые \($c.observatory.probeInterval // "-") по [\(($c.observatory.subjectSelector // [])|join(","))]" else "" end)
  + (if $c.burstObservatory then "\n    burstObservatory: \($c.burstObservatory.pingConfig.destination // "-") каждые \($c.burstObservatory.pingConfig.interval // "-") по [\(($c.burstObservatory.subjectSelector // [])|join(","))]" else "" end)
  + (if (($c.routing.rules // [])|length) > 0 then "\n    правил маршрутизации: \(($c.routing.rules|length)); куда по умолчанию: \(([$c.routing.rules[] | .balancerTag // .outboundTag // empty] | last) // "-")" else "" end)
EOF

echo "=== Формат Happ (Xray JSON)"
curl -fsSL --compressed -m 25 -A 'Happ/4.5.4/Windows/2610141139602' -D "$T/h.txt" -o "$T/xr.json" "$U"; echo "rc=$?"
grep -iE '^(profile-|subscription-userinfo|content-type)' "$T/h.txt" 2>/dev/null | cut -c1-120
if jq -e . "$T/xr.json" >/dev/null 2>&1; then
	jq -r -f "$T/q.jq" "$T/xr.json"
else
	echo "не JSON, первые символы: $(head -c 40 "$T/xr.json" 2>/dev/null | tr -cd 'A-Za-z0-9:/+=._ -')"
fi

echo
echo "=== Формат sing-box"
curl -fsSL --compressed -m 25 -A 'sing-box 1.12.0' -o "$T/sb.json" "$U"; echo "rc=$?"
if jq -e . "$T/sb.json" >/dev/null 2>&1; then
	jq -r '"серверов: \([.outbounds[]? | select(.server)] | length)",
		(.outbounds[]? | select(.type=="urltest" or .type=="selector") | "\(.type) «\(.tag)»: \(.outbounds|length) шт."),
		(.outbounds[]? | select(.server) | "  \(.tag) — \(.type)@\(.server):\(.server_port)")' "$T/sb.json"
else
	echo "не JSON"
fi

echo
echo "=== Формат ссылок (как берёт Steer)"
curl -fsSL --compressed -m 25 -A 'v2rayN/7.0' -o "$T/ln.txt" "$U"; echo "rc=$?"
if grep -qE '^[a-z0-9]+://' "$T/ln.txt" 2>/dev/null; then cp "$T/ln.txt" "$T/l.txt"; else base64 -d "$T/ln.txt" > "$T/l.txt" 2>/dev/null; fi
echo "ссылок: $(grep -cE '^[a-z0-9]+://' "$T/l.txt" 2>/dev/null)"
grep -E '^[a-z0-9]+://' "$T/l.txt" 2>/dev/null | while IFS= read -r l; do
	p="${l%%://*}"; n="${l#*#}"; [ "$n" = "$l" ] && n="-"
	h="$(printf '%s' "$l" | sed -n 's#^[a-z0-9]*://[^@]*@\([^?/#]*\).*#\1#p')"
	printf '  %s — %s@%s\n' "$(printf '%b' "$(printf '%s' "$n" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')")" "$p" "${h:-?}"
done
