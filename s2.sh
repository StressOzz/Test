#!/bin/sh
set -eu

OUT="/root/itdoginfo-merged-classical.yaml"
WORKDIR="/tmp/itdoginfo_mihomo_build.$$"
mkdir -p "$WORKDIR"
trap 'rm -rf "$WORKDIR"' EXIT

URLS='
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/anime.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/block.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/geoblock.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/hodca.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/news.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/porn.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_ai.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_play.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hdrezka.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/tiktok.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/youtube.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/twitter.lst
'

fetch() {
  u="$1"
  d="$2"
  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O "$d" "$u"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$d" "$u"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$d" "$u"
  else
    echo "No downloader found (need uclient-fetch/wget/curl)" >&2
    exit 1
  fi
}

# 1) Download lists
i=0
echo "$URLS" | while IFS= read -r url; do
  [ -n "$url" ] || continue
  i=$((i+1))
  base="$(basename "$url")"
  dst="$WORKDIR/$base"
  fetch "$url" "$dst"
done

# 2) Normalize + tag each line with group name (filename w/o .lst, lowercased)
# Output: "group<TAB>kind<TAB>value"
# kind: D (domain), I (ipcidr)
awk '
function lc(s){ for(i=1;i<=length(s);i++){ c=substr(s,i,1); o=o ((c>="A"&&c<="Z")?tolower(c):c) } t=o; o=""; return t }
function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
function is_ipcidr(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/) }
BEGIN{ FS="\t" }
' >/dev/null 2>&1 || true

# BusyBox awk may be limited, so do it in a single awk without helper funcs complexity
awk '
function tolower_ascii(s,   i,c,r){ r=""; for(i=1;i<=length(s);i++){ c=substr(s,i,1); if(c>="A"&&c<="Z") c=substr("abcdefghijklmnopqrstuvwxyz", index("ABCDEFGHIJKLMNOPQRSTUVWXYZ",c),1); r=r c } return r }
function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
function is_ipcidr(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/) }
function is_ipv4(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) }
BEGIN{
  OFS="\t"
}
FNR==1{
  fn=FILENAME
  sub(/^.*\//,"",fn)
  sub(/\.lst$/,"",fn)
  grp=tolower_ascii(fn)
}
{
  line=$0
  sub(/#.*/,"",line)
  sub(/;.*/,"",line)
  line=trim(line)
  if(line=="") next

  if(is_ipcidr(line)){
    print grp,"I",line
    next
  }
  if(is_ipv4(line)){
    print grp,"I",line"/32"
    next
  }

  gsub(/^([a-zA-Z]+:\/\/)/,"",line)
  sub(/\/.*$/,"",line)
  if(line ~ /^\*\./) line=substr(line,2)
  if(line ~ /^\./) line=substr(line,2)

  if(line ~ /[A-Za-z0-9-]+\.[A-Za-z0-9.-]+/){
    print grp,"D",line
  }
}
' "$WORKDIR"/*.lst > "$WORKDIR/tagged.tsv"

# 3) Emit mihomo classical yaml payload
# classical supports lines like DOMAIN-SUFFIX,example.com and IP-CIDR,1.2.3.0/24 [web:9]
{
  echo "payload:"
  awk -F '\t' '
  function cap(s,   i,c,r){ r=toupper(substr(s,1,1)) substr(s,2); return r }
  BEGIN{ OFS="" }
  {
    grp=$1; kind=$2; val=$3
    # Build pretty group label from filename: e.g. "cloudflare" -> "Cloudflare"
    pretty=grp
    pretty=toupper(substr(pretty,1,1)) substr(pretty,2)
    key=pretty SUBSEP kind SUBSEP val
    if(seen[key]++) next
    data[pretty,kind,val]=1
    groups[pretty]=1
  }
  END{
    # Deterministic order: sort by pretty name, then kind, then value
    n=0
    for(g in groups){ n++; glist[n]=g }
    # Simple bubble sort (BusyBox awk portability)
    for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(glist[i] > glist[j]){ t=glist[i]; glist[i]=glist[j]; glist[j]=t }

    for(i=1;i<=n;i++){
      g=glist[i]
      print "  # ", g
      # domains first, then ipcidr
      for(kindIdx=1; kindIdx<=2; kindIdx++){
        kind=(kindIdx==1 ? "D" : "I")
        m=0
        for(k in data){
          split(k, a, SUBSEP)
          if(a[1]==g && a[2]==kind){
            m++; vlist[m]=a[3]
          }
        }
        for(x=1;x<=m;x++) for(y=x+1;y<=m;y++) if(vlist[x] > vlist[y]){ t=vlist[x]; vlist[x]=vlist[y]; vlist[y]=t }

        for(x=1;x<=m;x++){
          if(kind=="D") print "  - DOMAIN-SUFFIX,", vlist[x]
          else print "  - IP-CIDR,", vlist[x]
        }
        delete vlist
      }
    }
  }
  ' "$WORKDIR/tagged.tsv"
} > "$OUT"

echo "Saved: $OUT"
