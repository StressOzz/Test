#!/bin/sh

# ===== Цвета =====
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
CYAN="\033[1;36m"
NC="\033[0m"

echo -e "${GREEN}===> Определение системы...${NC}"

# ===== Определяем пакетный менеджер =====
if command -v apk >/dev/null 2>&1; then
    PKG="apk"
    PKG_NAME="APK (OpenWrt 25+)"
else
    PKG="opkg"
    PKG_NAME="OPKG (OpenWrt 22-24)"
fi

echo -e "${CYAN}Пакетный менеджер: ${YELLOW}$PKG_NAME${NC}"

# ===== Установка зависимостей =====
echo -e "${GREEN}===> Установка зависимостей...${NC}"

if [ "$PKG" = "apk" ]; then
    echo -e "${CYAN}Команда: apk update && apk add curl kmod-nft-tproxy kmod-tun coreutils-base64${NC}"
    apk update
    apk add curl kmod-nft-tproxy kmod-tun coreutils-base64
else
    echo -e "${CYAN}Команда: opkg update && opkg install curl kmod-nft-tproxy kmod-tun coreutils-base64${NC}"
    opkg update
    opkg install curl kmod-nft-tproxy kmod-tun coreutils-base64
fi

# ===== Получаем версию SSClash =====
echo -e "${GREEN}===> Получение версии SSClash...${NC}"

SSCLASH_RELEASE=$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/zerolabnet/SSClash/releases/latest | sed 's#.*/tag/##; s/^v//')

if [ -z "$SSCLASH_RELEASE" ]; then
    echo -e "${RED}Ошибка получения версии SSClash${NC}"
    exit 1
fi

echo -e "${CYAN}Найдена версия SSClash: ${YELLOW}$SSCLASH_RELEASE${NC}"

# ===== Установка SSClash =====
echo -e "${GREEN}===> Установка SSClash...${NC}"

if [ "$PKG" = "apk" ]; then
    SSCLASH_FILE="luci-app-ssclash-${SSCLASH_RELEASE}-r1.apk"
    URL="https://github.com/zerolabnet/SSClash/releases/download/v$SSCLASH_RELEASE/$SSCLASH_FILE"

    echo -e "${CYAN}Скачивание: ${YELLOW}$SSCLASH_FILE${NC}"
    echo -e "${CYAN}URL: ${YELLOW}$URL${NC}"

    curl -L "$URL" -o /tmp/ssclash.apk || {
        echo -e "${RED}Ошибка скачивания SSClash${NC}"
        exit 1
    }

    echo -e "${CYAN}Установка пакета: ${YELLOW}$SSCLASH_FILE${NC}"
    apk add /tmp/ssclash.apk --allow-untrusted
    rm -f /tmp/ssclash.apk
else
    SSCLASH_FILE="luci-app-ssclash_${SSCLASH_RELEASE}-r1_all.ipk"
    URL="https://github.com/zerolabnet/SSClash/releases/download/v$SSCLASH_RELEASE/$SSCLASH_FILE"

    echo -e "${CYAN}Скачивание: ${YELLOW}$SSCLASH_FILE${NC}"
    echo -e "${CYAN}URL: ${YELLOW}$URL${NC}"

    curl -L "$URL" -o /tmp/ssclash.ipk || {
        echo -e "${RED}Ошибка скачивания SSClash${NC}"
        exit 1
    }

    echo -e "${CYAN}Установка пакета: ${YELLOW}$SSCLASH_FILE${NC}"
    opkg install /tmp/ssclash.ipk
    /etc/init.d/clash stop 2>/dev/null
    rm -f /tmp/ssclash.ipk
fi

# ===== Определяем архитектуру =====
echo -e "${GREEN}===> Определение архитектуры...${NC}"

ARCH=$(uname -m)

case "$ARCH" in
    aarch64*|arm64*)
        MIHOMO_ARCH="linux-arm64"
        ;;
    armv7*|armv7l|armhf*)
        MIHOMO_ARCH="linux-armv7"
        ;;
    mipsel*|mipsle*)
        MIHOMO_ARCH="linux-mipsle-softfloat"
        ;;
    x86_64*)
        MIHOMO_ARCH="linux-amd64-compatible"
        ;;
    *)
        echo -e "${RED}Неизвестная архитектура: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${CYAN}Архитектура системы: ${YELLOW}$ARCH${NC}"
echo -e "${CYAN}Архитектура Mihomo: ${YELLOW}$MIHOMO_ARCH${NC}"

# ===== Получаем версию Mihomo =====
echo -e "${GREEN}===> Получение версии Mihomo...${NC}"

MIHOMO_RELEASE=$(curl -Ls -o /dev/null -w '%{url_effective}' https://github.com/MetaCubeX/mihomo/releases/latest | sed 's#.*/tag/##; s/^v//')

if [ -z "$MIHOMO_RELEASE" ]; then
    echo -e "${RED}Ошибка получения версии Mihomo${NC}"
    exit 1
fi

echo -e "${CYAN}Найдена версия Mihomo: ${YELLOW}$MIHOMO_RELEASE${NC}"

# ===== Скачивание Mihomo =====
echo -e "${GREEN}===> Скачивание Mihomo...${NC}"

MIHOMO_FILE="mihomo-$MIHOMO_ARCH-v$MIHOMO_RELEASE.gz"
URL="https://github.com/MetaCubeX/mihomo/releases/download/v$MIHOMO_RELEASE/$MIHOMO_FILE"

echo -e "${CYAN}Файл: ${YELLOW}$MIHOMO_FILE${NC}"
echo -e "${CYAN}URL: ${YELLOW}$URL${NC}"

curl -L "$URL" -o /tmp/clash.gz || {
    echo -e "${RED}Ошибка скачивания Mihomo${NC}"
    exit 1
}

# ===== Установка Mihomo =====
echo -e "${GREEN}===> Установка Mihomo...${NC}"

mkdir -p /opt/clash/bin

gunzip -c /tmp/clash.gz > /opt/clash/bin/clash
chmod +x /opt/clash/bin/clash
rm -f /tmp/clash.gz

echo -e "${CYAN}Бинарник установлен: ${YELLOW}/opt/clash/bin/clash${NC}"

# ===== Финал =====
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN} Установка завершена${NC}"
echo -e "${GREEN} SSClash + Mihomo готовы к работе${NC}"
echo -e "${GREEN}======================================${NC}"
