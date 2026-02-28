#!/bin/sh
set -eu

OUT="/root/mihomo_groups.json"
WORK="/tmp/mihomo_groups.$$"
TAG="mihomo-groups"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Цветной вывод (ANSI). В syslog цвета не отправляем.
RED="$(printf '\033[31m')"
GRN="$(printf '\033[32m')"
YEL="$(printf '\033[33m')"
BLU="$(printf '\033[34m')"
MAG="$(printf '\033[35m')"
CYN="$(printf '\033[36m')"
RST="$(printf '\033[0m')"

logc() {
  color="$1"; shift
  msg="$*"
  printf "%b%s%b\n" "$color" "$msg" "$RST"
  if command -v logger >/dev/null 2>&1; then
    logger -t "$TAG" "$msg"
  fi
}

fetch() {
  u="$1"; d="$2"
  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O "$d" "$u"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$d" "$u"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$d" "$u"
  else
    logc "$RED" "ОШИБКА: нет uclient-fetch/wget/curl для загрузки"
    exit 1
  fi
}

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

logc "$CYN" "Старт: собираю группы для Mihomo -> $OUT"
LIST_COUNT="$(printf "%s" "$URLS" | awk 'NF{c++} END{print c+0}')"
logc "$YEL" "Списков для загрузки: $LIST_COUNT"

printf "%s" "$URLS" | while IFS= read -r url; do
  [ -n "$url" ] || continue
  base="$(basename "$url")"
  dst="$WORK/$base"
  logc "$BLU" "Загружаю: $base"
  fetch "$url" "$dst"
  lines="$(wc -l < "$dst" 2>/dev/null || echo 0)"
  logc "$GRN" "Готово: $base (строк: $lines)"
done

