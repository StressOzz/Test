TARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f1)
SUBTARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f2)

# Получаем board id из board.json
BOARD=$(grep -o '"id": *"[^"]*"' /etc/board.json | cut -d'"' -f4)

# Версия OpenWRT
VERSION=$(grep "^DISTRIB_RELEASE=" /etc/openwrt_release | cut -d"'" -f2)

if [ -z "$TARGET" ] || [ -z "$SUBTARGET" ] || [ -z "$BOARD" ]; then
    echo "Не удалось определить параметры устройства для Firmware Selector."
    exit 1
fi

echo "TARGET: $TARGET"
echo "SUBTARGET: $SUBTARGET"
echo "BOARD ID: $BOARD"
echo
echo "Ссылка на Firmware Selector:"
echo "https://firmware-selector.openwrt.org/?version=$VERSION&target=${TARGET}%2F${SUBTARGET}&id=$BOARD"

