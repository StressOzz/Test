#!/bin/sh
set -eu

WORK="/tmp/itdog_check.$$"
mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

fetch() {
  u="$1"; d="$2"
  if command -v uclient-fetch >/dev/null 2>&1; then
    uclient-fetch -q -O "$d" "$u"
  elif command -v wget >/dev/null 2>&1; then
    wget -q -O "$d" "$u"
  elif command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$d" "$u"
  else
    echo "ERR: need uclient-fetch/wget/curl" >&2
    exit 1
  fi
}

norm_file() {
  awk '
  function trim(s){ sub(/^[ \t\r\n]+/,"",s); sub(/[ \t\r\n]+$/,"",s); return s }
  {
    line=$0
    sub(/\r$/,"",line)
    sub(/#.*/,"",line); sub(/;.*/,"",line)
    line=trim(line)
    if(line=="") next

    if (line ~ /^[a-zA-Z]+:\/\//) {
      gsub(/^([a-zA-Z]+:\/\/)/,"",line)
      sub(/\/.*$/,"",line)
    }

    if(line ~ /^\*\./) line=substr(line,2)
    if(line ~ /^\./) line=substr(line,2)

    line=trim(line)
    if(line!="") print line
  }' "$1"
}

echo "== download repo tarball =="
fetch "https://api.github.com/repos/itdoginfo/allow-domains/tarball/main" "$WORK/repo.tgz"
mkdir -p "$WORK/repo"
tar -xzf "$WORK/repo.tgz" -C "$WORK/repo"
ROOTDIR="$(find "$WORK/repo" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

echo "== download inside-kvas =="
fetch "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst" "$WORK/inside-kvas.lst"

echo "== normalize inside-kvas =="
norm_file "$WORK/inside-kvas.lst" | sort -u > "$WORK/inside.norm"

echo "== normalize Categories + Services =="
( for f in "$ROOTDIR/Categories/"*.lst "$ROOTDIR/Services/"*.lst; do
    [ -f "$f" ] || continue
    norm_file "$f"
  done ) | sort -u > "$WORK/catsrv.norm"

echo "== counts =="
echo -n "inside unique:  " ; wc -l < "$WORK/inside.norm" | tr -d " "
echo -n "catsrv unique:  " ; wc -l < "$WORK/catsrv.norm" | tr -d " "

echo "== inside minus catsrv (count + first 50) =="
awk '
FNR==NR { seen[$0]=1; next }
!seen[$0] { print; c++ }
END { print "COUNT=" (c+0) > "/dev/stderr" }
' "$WORK/catsrv.norm" "$WORK/inside.norm" > "$WORK/diff.norm" 2> "$WORK/diff.count"

cat "$WORK/diff.count"
sed -n "1,50p" "$WORK/diff.norm"
