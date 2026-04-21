#!/bin/sh

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.6/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.6/routerich"
TMP="/tmp/z2r"

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

ARCH="aarch64_cortex-a53"

# ---------- VERSION PARSER ----------

get_ver() {
    echo "$1" | awk -F'_' '{print $2}'
}

get_installed_ver() {
    opkg list-installed | awk -v p="$1" '$1==p {print $3}'
}

find_latest() {
    wget -qO- "$BASE_HTML" \
    | grep -oE "${1}_[0-9][^\"']*_${ARCH}\.ipk" \
    | sort -V \
    | tail -n1
}

# ---------- PACKAGE INSTALL ----------

install_pkg() {
    PKG="$(find_latest "$1")"
    [ -z "$PKG" ] && {
        echo -e "\n${RED}Пакет не найден${NC}\n"
        exit 1
    }

    VER="$(get_ver "$PKG")"

    echo -e "\n${CYAN}Пакет:${NC} $PKG"
    echo -e "${CYAN}Версия:${NC} $VER"
    echo -e "${CYAN}Скачивание...${NC}"

    mkdir -p "$TMP"
    wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" || {
        echo -e "${RED}Ошибка скачивания${NC}"
        exit 1
    }

    echo -e "${CYAN}Установка...${NC}"
    opkg install "$TMP/$PKG" || {
        echo -e "${RED}Ошибка установки${NC}"
        exit 1
    }
}

# ---------- ZAPRET ----------

zap_inst="$(get_installed_ver zapret2)"
zap_latest_file="$(find_latest zapret2_)"
zap_latest_ver="$(get_ver "$zap_latest_file")"

is_zap_installed() { [ -n "$zap_inst" ]; }
is_zap_update() { is_zap_installed && [ "$zap_inst" != "$zap_latest_ver" ]; }

install_zapret() {
    opkg update
    install_pkg "zapret2_"
    install_pkg "luci-app-zapret2_"
    echo -e "\n${GREEN}✔ Zapret установлен${NC}\n"
}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    echo -e "\n${GREEN}✔ Zapret удалён${NC}\n"
}

update_zapret() {
    echo -e "\n${YELLOW}→ Обновление Zapret${NC}"
    install_zapret
}

# ---------- ZEROBLOCK ----------

zero_inst="$(get_installed_ver zeroblock)"
zero_latest_file="$(find_latest zeroblock)"
zero_latest_ver="$(get_ver "$zero_latest_file")"

is_zero_installed() { [ -n "$zero_inst" ]; }
is_zero_update() { is_zero_installed && [ "$zero_inst" != "$zero_latest_ver" ]; }

install_zeroblock() {
    opkg update
    install_pkg "zeroblock"
    install_pkg "luci-app-zeroblock"
    echo -e "\n${GREEN}✔ Zeroblock установлен${NC}\n"
}

remove_zeroblock() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zeroblock zeroblock
    rm -rf /etc/config/zeroblock*
    rm -rf /etc/zeroblock*
    rm -rf /opt/zeroblock*
    rm -rf /usr/bin/zeroblock*
    echo -e "\n${GREEN}✔ Zeroblock удалён${NC}\n"
}

update_zeroblock() {
    echo -e "\n${YELLOW}→ Обновление Zeroblock${NC}"
    install_zeroblock
}

# ---------- ROUTERICH ----------

is_routerich() {
    grep -q "routerich" /etc/opkg/customfeeds.conf
}

add_routerich() {
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.5/routerich' \
    > /etc/opkg/customfeeds.conf
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    opkg update
    echo -e "\n${GREEN}✔ Routerich добавлен${NC}\n"
}

remove_routerich() {
    rm -f /etc/opkg/customfeeds.conf
    sed -i 's/# option check_signature/option check_signature/' /etc/opkg.conf
    opkg update
    echo -e "\n${GREEN}✔ Routerich удалён${NC}\n"
}

refresh_status() {
    zap_inst="$(get_installed_ver zapret2)"
    zap_latest_file="$(find_latest zapret2_)"
    zap_latest_ver="$(get_ver "$zap_latest_file")"

    zero_inst="$(get_installed_ver zeroblock)"
    zero_latest_file="$(find_latest zeroblock)"
    zero_latest_ver="$(get_ver "$zero_latest_file")"
}



# ---------- MENU ----------

menu() {

refresh_status
    clear

echo "███████╗██████╗ ██████╗ "
echo "╚══███╔╝╚════██╗██╔══██╗"
echo "  ███╔╝  █████╔╝██████╔╝"
echo " ███╔╝  ██╔═══╝ ██╔══██╗"
echo "███████╗███████╗██║  ██║"
echo "╚══════╝╚══════╝╚═╝  ╚═╝"

echo

echo -e "${CYAN}Zapret:${NC} $zap_inst → $zap_latest_ver"
echo -e "${CYAN}Zeroblock:${NC} $zero_inst → $zero_latest_ver"

echo

# ZAPRET STATE
if is_zap_installed; then
    if is_zap_update; then
        ZAP_OPT="Обновить"
    else
        ZAP_OPT="Удалить"
    fi
else
    ZAP_OPT="Установить"
fi

# ZERO STATE
if is_zero_installed; then
    if is_zero_update; then
        ZERO_OPT="Обновить"
    else
        ZERO_OPT="Удалить"
    fi
else
    ZERO_OPT="Установить"
fi

# ROUTERICH
if is_routerich; then
    ROUTE_OPT="Удалить"
else
    ROUTE_OPT="Добавить"
fi

echo "1) $ZAP_OPT Zapret 2"
echo "2) $ZERO_OPT Zeroblock"
echo "3) $ROUTE_OPT пакеты Routerich"
echo "Enter) Выход"

echo -en "\nВыбор: "
read c

case "$c" in
    1)
        if is_zap_installed; then
            if is_zap_update; then update_zapret; else remove_zapret; fi
        else install_zapret; fi
    ;;
    2)
        if is_zero_installed; then
            if is_zero_update; then update_zeroblock; else remove_zeroblock; fi
        else install_zeroblock; fi
    ;;
    3)
        if is_routerich; then remove_routerich; else add_routerich; fi
    ;;
    *)
        exit 0
    ;;
esac

echo -e "\nEnter..."
read
}

while true; do
    menu
done
