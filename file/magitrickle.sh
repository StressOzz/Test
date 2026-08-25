#!/bin/sh
# lib/magitrickle.sh — установка MagiTrickle + страница LuCI

MAGITRICKLE_ASSETS="${ASSETS_DIR}/magitrickle"
MAGITRICKLE_CONFIG_URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/files/MagiTrickle/configAD.yaml"

install_magitrickle() {
    pkg_installer="opkg install"; pkg_ext="ipk"; pkg_suf=""
    if command -v apk >/dev/null 2>&1; then
        pkg_installer="apk add --allow-untrusted"; pkg_ext="apk"; pkg_suf="r"
    fi

    mt_arch=$(grep "^OPENWRT_ARCH=" /etc/os-release | cut -d'"' -f2)
    mt_version=$(get_latest_tag "MagiTrickle/MagiTrickle")
    mt_version="${mt_version#v}"

    url="https://github.com/MagiTrickle/MagiTrickle/releases/download/${mt_version}/magitrickle_${mt_version}-${pkg_suf}1_openwrt_${mt_arch}.${pkg_ext}"
    file="/tmp/$(basename "$url")"

    echo -e "Скачиваем и устанавливаем:\n${CYAN}$url${NC}"
    if ! download_file "$file" "$url"; then
        log_error "Ошибка скачивания MagiTrickle"
        return 1
    fi
    if ! $pkg_installer "$file" >/dev/null 2>&1; then
        log_error "Ошибка установки MagiTrickle"
        rm -f "$file"
        return 1
    fi
    rm -f "$file"

    echo "Создание страницы MagiTrickle в LuCI"
    mkdir -p /www/luci-static/resources/view/magitrickle
    cp "$MAGITRICKLE_ASSETS/magitrickle.js" /www/luci-static/resources/view/magitrickle/magitrickle.js
    cp "$MAGITRICKLE_ASSETS/luci-app-magitrickle.json" /usr/share/luci/menu.d/luci-app-magitrickle.json

    rm -rf /tmp/luci-indexcache /tmp/luci-modulecache/
}

# Загрузка списка доменов/правил для MagiTrickle и запуск службы.
configure_magitrickle() {
    config_path="/etc/magitrickle/state/config.yaml"
    echo "Установка списка для MagiTrickle"
    if ! download_file "$config_path" "$MAGITRICKLE_CONFIG_URL"; then
        log_warn "Не удалось скачать список для MagiTrickle!"
    fi

    /etc/init.d/magitrickle enable  >/dev/null 2>&1
    /etc/init.d/magitrickle reload  >/dev/null 2>&1
    /etc/init.d/magitrickle restart >/dev/null 2>&1
}
