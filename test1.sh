#!/bin/sh
set -eu

IN="/root/WARP.conf"
OUT="/etc/mihomo/config.yaml"
TMP="$(mktemp)"

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing: $1" >&2; exit 1; }; }
need awk
need sed
need mktemp

[ -r "$IN" ] || { echo "Can't read $IN" >&2; exit 1; }

awk -v OUT="$TMP" '
function trim(s){ gsub(/^[ \t\r\n]+|[ \t\r\n]+$/, "", s); return s }
function lc(s){ return tolower(s) }
function split_endpoint(s,    a,n){
  s=trim(s)
  n=split(s,a,":")
  if(n<2){ ep_host=s; ep_port="" } else {
    ep_port=a[n]
    ep_host=a[1]
    for(i=2;i<n;i++) ep_host=ep_host ":" a[i]
  }
}
BEGIN{
  sec=""
  addr4=""; addr6=""; mtu=""; dns=""
  priv=""; pub=""; psk=""; allowed=""; endpoint=""; keep=""
  reserved=""
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
        if(a[i] ~ /:/) addr6=a[i]
        else addr4=a[i]
      }
    } else if(lkey=="privatekey") priv=val
    else if(lkey=="mtu") mtu=val
    else if(lkey=="dns") dns=val
    else if(lkey=="reserved") reserved=val
  } else if(sec=="peer"){
    if(lkey=="publickey") pub=val
    else if(lkey=="presharedkey") psk=val
    else if(lkey=="allowedips") { gsub(/[ \t]+/, "", val); allowed=val }
    else if(lkey=="endpoint") endpoint=val
    else if(lkey=="persistentkeepalive") keep=val
    else if(lkey=="reserved") reserved=val
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
  print "    server: " ep_host >> OUT
  if(ep_port!="") print "    port: " ep_port >> OUT
  if(addr4!="") print "    ip: " addr4 >> OUT
  if(addr6!="") print "    ipv6: " addr6 >> OUT
  print "    private-key: \"" priv "\"" >> OUT
  print "    public-key: \"" pub "\"" >> OUT
  if(psk!="") print "    pre-shared-key: \"" psk "\"" >> OUT
  print "    allowed-ips: " allowed_yaml >> OUT
  if(mtu!="") print "    mtu: " mtu >> OUT
  if(keep!="") print "    persistent-keepalive: " keep >> OUT

  if(reserved!=""){
    r=reserved
    gsub(/^[ \t]*\[/, "", r); gsub(/\][ \t]*$/, "", r)
    gsub(/,/, " ", r)
    gsub(/[ \t]+/, " ", r)
    r=trim(r)
    m=split(r, rv, " ")
    if(m>=3 && rv[1] ~ /^[0-9]+$/ && rv[2] ~ /^[0-9]+$/ && rv[3] ~ /^[0-9]+$/){
      print "    reserved: [" rv[1] ", " rv[2] ", " rv[3] "]" >> OUT
    }
  }

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
