#!/bin/sh
ARCH_MT=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2); CONFIG_PATH="/etc/magitrickle/state/config.yaml"
MT_VERSION="$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MagiTrickle/MagiTrickle/releases/latest | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
URL_APK="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-r1_openwrt_${ARCH_MT}.apk"
URL_IPK="https://github.com/MagiTrickle/MagiTrickle/releases/download/${MT_VERSION}/magitrickle_${MT_VERSION}-1_openwrt_${ARCH_MT}.ipk"
if [ "$USE_APK" -eq 1 ]; then FILE_MT="/tmp/magitrickle.apk"; echo "Скачивание:"; echo - e"$URL_IPK"
curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL_APK" >/dev/null 2>&1 || { echo -e "\nОшибка скачивания"; exit; }
echo -e "Устанавка $(basename "$URL_APK")"
apk add --allow-untrusted "$FILE_MT" >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка установки${NC}"; return 1; }
else FILE_MT=/tmp/magitrickle.ipk; echo "Скачивание:"; echo - e"$URL_IPK"
curl -Lf --retry 3 --retry-delay 2 -o "$FILE_MT" "$URL_IPK" >/dev/null 2>&1 || { echo -e "\nОшибка скачивания"; exit; }
echo -e "Устанавка $(basename "$URL_IPK")"
opkg install "$FILE_MT" >/dev/null 2>&1 || { echo -e "\nОшибка установки"; return 1; }; fi
