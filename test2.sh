# TARGET и SUBTARGET
TARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f1)
SUBTARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f2)

# BOARD ID из board.json
BOARD=$(grep -o '"id": *"[^"]*"' /etc/board.json | cut -d'"' -f4)

# Преобразуем запятую в подчёркивание
BOARD=$(echo "$BOARD" | sed 's/,/_/g')

# Жёстко заданная версия OpenWRT
VERSION="24.10.4"

echo "https://firmware-selector.openwrt.org/?version=$VERSION&target=${TARGET}%2F${SUBTARGET}&id=$BOARD"