awk '
function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
function tolower_ascii(s,   i,c,r,up,lo){
  up="ABCDEFGHIJKLMNOPQRSTUVWXYZ"; lo="abcdefghijklmnopqrstuvwxyz"; r=""
  for(i=1;i<=length(s);i++){ c=substr(s,i,1); p=index(up,c); if(p) c=substr(lo,p,1); r=r c }
  return r
}
function titlecase(s){ return (s==""?s:toupper(substr(s,1,1)) substr(s,2)) }
FNR==1{
  fn=FILENAME
  sub(/^.*\//,"",fn); sub(/\.lst$/,"",fn)
  grp=titlecase(tolower_ascii(fn))

  # Переименование группы: Inside-kvas -> Russia-Inside
  if (grp=="Inside-kvas") grp="Russia-Inside"
}
{
  line=$0
  sub(/#.*/,"",line); sub(/;.*/,"",line)
  line=trim(line)
  if(line=="") next

  gsub(/^([a-zA-Z]+:\/\/)/,"",line)
  sub(/\/.*$/,"",line)
  if(line ~ /^\*\./) line=substr(line,2)
  if(line ~ /^\./) line=substr(line,2)

  print grp "\t" line
}
' "$WORK"/*.lst > "$WORK/tagged.tsv"

TAGGED_TOTAL="$(wc -l < "$WORK/tagged.tsv" 2>/dev/null || echo 0)"
logc "$MAG" "Всего строк: $TAGGED_TOTAL"
logc "$CYN" "Сздаём общий список. Ждите..."


awk -F '\t' '
function is_ipv4(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) }
function is_ipv4_cidr(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/) }
function is_ipv6_cidr(s){ return (s ~ /^[0-9a-fA-F:]+\/[0-9]{1,3}$/) }
function is_domainish(s){ return (s ~ /^[A-Za-z0-9][A-Za-z0-9.-]*\.[A-Za-z0-9.-]+$/) }
function dotcount(s,  i,c,n){ n=0; for(i=1;i<=length(s);i++){ c=substr(s,i,1); if(c==".") n++ } return n }
function json_escape(s,  i,c,o){
  o=""
  for(i=1;i<=length(s);i++){
    c=substr(s,i,1)
    if(c=="\\") o=o "\\\\"
    else if(c=="\"") o=o "\\\""
    else if(c=="\r" || c=="\n") o=o ""
    else o=o c
  }
  return o
}
function rid(    x){
  "hexdump -n 4 -e \x27/1 \"%02x\"\x27 /dev/urandom 2>/dev/null" | getline x
  close("hexdump -n 4 -e \x27/1 \"%02x\"\x27 /dev/urandom 2>/dev/null")
  if(x=="") x="00000000"
  return x
}
function rand_color(    h){
  "hexdump -n 3 -e \x27/1 \"%02x\"\x27 /dev/urandom 2>/dev/null" | getline h
  close("hexdump -n 3 -e \x27/1 \"%02x\"\x27 /dev/urandom 2>/dev/null")
  if(h=="") h="ffffff"
  return "#" h
}
BEGIN{
  print "{\"groups\":["
  first_group=1
}
{
  g=$1; v=$2
  key=g SUBSEP v
  if(seen[key]++) next
  groups[g]=1
  vals[g, ++cnt[g]] = v
}
END{
  n=0
  for(g in groups){ glist[++n]=g }
  for(i=1;i<=n;i++) for(j=i+1;j<=n;j++) if(glist[i] > glist[j]){ t=glist[i]; glist[i]=glist[j]; glist[j]=t }

  # отчёт в stderr: группа\tвсего\tnamespace\tdomain\tsubnet\tsubnet6
  for(gi=1; gi<=n; gi++){
    g=glist[gi]
    m=cnt[g]
    dn=0; nm=0; sn=0; s6n=0
    for(i=1;i<=m;i++){
      v=vals[g,i]
      if(is_ipv6_cidr(v)) s6n++
      else if(is_ipv4_cidr(v) || is_ipv4(v)) sn++
      else if(is_domainish(v)){ if(dotcount(v)>=2) dn++; else nm++ }
      else nm++
    }
    print g "\t" m "\t" nm "\t" dn "\t" sn "\t" s6n > "/dev/stderr"
  }

  for(gi=1; gi<=n; gi++){
    g=glist[gi]
    if(!first_group) print ","
    first_group=0

    gid=rid()
    color=rand_color()

    print "{\"id\":\"",gid,"\",\"name\":\"",json_escape(g),"\",\"color\":\"",color,"\",\"interface\":\"Mihomo\",\"enable\":true,\"rules\":["
    first_rule=1

    m=cnt[g]
    for(i=1;i<=m;i++) vlist[i]=vals[g,i]
    for(i=1;i<=m;i++) for(j=i+1;j<=m;j++) if(vlist[i] > vlist[j]){ t=vlist[i]; vlist[i]=vlist[j]; vlist[j]=t }

    for(i=1;i<=m;i++){
      v=vlist[i]
      if(v=="") continue

      if(is_ipv6_cidr(v)) typ="subnet6"
      else if(is_ipv4_cidr(v) || is_ipv4(v)) typ="subnet"
      else if(is_domainish(v)){
        if(dotcount(v)>=2) typ="domain"; else typ="namespace"
      } else typ="namespace"

      if(!first_rule) print ","
      first_rule=0
      print "{\"enable\":true,\"id\":\"",rid(),"\",\"name\":\"\",\"rule\":\"",json_escape(v),"\",\"type\":\"",typ,"\"}"
    }
    print "]}"
    delete vlist
  }
  print "]}"
}
' "$WORK/tagged.tsv" 2> "$WORK/report.tsv" > "$OUT"

# Итог: одна строка на группу, но внутри строки разные цвета:
# - Название группы: CYN
# - Ключи (всего/namespace/...): MAG
# - Числа после "=": YEL
NAMEC="$CYN"
KEYC="$RST"
NUMC="$YEL"

logc "$MAG" "Итог по группам:"

while IFS="$(printf '\t')" read -r g total ns dom sn s6; do
  [ -n "${g:-}" ] || continue

  printf "%b%s%b: %bвсего%b=%b%s%b %bnamespace%b=%b%s%b %bdomain%b=%b%s%b %bsubnet%b=%b%s%b %bsubnet6%b=%b%s%b\n" \
    "$NAMEC" "$g" "$RST" \
    "$KEYC" "$RST" "$NUMC" "${total:-0}" "$RST" \
    "$KEYC" "$RST" "$NUMC" "${ns:-0}" "$RST" \
    "$KEYC" "$RST" "$NUMC" "${dom:-0}" "$RST" \
    "$KEYC" "$RST" "$NUMC" "${sn:-0}" "$RST" \
    "$KEYC" "$RST" "$NUMC" "${s6:-0}" "$RST"
done < "$WORK/report.tsv"

logc "$GRN" "Готово. Файл сохранён: $OUT"
logc "$YEL" "Подсказка: посмотреть системные логи: logread -e $TAG"
