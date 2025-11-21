# --- Определяем данные устройства ---
VER=$(grep DISTRIB_RELEASE /etc/openwrt_release | cut -d"'" -f2)
MAJOR=$(echo "$VER" | cut -d'.' -f1)

TARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f1)
SUBTARGET=$(grep "^DISTRIB_TARGET=" /etc/openwrt_release | cut -d"'" -f2 | cut -d'/' -f2)

BOARD=$(grep -o '"id": *"[^"]*"' /etc/board.json | cut -d'"' -f4)
BOARD=$(echo "$BOARD" | sed 's/,/_/g')

# Фиксированная версия OpenWRT — всегда 24.10.4
VERSION="24.10.4"

URL="https://firmware-selector.openwrt.org/?version=$VERSION&target=${TARGET}%2F${SUBTARGET}&id=$BOARD"


# --- Проверка версии OpenWRT ---
if [ "$MAJOR" -lt 23 ]; then
    echo "Обнаружена версия OpenWRT $VER — требуется 23 или новее."
    echo "Подходящая прошивка для вашего роутера:"
    echo "$URL"
    exit 1
fi

# --- Если версия нормальная ---
echo "Версия OpenWRT поддерживается: $VER"
echo "Ссылка на прошивку: $URL"
