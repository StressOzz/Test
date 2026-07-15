#!/bin/sh

INSTALL="opkg install"; UPDATE="opkg update"; RAZ="ipk"; SUF=""
command -v apk >/dev/null 2>&1 && INSTALL="apk add --allow-untrusted" && UPDATE="apk update" && RAZ="apk" && SUF="r"

ARCH_MT=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2)

MT_VERSION="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MagiTrickle/MagiTrickle/releases/latest | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

[ -z "$MT_VERSION" ] && { echo "Не удалось определить версию"; exit 1; }

FILE_MT="/tmp/magitrickle.$RAZ"

URL="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-${SUF}1_openwrt_${ARCH_MT}.$RAZ"

clear

echo "Скачивание:"
echo "$URL"

curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL" >/dev/null 2>&1 || { echo "Ошибка скачивания"; exit 1; }

echo "Установка $(basename "$URL")"

$UPDATE >/dev/null 2>&1 || { echo "Ошибка обновления пакетов"; exit 1; }

$INSTALL "$FILE_MT" >/dev/null 2>&1 || { echo "Ошибка установки"; exit 1; }

echo; echo "MagiTrickle установлен (обновлён)"; echo
