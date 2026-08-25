#!/bin/sh
# lib/mihomo.sh — установка ядра Mihomo + служба + страница LuCI

MIHOMO_INSTALL_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/bin/mihomo"
MIHOMO_ASSETS="${ASSETS_DIR}/mihomo"

# Проверка достаточности свободного места под /tmp и /usr(root).
check_disk_space() {
    req_tmp_kb=16000
    req_root_kb=18000

    avail_tmp_kb=$(df -k /tmp | awk 'NR==2 {print $4}')
    if [ "$avail_tmp_kb" -lt "$req_tmp_kb" ]; then
        log_error "Недостаточно места в /tmp: доступно $((avail_tmp_kb/1024)) MB, требуется $((req_tmp_kb/1024)) MB"
        return 1
    fi

    install_dir_path=$(dirname "$MIHOMO_BIN")
    avail_root_kb=$(df -k "$install_dir_path" | awk 'NR==2 {print $4}')
    if [ "$avail_root_kb" -ge "$req_root_kb" ]; then
        return 0
    fi

    log_error "Недостаточно места на диске: доступно $((avail_root_kb/1024)) MB, требуется $((req_root_kb/1024)) MB"
    if [ ! -f "$MIHOMO_BIN" ]; then
        log_warn "Старая версия не найдена. Удалите лишние пакеты вручную."
        return 1
    fi

    log_warn "Найдена установленная версия: $MIHOMO_BIN"
    printf "Удалить старую версию для освобождения места? [y/+/д или n/-/н]: "
    read -r response
    case "$response" in
        [yY+дД]*)
            rm -f "$MIHOMO_BIN"
            avail_root_kb=$(df -k "$install_dir_path" | awk 'NR==2 {print $4}')
            if [ "$avail_root_kb" -lt "$req_root_kb" ]; then
                log_error "Места всё равно недостаточно после удаления."
                return 1
            fi
            ;;
        *)
            log_warn "Установка отменена."
            return 1
            ;;
    esac
}

# Скачивание и установка бинарника ядра.
install_mihomo_binary() {
    [ -f "/etc/init.d/mihomo" ] && /etc/init.d/mihomo stop 2>/dev/null || true

    mihomo_arch=$(detect_mihomo_arch)
    echo "Архитектура системы: $(uname -m) -> выбран файл: $mihomo_arch"
    echo "$mihomo_arch" > /etc/mihomo/.arch

    echo "Получение номера последней версии"
    release_tag=$(get_latest_tag "MetaCubeX/mihomo")
    if [ -z "$release_tag" ]; then
        log_error "Не удалось определить версию. Проверьте интернет."
        return 1
    fi
    echo "Последняя версия: $release_tag"

    filename="mihomo-linux-${mihomo_arch}-${release_tag}.gz"
    url="https://github.com/MetaCubeX/mihomo/releases/download/${release_tag}/${filename}"
    tmp_file="/tmp/mihomo.gz"

    log_online "Скачивание архива $filename"
    log_online "$url"
    if ! download_file "$tmp_file" "$url"; then
        log_error "Ошибка скачивания! Проверьте, существует ли файл $filename в релизах."
        return 1
    fi

    echo "Распаковка архива"
    if ! gunzip -c "$tmp_file" > "$MIHOMO_BIN" 2>/dev/null; then
        log_error "Ошибка распаковки архива"
        rm -f "$tmp_file"
        return 1
    fi
    chmod +x "$MIHOMO_BIN"
    rm -f "$tmp_file"

    echo "Проверка работы ядра Mihomo"
    if ! "$MIHOMO_BIN" -v >/dev/null 2>&1; then
        log_error "Ядро не запускается! Возможно, выбрана неверная архитектура."
        return 1
    fi
}

# Установка config.yaml — не перезаписывает существующий рабочий конфиг.
install_mihomo_config() {
    config_file="/etc/mihomo/config.yaml"

    if [ -f "$config_file" ] && grep -q "mixed-port: 7890" "$config_file"; then
        echo "Использование существующей конфигурации"
        return 0
    fi

    if [ -f "$config_file" ]; then
        log_warn "Конфигурация найдена, но без 'mixed-port: 7890'. Создаём резервную копию"
        cp "$config_file" "${config_file}.bak"
    fi

    echo "Создание новой конфигурации /etc/mihomo/config.yaml..."
    cp "$MIHOMO_ASSETS/configs/config.yaml" "$config_file"
}

