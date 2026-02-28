#!/bin/sh
set -eu

OUT="/root/ItDogList.mtrickle"
WORK="/tmp/mihomo_groups.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

RED="$(printf '\033[31m')"
GRN="$(printf '\033[32m')"
YEL="$(printf '\033[33m')"
BLU="$(printf '\033[34m')"
CYN="$(printf '\033[36m')"
WHT="$(printf '\033[37m')"
MAG="$(printf '\033[35m')"
RST="$(printf '\033[0m')"

say() { color="$1"; shift; echo -e "${color}$*${RST}"; }

fetch() {
  u="$1"; d="$2"
  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O "$d" "$u"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$d" "$u"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$d" "$u"
  else
    say "$RED" "ОШИБКА: нет uclient-fetch/wget/curl"
    exit 1
  fi
}

count_lines_human() {
  f="$1"
  bytes="$(wc -c < "$f" 2>/dev/null || echo 0)"
  nl="$(wc -l < "$f" 2>/dev/null || echo 0)"
  if [ "$bytes" -gt 0 ] && [ "$nl" -eq 0 ]; then
    echo 1
  else
    echo "$nl"
  fi
}

# --- GitHub API listing (contents) ---
# Возвращает download_url для .lst файлов в директории репозитория
list_dir_lst_urls() {
  dir="$1"
  api="https://api.github.com/repos/itdoginfo/allow-domains/contents/$dir?ref=main"
  tmp="$WORK/api.$(printf "%s" "$dir" | tr '/:' '__').json"

  if command -v uclient-fetch >/dev/null 2>&1; then
    # uclient-fetch не всегда удобен с заголовками, поэтому без них (хватит и так)
    uclient-fetch -q -O "$tmp" "$api" || return 1
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$tmp" "$api" || return 1
  else
    wget -q -O "$tmp" "$api" || return 1
  fi

  # Достаём download_url только для файлов *.lst (без jq)
  # В ответе contents для директории каждый элемент имеет поля "name", "type", "download_url". [web:191]
  awk '
    BEGIN{RS="\\{"; FS="\n"}
    /"type"[[:space:]]*:[[:space:]]*"file"/ && /"name"[[:space:]]*:[[:space:]]*".*\.lst"/ {
      for(i=1;i<=NF;i++){
        if($i ~ /"download_url"[[:space:]]*:/){
          line=$i
          sub(/.*"download_url"[[:space:]]*:[[:space:]]*"/,"",line)
          sub(/".*/,"",line)
          if(line!="null" && line!="") print line
        }
      }
    }
  ' "$tmp"
}

clear
say "$CYN" "Старт: собираю списки -> $OUT"

# Директории, которые ты указал
DIRS="
Subnets/IPv4
Subnets/IPv6
Services
Categories
"

URLS=""
for d in $DIRS; do
  say "$YEL" "Читаю каталог GitHub: $d"
  urls="$(list_dir_lst_urls "$d" || true)"
  if [ -n "${urls:-}" ]; then
    URLS="$URLS
$urls"
  else
    say "$RED" "Не смог получить список файлов для $d (возможен лимит/403)"
  fi
done

# Плюс inside-kvas.lst
URLS="$URLS
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst
"

LIST_COUNT="$(printf "%s" "$URLS" | awk 'NF{c++} END{print c+0}')"
say "$YEL" "Списков для загрузки: $LIST_COUNT"

printf "%s" "$URLS" | while IFS= read -r url; do
  [ -n "$url" ] || continue
  base="$(basename "$url")"
  dst="$WORK/$base"

  say "$BLU" "Загружаю: $base"
  fetch "$url" "$dst"

  lines="$(count_lines_human "$dst")"
  say "$GRN" "Готово: $base (строк: $lines)"
done

# --- Tagging rules by group name from filename ---
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
say "$MAG" "Всего строк после очистки: $TAGGED_TOTAL"
say "$CYN" "Создаю общий список. Ждите..."

# --- Build .mtrickle JSON + report.tsv ---
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

# --- Pretty summary ---
NAMEC="$CYN"
KEYC="$WHT"
NUMC="$YEL"

say "$MAG" "Итог по группам:"

while IFS="$(printf '\t')" read -r g total ns dom sn s6; do
  [ -n "${g:-}" ] || continue

  line="${NAMEC}${g}${RST}:"

  add_kv() {
    k="$1"
    v="${2:-0}"
    if [ "$v" -ne 0 ] 2>/dev/null; then
      line="${line} ${KEYC}${k}${RST}=${NUMC}${v}${RST}"
    fi
  }

  add_kv "всего" "${total:-0}"
  add_kv "namespace" "${ns:-0}"
  add_kv "domain" "${dom:-0}"
  add_kv "subnet" "${sn:-0}"
  add_kv "subnet6" "${s6:-0}"

  echo -e "$line"
done < "$WORK/report.tsv"

say "$GRN" "Готово. Файл сохранён: $OUT"
