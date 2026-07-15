#!/bin/sh

USE_APK=0
command -v apk >/dev/null 2>&1 && USE_APK=1

ARCH_MT=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2)

MT_VERSION="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MagiTrickle/MagiTrickle/releases/latest | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"

[ -z "$MT_VERSION" ] && { echo "Не удалось определить версию"; exit 1; }

URL_APK="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-r1_openwrt_${ARCH_MT}.apk"
URL_IPK="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-1_openwrt_${ARCH_MT}.ipk"

if [ "$USE_APK" -eq 1 ]; then

    FILE_MT="/tmp/magitrickle.apk"

    clear

    echo "Скачивание:"
    echo "$URL_APK"

    curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL_APK" >/dev/null 2>&1 || {
        echo "Ошибка скачивания"
        exit 1
    }

    echo "Установка $(basename "$URL_APK")"

    apk add --allow-untrusted "$FILE_MT" >/dev/null 2>&1 || {
        echo "Ошибка установки"
        exit 1
    }

else

    FILE_MT="/tmp/magitrickle.ipk"

    echo "Скачивание:"
    echo "$URL_IPK"

    curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL_IPK" >/dev/null 2>&1 || {
        echo "Ошибка скачивания"
        exit 1
    }

    echo "Установка $(basename "$URL_IPK")"

    opkg install "$FILE_MT" >/dev/null 2>&1 || {
        echo "Ошибка установки"
        exit 1
    }

fi
