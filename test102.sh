#!/bin/sh

BASE_HTML="https://github.com/routerich/packages.routerich/tree/24.10.6/routerich"
RAW_BASE="https://github.com/routerich/packages.routerich/raw/refs/heads/24.10.6/routerich"
TMP="/tmp/z2r"

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
NC="\033[0m"

ARCH="$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release)"

[ "$ARCH" = "aarch64_cortex-a53" ] || {
    echo -e "\n${RED}Неподдерживаемая архитектура!${NC}\n${GREEN}Только для ${NC}aarch64_cortex-a53\n"
    exit 1
}

find_latest() { wget -qO- "$BASE_HTML" | grep -oE "$1[^\"']+\.ipk" | sort -u | head -n1; }

get_installed_ver() {
    opkg list-installed | grep "^$1 " | awk '{print $3}'
}

get_pkg_ver() {
    echo "$1" | grep -oE '[0-9]+(\.[0-9]+)*(-r[0-9]+)?'
}

install_pkg() {
    PKG="$(find_latest "$1")" || { echo -e "\n${RED}Файл не найден!${NC}\n"; exit 1; }

    VER="$(get_pkg_ver "$PKG")"

    echo -e "\n${CYAN}→ Пакет:${NC} $PKG"
    echo -e "${CYAN}→ Версия:${NC} $VER"
    echo -e "${CYAN}→ Скачивание...${NC}"

    wget "$RAW_BASE/$PKG" -O "$TMP/$PKG" || {
        echo -e "\n${RED}Ошибка скачивания!${NC}\n"
        exit 1
    }

    echo -e "${CYAN}→ Установка...${NC}"
    opkg install "$TMP/$PKG" || {
        echo -e "\n${RED}Ошибка установки!${NC}\n"
        exit 1
    }
}

# ---------- STATUS HELPERS ----------

zap_inst="$(get_installed_ver zapret2)"
zap_latest_file="$(find_latest zapret2_)"
zap_latest_ver="$(get_pkg_ver "$zap_latest_file")"

zero_inst="$(get_installed_ver zeroblock)"
zero_latest_file="$(find_latest zeroblock)"
zero_latest_ver="$(get_pkg_ver "$zero_latest_file")"

is_zap_installed() { [ -n "$zap_inst" ]; }
is_zero_installed() { [ -n "$zero_inst" ]; }

is_zap_update() { is_zap_installed && [ "$zap_inst" != "$zap_latest_ver" ]; }
is_zero_update() { is_zero_installed && [ "$zero_inst" != "$zero_latest_ver" ]; }

# ---------- ZAPRET ----------

install_zapret() {
    mkdir -p "$TMP"
    opkg update
    install_pkg "zapret2_"
    install_pkg "luci-app-zapret2_"

    wget -qO /opt/zapret2/ipset/zapret_hosts_user_exclude.txt \
    https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt

    sed -i "/config strategy 'default'/,/config /s/option enabled '0'/option enabled '1'/" /etc/config/zapret2
    /etc/init.d/zapret2 restart

    rm -rf "$TMP"
    echo -e "\n${GREEN}✔ Zapret установлен${NC}\n"
}

remove_zapret() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zapret2 zapret2
    rm -f /etc/config/zapret2
    rm -rf /opt/zapret2
    echo -e "\n${GREEN}✔ Zapret удалён${NC}\n"
}

update_zapret() {
    echo -e "\n${YELLOW}→ Обновление Zapret...${NC}"
    install_zapret
}

# ---------- ZERO ----------

install_zeroblock() {
    mkdir -p "$TMP"
    opkg update
    install_pkg "zeroblock"
    install_pkg "luci-app-zeroblock"
    rm -rf "$TMP"
    echo -e "\n${GREEN}✔ Zeroblock установлен${NC}\n"
}

remove_zeroblock() {
    opkg --force-removal-of-dependent-packages --autoremove remove luci-app-zeroblock zeroblock
    rm -f /etc/config/zeroblock
    rm -rf /opt/zeroblock
    echo -e "\n${GREEN}✔ Zeroblock удалён${NC}\n"
}

update_zeroblock() {
    echo -e "\n${YELLOW}→ Обновление Zeroblock...${NC}"
    install_zeroblock
}

# ---------- ROUTERICH ----------

add_routerich() {
    sed -i 's/option check_signature/# option check_signature/' /etc/opkg.conf
    echo 'src/gz routerich https://github.com/routerich/packages.routerich/raw/24.10.5/routerich' > /etc/opkg/customfeeds.conf
    opkg update
    echo -e "\n${GREEN}✔ Routerich добавлен${NC}\n"
}

remove_routerich() {
    rm -f /etc/opkg/customfeeds.conf
    sed -i 's/# option check_signature/option check_signature/' /etc/opkg.conf
    opkg update
    echo -e "\n${GREEN}✔ Routerich удалён${NC}\n"
}

# ---------- MENU ----------

menu() {
    clear

echo "███████╗██████╗ ██████╗ "
echo "╚══███╔╝╚════██╗██╔══██╗"
echo "  ███╔╝  █████╔╝██████╔╝"
echo " ███╔╝  ██╔═══╝ ██╔══██╗"
echo "███████╗███████╗██║  ██║"
echo "╚══════╝╚══════╝╚═╝  ╚═╝"

echo

echo -e "${CYAN}Zapret:${NC}"
echo -e "Установлено: ${YELLOW}${zap_inst:-нет}${NC}"
echo -e "Последняя версия: ${YELLOW}${zap_latest_ver}${NC}"

echo -e "${CYAN}Zeroblock:${NC}"
echo -e "Установлено: ${YELLOW}${zero_inst:-нет}${NC}"
echo -e "Последняя версия: ${YELLOW}${zero_latest_ver}${NC}"

echo

# ---- ZAPRET MENU ----
if is_zap_installed; then
    Z1="${YELLOW}Удалить${NC}"
else
    Z1="${GREEN}Установить${NC}"
fi

if is_zap_update; then
    Z3="${GREEN}Обновить${NC}"
else
    Z3="${CYAN}Актуально${NC}"
fi

# ---- ZERO MENU ----
if is_zero_installed; then
    Z2="${YELLOW}Удалить${NC}"
else
    Z2="${GREEN}Установить${NC}"
fi

if is_zero_update; then
    Z4="${GREEN}Обновить${NC}"
else
    Z4="${CYAN}Актуально${NC}"
fi

echo -e "${CYAN}1) Zapret → $Z1 | $Z3${NC}"
echo -e "${CYAN}2) Zeroblock → $Z2 | $Z4${NC}"
echo -e "${CYAN}3) Routerich добавить/удалить${NC}"
echo -e "${CYAN}Enter) Выход${NC}"

echo -en "${YELLOW}Выбор:${NC} "
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
        if is_routerich_added; then remove_routerich; else add_routerich; fi
    ;;
    *)
        exit 0
    ;;
esac

echo -ne "\nEnter..."
read d
}

while true; do
    menu
done
