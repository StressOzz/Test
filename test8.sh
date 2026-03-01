#!/bin/sh
set -eu

WG="/root/WARP.conf"
TPL="/etc/mihomo/template.yaml"
OUT="/etc/mihomo/config.yaml"

[ -r "$WG" ] || { echo "No $WG" >&2; exit 1; }
[ -r "$TPL" ] || { echo "No $TPL (put site YAML there)" >&2; exit 1; }

TMP="$(mktemp)"

# 1) вытащим значения из WARP.conf
eval "$(
awk '
function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function lc(s){ return tolower(s) }
BEGIN{ sec=""; addr4=""; addr6=""; mtu=""; priv=""; pub=""; psk=""; allowed=""; endpoint=""; keep="" }
{
  line=$0
  sub(/[;#].*$/, "", line)
  line=trim(line)
  if(line=="") next
  if(line ~ /^\[.*\]$/){ sec=lc(trim(substr(line,2,length(line)-2))); next }
  if(index(line,"=")==0) next
  key=trim(substr(line,1,index(line,"=")-1))
  val=trim(substr(line,index(line,"=")+1))
  k=lc(key)

  if(sec=="interface"){
    if(k=="address"){
      gsub(/,/, " ", val)
      n=split(val,a,/[^0-9a-fA-F:./]+/)
      for(i=1;i<=n;i++){
        if(a[i]=="") continue
        if(a[i] ~ /:/) addr6=a[i]; else addr4=a[i]
      }
    } else if(k=="privatekey") priv=val
    else if(k=="mtu") mtu=val
  } else if(sec=="peer"){
    if(k=="publickey") pub=val
    else if(k=="presharedkey") psk=val
    else if(k=="allowedips"){ gsub(/[ \t]+/, "", val); allowed=val }
    else if(k=="endpoint") endpoint=val
    else if(k=="persistentkeepalive") keep=val
  }
}
END{
  if(priv==""||pub==""||endpoint==""){ print "echo \"Bad WARP.conf\" >&2; exit 2"; exit 0 }

  host=endpoint; port=""
  n=split(endpoint,a,":")
  if(n>=2){
    port=a[n]; host=a[1]
    for(i=2;i<n;i++) host=host ":" a[i]
  }

  ip=addr4; sub(/\/32$/, "", ip)
  ipv6=addr6; sub(/\/128$/, "", ipv6)

  # Печатаем безопасные shell-переменные
  printf("WG_HOST=%s\n", q(host))
}
function q(s,  t){
  t=s; gsub(/'\''/, "'\"'\"'", t)
  return "'" t "'"
}
' "$WG" | sed -n '
/^WG_HOST=/p
')"

# повторим eval аккуратно, без сложностей: сделаем одним awk, который сразу выведет все переменные
eval "$(
awk '
function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function lc(s){ return tolower(s) }
function q(s,  t){ t=s; gsub(/'\''/, "'\"'\"'", t); return "'" t "'" }
BEGIN{ sec=""; addr4=""; addr6=""; mtu=""; priv=""; pub=""; psk=""; allowed=""; endpoint=""; keep="" }
{
  line=$0; sub(/[;#].*$/, "", line); line=trim(line); if(line=="") next
  if(line ~ /^\[.*\]$/){ sec=lc(trim(substr(line,2,length(line)-2))); next }
  if(index(line,"=")==0) next
  key=trim(substr(line,1,index(line,"=")-1))
  val=trim(substr(line,index(line,"=")+1))
  k=lc(key)
  if(sec=="interface"){
    if(k=="address"){ gsub(/,/, " ", val); n=split(val,a,/[^0-9a-fA-F:./]+/); for(i=1;i<=n;i++){ if(a[i]=="") continue; if(a[i] ~ /:/) addr6=a[i]; else addr4=a[i] } }
    else if(k=="privatekey") priv=val
    else if(k=="mtu") mtu=val
  } else if(sec=="peer"){
    if(k=="publickey") pub=val
    else if(k=="presharedkey") psk=val
    else if(k=="allowedips"){ gsub(/[ \t]+/, "", val); allowed=val }
    else if(k=="endpoint") endpoint=val
    else if(k=="persistentkeepalive") keep=val
  }
}
END{
  host=endpoint; port=""
  n=split(endpoint,a,":")
  if(n>=2){ port=a[n]; host=a[1]; for(i=2;i<n;i++) host=host ":" a[i] }

  ip=addr4; sub(/\/32$/, "", ip)
  ipv6=addr6; sub(/\/128$/, "", ipv6)

  print "WG_HOST=" q(host)
  print "WG_PORT=" q(port)
  print "WG_IP=" q(ip)
  print "WG_IPV6=" q(ipv6)
  print "WG_PRIV=" q(priv)
  print "WG_PUB=" q(pub)
  print "WG_PSK=" q(psk)
  print "WG_ALLOWED=" q(allowed)
  print "WG_KEEP=" q(keep)
  print "WG_MTU=" q(mtu)
}
' "$WG"
)"

# 2) патчим template.yaml: меняем только поля внутри proxy с name: WARP
awk -v H="$WG_HOST" -v P="$WG_PORT" -v IP="$WG_IP" -v IP6="$WG_IPV6" \
    -v PR="$WG_PRIV" -v PU="$WG_PUB" -v PSK="$WG_PSK" -v AL="$WG_ALLOWED" \
    -v KA="$WG_KEEP" -v MTU="$WG_MTU" '
function ltrim(s){ sub(/^[ \t]+/,"",s); return s }
BEGIN{ inwarp=0 }
{
  line=$0
  t=ltrim(line)

  # входим в блок proxy "- name: WARP" (любая индентация)
  if(t ~ /^- name:[ \t]*"?WARP"?[ \t]*$/){ inwarp=1; print; next }

  # выходим из блока proxies, когда начался следующий "- name:" на той же индентации
  if(inwarp && t ~ /^- name:[ \t]*/){ inwarp=0; }

  if(inwarp){
    if(t ~ /^server:/){ sub(/server:.*/, "    server: " H, line); print line; next }
    if(t ~ /^port:/ && P!=""){ sub(/port:.*/, "    port: " P, line); print line; next }
    if(t ~ /^private-key:/){ sub(/private-key:.*/, "    private-key: \"" PR "\"", line); print line; next }
    if(t ~ /^public-key:/){ sub(/public-key:.*/, "    public-key: \"" PU "\"", line); print line; next }
    if(t ~ /^pre-shared-key:/ && PSK!=""){ sub(/pre-shared-key:.*/, "    pre-shared-key: \"" PSK "\"", line); print line; next }
    if(t ~ /^ip:/ && IP!=""){ sub(/ip:.*/, "    ip: " IP, line); print line; next }
    if(t ~ /^ipv6:/ && IP6!=""){ sub(/ipv6:.*/, "    ipv6: " IP6, line); print line; next }
    if(t ~ /^persistent-keepalive:/ && KA!=""){ sub(/persistent-keepalive:.*/, "    persistent-keepalive: " KA, line); print line; next }
    if(t ~ /^mtu:/ && MTU!=""){ sub(/mtu:.*/, "    mtu: " MTU, line); print line; next }
  }

  print
}
' "$TPL" > "$TMP"

chmod 600 "$TMP"
mv -f "$TMP" "$OUT"
echo "Written: $OUT"
