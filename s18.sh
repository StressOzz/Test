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
  if [ "$bytes" -gt 0 ] && [ "$nl" -eq 0 ]; then echo 1; else echo "$nl"; fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || { say "$RED" "Нужна утилита: $1"; exit 1; }; }
need_cmd tar; need_cmd awk; need_cmd wc; need_cmd basename; need_cmd find; need_cmd head; need_cmd cp; need_cmd hexdump

clear
say "$CYN" "Старт: собираю списки -> $OUT"

# 1) Быстро: скачиваем tarball репозитория и берём нужные .lst
TARBALL="$WORK/repo.tgz"
say "$YEL" "Скачиваю архив allow-domains (tarball)"
fetch "https://api.github.com/repos/itdoginfo/allow-domains/tarball/main" "$TARBALL"

REPO="$WORK/repo"
mkdir -p "$REPO"
tar -xzf "$TARBALL" -C "$REPO"

ROOTDIR="$(find "$REPO" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
[ -n "${ROOTDIR:-}" ] || { say "$RED" "Не нашёл корневую папку архива"; exit 1; }

copy_lst_dir() {
  src="$1"
  [ -d "$src" ] || return 0
  find "$src" -maxdepth 1 -type f -name '*.lst' -print | while IFS= read -r f; do
    b="$(basename "$f")"
    cp "$f" "$WORK/$b"
  done
}

say "$YEL" "Копирую списки из Categories/ Services/ Subnets/IPv4/ Subnets/IPv6"
copy_lst_dir "$ROOTDIR/Categories"
copy_lst_dir "$ROOTDIR/Services"
copy_lst_dir "$ROOTDIR/Subnets/IPv4"
copy_lst_dir "$ROOTDIR/Subnets/IPv6"

# 2) Плюс inside-kvas.lst
INSIDE="$WORK/inside-kvas.lst"
say "$BLU" "Загружаю: inside-kvas.lst"
fetch "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst" "$INSIDE"

say "$MAG" "Скачано файлов: $(find "$WORK" -maxdepth 1 -name '*.lst' | wc -l | tr -d ' ')"

# --- Tagging ---
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

  # РЕЖЕМ /path ТОЛЬКО у URL со схемой, CIDR не трогаем
  if (line ~ /^[a-zA-Z]+:\/\//) {
    gsub(/^([a-zA-Z]+:\/\/)/,"",line)
    sub(/\/.*$/,"",line)
  }

  if(line ~ /^\*\./) line=substr(line,2)
  if(line ~ /^\./) line=substr(line,2)

  print grp "\t" line
}
' "$WORK"/*.lst > "$WORK/tagged.tsv"

say "$MAG" "Всего правил после очистки: $(wc -l < "$WORK/tagged.tsv" 2>/dev/null || echo 0)"
say "$CYN" "Генерирую $OUT ..."

# --- Build JSON + report ---
awk -F '\t' '
function is_ipv4(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}$/) }
function is_ipv4_cidr(s){ return (s ~ /^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$/) }
function is_ipv6(s){ return (s ~ /^[0-9a-fA-F:]+$/) }
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
BEGIN{ print "{\"groups\":["; first_group=1 }
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
      if(is_ipv6_cidr(v) || is_ipv6(v)) s6n++
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

      if(is_ipv6_cidr(v) || is_ipv6(v)) typ="subnet6"
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

# --- Pretty output (hide =0) ---
NAMEC="$CYN"; KEYC="$WHT"; NUMC="$YEL"
say "$MAG" "Итог по группам:"

while IFS="$(printf '\t')" read -r g total ns dom sn s6; do
  [ -n "${g:-}" ] || continue
  line="${NAMEC}${g}${RST}:"

  add_kv() {
    k="$1"; v="${2:-0}"
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
