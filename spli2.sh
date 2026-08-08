#!/bin/sh

TMP="/tmp/release_install"
mkdir -p "$TMP"

. /etc/openwrt_release

ARCH="$DISTRIB_ARCH"

case "$ARCH" in
    aarch64_cortex-a53)
        STEER_ARCH="aarch64_cortex-a53"
        SPLIFY_ARCH="aarch64_cortex-a53"
        ;;
    aarch64_generic)
        STEER_ARCH="aarch64_generic"
        SPLIFY_ARCH="aarch64_generic"
        ;;
    arm_cortex-a7_neon-vfpv4)
        STEER_ARCH="arm_cortex-a7_neon-vfpv4"
        SPLIFY_ARCH="arm_cortex-a7_neon-vfpv4"
        ;;
    mipsel_24kc)
        STEER_ARCH="mipsel_24kc"
        SPLIFY_ARCH="mipsel_24kc"
        ;;
    mips_24kc)
        STEER_ARCH="mips_24kc"
        SPLIFY_ARCH="mips_24kc"
        ;;
    x86_64)
        STEER_ARCH="x86_64"
        SPLIFY_ARCH="x86_64"
        ;;
    *)
        echo "Неподдерживаемая архитектура: $ARCH"
        rm -rf "$TMP"
        exit 1
        ;;
esac


get_latest_tag() {
    curl -Ls -o /dev/null -w '%{url_effective}' "$1" |
        sed 's#.*/tag/##'
}


install_steer() {
    echo "Устанавливаем Steer"

    TAG="$(get_latest_tag "https://github.com/xyzmean/steer/releases/latest")"

    [ -n "$TAG" ] || {
        echo "Не удалось определить последнюю версию Steer"
        return 1
    }

    VER="${TAG#v}"

    FILE="steer-extended-${VER}-1_${STEER_ARCH}.apk"
    URL="https://github.com/xyzmean/steer/releases/download/${TAG}/${FILE}"

    echo "Версия: $VER"
    echo "Архитектура: $STEER_ARCH"

    curl -fL "$URL" -o "$TMP/$FILE" || {
        echo "Ошибка скачивания Steer"
        return 1
    }

    apk add --allow-untrusted "$TMP/$FILE" || {
        echo "Ошибка установки Steer"
        rm -f "$TMP/$FILE"
        return 1
    }

    rm -f "$TMP/$FILE"

    echo "Steer установлен"
}


install_splify() {
    echo "Устанавливаем Splify"

    TAG="$(get_latest_tag "https://github.com/xyzmean/splify2/releases/latest")"

    [ -n "$TAG" ] || {
        echo "Не удалось определить последнюю версию Splify"
        return 1
    }

    VER="${TAG#v}"

    PAGE="$(curl -fsSL "https://github.com/xyzmean/splify2/releases/tag/${TAG}")" || {
        echo "Не удалось получить страницу release Splify"
        return 1
    }

    FILE="$(
        echo "$PAGE" |
        grep -oE 'href="[^"]+\.apk"' |
        sed 's/^href="//;s/"$//' |
        grep "_${SPLIFY_ARCH}\.apk$" |
        sed 's#.*/##' |
        head -n1
    )"

    [ -n "$FILE" ] || {
        echo "APK Splify для $SPLIFY_ARCH не найден"
        return 1
    }

    URL="https://github.com/xyzmean/splify2/releases/download/${TAG}/${FILE}"

    echo "Версия: $VER"
    echo "Архитектура: $SPLIFY_ARCH"
    echo "Файл: $FILE"

    curl -fL "$URL" -o "$TMP/$FILE" || {
        echo "Ошибка скачивания Splify"
        return 1
    }

    apk add --allow-untrusted "$TMP/$FILE" || {
        echo "Ошибка установки Splify"
        rm -f "$TMP/$FILE"
        return 1
    }

    rm -f "$TMP/$FILE"

    echo "Splify установлен"
}


echo "Архитектура: $ARCH"

install_steer
install_splify

rm -rf "$TMP"
