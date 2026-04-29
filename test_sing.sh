#!/bin/sh

LATEST_URL_SING=$(curl -sL -o /dev/null -w '%{url_effective}' https://github.com/shtorm-7/sing-box-extended/releases/latest)

VERSION_SING=$(echo "$LATEST_URL_SING" | awk -F'/tag/v' '{print $2}')

if command -v opkg >/dev/null 2>&1; then
    ARCH_SING="$(opkg print-architecture | awk '{print $2}' | tail -n1)"
elif command -v apk >/dev/null 2>&1; then
    ARCH_SING="$(apk --print-arch)"
else
    ARCH_SING="$(uname -m)"
fi

case "$ARCH_SING" in
  aarch64)           ARCH_SUFFIX_SING="arm64" ;;
  armv7*)            ARCH_SUFFIX_SING="armv7" ;;
  armv6*)            ARCH_SUFFIX_SING="armv6" ;;
  x86_64)            ARCH_SUFFIX_SING="amd64" ;;
  i386|i686)         ARCH_SUFFIX_SING="386" ;;
  mips)              ARCH_SUFFIX_SING="mips-softfloat" ;;
  mipsel|mipsle)     ARCH_SUFFIX_SING="mipsle-softfloat" ;;
  mips64)            ARCH_SUFFIX_SING="mips64" ;;
  mips64el|mips64le) ARCH_SUFFIX_SING="mips64le" ;;
  riscv64)           ARCH_SUFFIX_SING="riscv64" ;;
  s390x)             ARCH_SUFFIX_SING="s390x" ;;
esac

[ -z "$ARCH_SUFFIX_SING" ] && { echo "unsupported arch: $ARCH_SING"; exit 1; }

BASE_SING="https://github.com/shtorm-7/sing-box-extended/releases/download"
FILE_SING="sing-box-${VERSION_SING}-linux-${ARCH_SUFFIX_SING}.tar.gz"
URL_SING="${BASE_SING}/v${VERSION_SING}/${FILE_SING}"

echo "$URL_SING"

ARCHIVE_SING="/tmp/sing-box.tar.gz"
WORKDIR_SING="/tmp/sing-box-update"

rm -rf "$WORKDIR_SING"
mkdir -p "$WORKDIR_SING"

curl -L -o "$ARCHIVE_SING" "$URL_SING" || { echo "download failed"; exit 1; }

[ ! -s "$ARCHIVE_SING" ] && { echo "empty archive"; exit 1; }

tar -xzf "$ARCHIVE_SING" -C "$WORKDIR_SING" || { echo "extract failed"; exit 1; }

rm -f "$ARCHIVE_SING"

BINARY_SING=$(find "$WORKDIR_SING" -type f -name "sing-box" | head -n 1)

[ -z "$BINARY_SING" ] && { echo "binary not found"; exit 1; }

DEST_SING="/usr/bin/sing-box"

/etc/init.d/sing-box stop 2>/dev/null

mv -f "$BINARY_SING" "$DEST_SING"
chmod +x "$DEST_SING"

/etc/init.d/sing-box start 2>/dev/null

rm -rf "$WORKDIR_SING"
