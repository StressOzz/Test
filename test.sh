#!/bin/sh

# ===== Цвета =====
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
NC="\033[0m"

echo -e "${GREEN}===> Определение системы...${NC}"

# ===== Определяем пакетный менеджер =====
if command -v apk >/dev/null 2>&1; then
    PKG="apk"
    echo -e "${GREEN}Найден APK (OpenWrt 25+)${NC}"
else
    PKG="opkg"
    echo -e "${GREEN}Найден OPKG (OpenWrt 21-24)${NC}"
fi

# ===== Установка зависимостей =====
echo -e "${GREEN}===> Установка зависимостей...${NC}"

if [ "$PKG" = "apk" ]; then
    apk update
    apk add curl kmod-nft-tproxy kmod-tun coreutils-base64
else
    opkg update

    if grep -q "21.02" /etc/openwrt_release 2>/dev/null; then
        opkg install iptables-mod-tproxy curl kmod-tun coreutils-base64
    else
        opkg install curl kmod-nft-tproxy kmod-tun coreutils-base64
    fi
fi

# ===== Установка SSClash =====
echo -e "${GREEN}===> Установка SSClash 3.8.0...${NC}"

if [ "$PKG" = "apk" ]; then
    curl -L https://github.com/zerolabnet/SSClash/releases/download/v3.8.0/luci-app-ssclash-3.8.0-r1.apk -o /tmp/ssclash.apk
    apk add /tmp/ssclash.apk --allow-untrusted
    rm -f /tmp/ssclash.apk
else
    curl -L https://github.com/zerolabnet/SSClash/releases/download/v3.8.0/luci-app-ssclash_3.8.0-r1_all.ipk -o /tmp/ssclash.ipk
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

echo -e "${YELLOW}Архитектура: $ARCH -> $MIHOMO_ARCH${NC}"

# ===== Получаем последний релиз Mihomo =====
echo -e "${GREEN}===> Получение версии Mihomo...${NC}"

RELEASE=$(curl -s https://api.github.com/repos/MetaCubeX/mihomo/releases/latest | grep tag_name | cut -d '"' -f4)

if [ -z "$RELEASE" ]; then
    echo -e "${RED}Ошибка получения версии Mihomo${NC}"
    exit 1
fi

echo -e "${YELLOW}Последняя версия: $RELEASE${NC}"

# ===== Скачивание Mihomo =====
echo -e "${GREEN}===> Скачивание ядра Mihomo...${NC}"

URL="https://github.com/MetaCubeX/mihomo/releases/download/$RELEASE/mihomo-$MIHOMO_ARCH-$RELEASE.gz"

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

# ===== Финал =====
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN} Установка завершена${NC}"
echo -e "${GREEN} SSClash + Mihomo готовы к работе${NC}"
echo -e "${GREEN}======================================${NC}"