install_mihomo_service() {
    echo "Создание службы /etc/init.d/mihomo"
    cp "$MIHOMO_ASSETS/mihomo.init" /etc/init.d/mihomo
    chmod +x /etc/init.d/mihomo
    /etc/init.d/mihomo enable || log_warn "Не удалось включить автозапуск"
}

install_mihomo_luci_menu() {
    echo "Настройка страницы LuCI для управления Mihomo"
    mkdir -p /usr/share/luci/menu.d /usr/share/rpcd/acl.d
    cp "$MIHOMO_ASSETS/luci-app-mihomo.json" /usr/share/luci/menu.d/luci-app-mihomo.json
    cp "$MIHOMO_ASSETS/luci-app-mihomo.acl.json" /usr/share/rpcd/acl.d/luci-app-mihomo.json
}

# Скачивание ACE Editor (пробуем несколько CDN по очереди).
install_ace_editor() {
    ace_path="$1"
    mkdir -p "$ace_path"

    echo "Определение актуальной версии ACE Editor"
    latest_ace_ver=$(curl -s "https://api.cdnjs.com/libraries/ace" | grep -o '"version":"[^"]*"' | cut -d'"' -f4 | head -1)
    if [ -z "$latest_ace_ver" ]; then
        log_warn "cdnjs API недоступен, пробуем GitHub API"
        latest_ace_ver=$(curl -s "https://api.github.com/repos/ajaxorg/ace/releases/latest" | grep -o '"tag_name": *"[^"]*"' | cut -d'"' -f4 | sed 's/^v//' | head -1)
    fi
    if [ -z "$latest_ace_ver" ]; then
        log_warn "Используем фиксированную версию ACE Editor"
        latest_ace_ver="1.43.3"
    else
        echo "Актуальная версия ACE Editor: $latest_ace_ver"
    fi

    cdnjs_ace_ver="1.43.6"
    log_online "Скачивание файлов для ACE Editor $latest_ace_ver:"
    for file in ace.js theme-merbivore_soft.js theme-tomorrow.js mode-yaml.js worker-yaml.js; do
        dest="${ace_path}/${file}"
        log_online "Скачивание $file"
        if ! download_file "$dest" \
            "https://cdn.jsdelivr.net/npm/ace-builds@${latest_ace_ver}/src-min-noconflict/${file}" \
            "https://raw.githubusercontent.com/ajaxorg/ace-builds/master/src-min-noconflict/${file}" \
            "https://cdnjs.cloudflare.com/ajax/libs/ace/${cdnjs_ace_ver}/${file}"; then
            log_error "Не удалось скачать $file ни из одного источника."
            return 1
        fi
    done
}

install_mihomo_luci_page() {
    view_path="/www/luci-static/resources/view/mihomo"
    install_ace_editor "$view_path/ace" || return 1

    echo "Создание config.js"
    cp "$MIHOMO_ASSETS/config.js" "$view_path/config.js"
}

install_mihomo() {
    check_disk_space || return 1
    mkdir -p "$MIHOMO_INSTALL_DIR" \
             /etc/mihomo/proxy-providers \
             /etc/mihomo/rule-providers \
             /etc/mihomo/rule-files

    install_mihomo_binary       || return 1
    install_mihomo_config       || return 1
    install_mihomo_service      || return 1
    install_mihomo_luci_menu    || return 1
    install_mihomo_luci_page    || return 1
}

# Установка веб-панели Zashboard в /etc/mihomo/ui
install_zashboard_ui() {
    log_online "Установка панели Zashboard для Mihomo"
    tmp_zip="/tmp/zashboard.zip"
    tmp_dir="/tmp/zashboard"
    dest_dir="/etc/mihomo/ui"
    url="https://github.com/Zephyruso/zashboard/releases/latest/download/dist-cdn-fonts.zip"

    if ! download_file "$tmp_zip" "$url"; then
        log_error "Ошибка скачивания WEB UI!"
        rm -f "$tmp_zip"
        return 1
    fi

    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"
    if ! unzip -oq "$tmp_zip" -d "$tmp_dir"; then
        log_error "Ошибка распаковки WEB UI!"
        rm -rf "$tmp_zip" "$tmp_dir"
        return 1
    fi

    rm -rf "$dest_dir"; mkdir -p "$dest_dir"
    if [ -d "$tmp_dir/dist" ]; then
        cp -r "$tmp_dir/dist/." "$dest_dir/"
    else
        cp -r "$tmp_dir/." "$dest_dir/"
    fi

    rm -rf "$tmp_zip" "$tmp_dir"
}
