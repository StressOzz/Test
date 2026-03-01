#!/bin/sh
set -eu

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"
TMP="$(mktemp)"

[ -r "$IN" ] || { echo "Can't read $IN" >&2; exit 1; }
command -v awk >/dev/null 2>&1 || { echo "Missing awk" >&2; exit 1; }

awk -v OUT="$TMP" '
function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function lc(s){ return tolower(s) }
function split_endpoint(s,    a,n){
  s=trim(s)
  n=split(s,a,":")
  if(n<2){ host=s; port="" } else {
    port=a[n]
    host=a[1]
    for(i=2;i<n;i++) host=host ":" a[i]
  }
}
BEGIN{
  sec=""
  addr4=""; addr6=""; mtu=""
  priv=""; pub=""; psk=""; allowed=""; endpoint=""; keep=""
}
{
  line=$0
  sub(/[;#].*$/, "", line)
  line=trim(line)
  if(line=="") next

  if(line ~ /^\[.*\]$/){
    sec=lc(trim(substr(line,2,length(line)-2)))
    next
  }

  if(index(line,"=")==0) next
  key=trim(substr(line,1,index(line,"=")-1))
  val=trim(substr(line,index(line,"=")+1))
  lkey=lc(key)

  if(sec=="interface"){
    if(lkey=="address"){
      gsub(/,/, " ", val)
      n=split(val, a, /[ \t]+/)
      for(i=1;i<=n;i++){
        if(a[i] ~ /:/) addr6=a[i]; else addr4=a[i]
      }
    } else if(lkey=="privatekey") priv=val
    else if(lkey=="mtu") mtu=val
  } else if(sec=="peer"){
    if(lkey=="publickey") pub=val
    else if(lkey=="presharedkey") psk=val
    else if(lkey=="allowedips") { gsub(/[ \t]+/, "", val); allowed=val }
    else if(lkey=="endpoint") endpoint=val
    else if(lkey=="persistentkeepalive") keep=val
  }
}
END{
  if(priv=="" || pub=="" || endpoint==""){
    print "WARP.conf missing required fields (PrivateKey/PublicKey/Endpoint)" > "/dev/stderr"
    exit 2
  }
  split_endpoint(endpoint)

  if(allowed=="") allowed="0.0.0.0/0,::/0"
  n=split(allowed, aip, ",")
  allowed_yaml="["
  for(i=1;i<=n;i++){
    if(i>1) allowed_yaml=allowed_yaml ", "
    allowed_yaml=allowed_yaml "\"" aip[i] "\""
  }
  allowed_yaml=allowed_yaml "]"

  print "mixed-port: 7890" > OUT
  print "allow-lan: true" >> OUT
  print "mode: rule" >> OUT
  print "log-level: info" >> OUT
  print "" >> OUT

  print "proxies:" >> OUT
  print "  - name: \"WARP\"" >> OUT
  print "    type: wireguard" >> OUT
  print "    server: " host >> OUT
  if(port!="") print "    port: " port >> OUT
  if(addr4!="") print "    ip: " addr4 >> OUT
  if(addr6!="") print "    ipv6: " addr6 >> OUT
  print "    private-key: \"" priv "\"" >> OUT
  print "    public-key: \"" pub "\"" >> OUT
  if(psk!="") print "    pre-shared-key: \"" psk "\"" >> OUT
  print "    allowed-ips: " allowed_yaml >> OUT
  if(mtu!="") print "    mtu: " mtu >> OUT
  if(keep!="") print "    persistent-keepalive: " keep >> OUT

  print "" >> OUT
  print "proxy-groups:" >> OUT
  print "  - name: \"PROXY\"" >> OUT
  print "    type: select" >> OUT
  print "    proxies: [\"WARP\", \"DIRECT\"]" >> OUT
  print "" >> OUT
  print "rules:" >> OUT
  print "  - MATCH,PROXY" >> OUT
}
' "$IN"

chmod 600 "$TMP"
mkdir -p "$(dirname "$OUT")"
mv -f "$TMP" "$OUT"
echo "Written: $OUT"
