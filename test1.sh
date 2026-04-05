```sh
#!/bin/sh
#===============================================================================
#  Mihomo + MagiTrickle Installer for OpenWRT
#  Author: StressOzz Remix | Optimized Edition v2.1.1
#  License: MIT
#===============================================================================

set -eu

#-------------------------------------------------------------------------------
#  GLOBAL CONFIGURATION
#-------------------------------------------------------------------------------
readonly MIHOMO_DIR="/etc/mihomo"
readonly MIHOMO_BIN="/usr/bin/mihomo"
readonly MAGITRICKLE_CFG="/etc/magitrickle/state/config.yaml"
readonly LUCI_MIHOMO_VIEW="/www/luci-static/resources/view/mihomo"
readonly LUCI_MT_VIEW="/www/luci-static/resources/view/magitrickle"

# Colors
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_RED='\033[31m'
C_GREEN='\033[32m'
C_YELLOW='\033[33m'
C_BLUE='\033[34m'
C_CYAN='\033[36m'
C_MAGENTA='\033[35m'

# Progress tracking
STEP_TOTAL=5
STEP_CURRENT=0
PKG_MGR=""

#-------------------------------------------------------------------------------
#  LOGGING FUNCTIONS
#-------------------------------------------------------------------------------
log()      { printf "${C_WHITE}[·]${C_RESET} %s\n" "$*"; }
info()     { printf "${C_GREEN}[✓]${C_RESET} %s\n" "$*"; }
warn()     { printf "${C_YELLOW}[!]${C_RESET} %s\n" "$*" >&2; }
error()    { printf "${C_RED}[✗]${C_RESET} %s\n" "$*" >&2; }
success()  { printf "${C_GREEN}✨ ${C_BOLD}%s${C_RESET}\n" "$*"; }
header()   { printf "\n${C_CYAN}━━━ ${C_BOLD}%s${C_RESET} ${C_CYAN}━━━${C_RESET}\n" "$*"; }
subheader(){ printf "${C_BLUE}➜ ${C_RESET}%s\n" "$*"; }

step() {
    STEP_CURRENT=$((STEP_CURRENT + 1))
    printf "\n${C_MAGENTA}▌${C_RESET} ${C_BOLD}Шаг ${STEP_CURRENT}/${STEP_TOTAL}:${C_RESET} %s\n" "$*"
}

die() {
    error "$*"
    exit 1
}

#-------------------------------------------------------------------------------
#  SYSTEM UTILITIES
#-------------------------------------------------------------------------------
init_pkgmgr() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MGR="opkg"
    else
        die "Не найдена система пакетов (apk/opkg)"
    fi
}

pkg_update() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk update -q 2>/dev/null || true
    else
        opkg update -q 2>/dev/null || true
    fi
}

pkg_install() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk add -q "$@" 2>/dev/null
    else
        opkg install -q "$@" 2>/dev/null
    fi
}

pkg_remove() {
    if [ "$PKG_MGR" = "apk" ]; then
        apk del -q "$@" 2>/dev/null || true
    else
        opkg remove -q "$@" 2>/dev/null || true
    fi
}

gh_latest() {
    local repo="$1"
    local pattern="${2:-[0-9]+\\.[0-9]+\\.[0-9]+}"
    curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | grep -oE "$pattern" | head -1
}

fetch_file() {
    local url="$1"
    local dest="$2"
    local retry=0
    local max_retry=3
    
    while [ $retry -lt $max_retry ]; do
        if curl -Lf --connect-timeout 15 -sS -o "$dest" "$url" 2>/dev/null && [ -s "$dest" ]; then
            return 0
        fi
        retry=$((retry + 1))
        sleep 2
    done
    return 1
}

detect_mihomo_arch() {
    local arch="$(uname -m)"
    case "$arch" in
        x86_64)        echo "amd64" ;;
        i?86)          echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*)        echo "armv7" ;;
        armv5*|armv4*) echo "armv5" ;;
        mips*)
            local endian fpu float
            endian=$(hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null || echo "0")
            fpu=$(grep -c "FPU" /proc/cpuinfo 2>/dev/null || echo "0")
            float="softfloat"
            [ "$fpu" -gt 0 ] && float="hardfloat"
            [ "$endian" = "1" ] && echo "mipsle-${float}" || echo "mips-${float}"
            ;;
        riscv64) echo "riscv64" ;;
        *) die "Неподдерживаемая архитектура: $arch" ;;
    esac
}

check_disk_space() {
    local path="$1"
    local required_kb="$2"
    local avail
    avail=$(df -k "$path" 2>/dev/null | awk 'NR==2{print $4}')
    if [ "$avail" -lt "$required_kb" ]; then
        error "Недостаточно места в $path: $((avail/1024))MB (требуется $((required_kb/1024))MB)"
        return 1
    fi
    return 0
}

#-------------------------------------------------------------------------------
#  MODULE: Dependencies
#-------------------------------------------------------------------------------
install_dependencies() {
    step "Установка зависимостей"
    subheader "Обновление индексов пакетов..."
    pkg_update || warn "Предупреждение при обновлении пакетов"
    
    subheader "Установка компонентов..."
    local deps="ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl"
    [ "$PKG_MGR" = "opkg" ] && deps="$deps libcurl4 ca-bundle"
    
    if pkg_install $deps; then
        info "Зависимости установлены успешно"
    else
        die "Не удалось установить зависимости"
    fi
}

#-------------------------------------------------------------------------------
#  MODULE: Mihomo Core
#-------------------------------------------------------------------------------
install_mihomo_core() {
    step "Установка ядра Mihomo"
    
    # Проверка места на диске
    check_disk_space /tmp 16000 || die "Недостаточно места в /tmp"
    check_disk_space / 18000 || die "Недостаточно места в корне"
    
    # Остановка службы если запущена
    [ -f /etc/init.d/mihomo ] && /etc/init.d/mihomo stop 2>/dev/null || true
    
    # Определение архитектуры
    local arch
    arch="$(detect_mihomo_arch)"
    subheader "Архитектура: $(uname -m) → ${arch}"
    
    # Подготовка директорий
    mkdir -p "${MIHOMO_DIR}"/{proxy-providers,rule-providers,rule-files,UI}
    echo "$arch" > "${MIHOMO_DIR}/.arch"
    
    # Получение последней версии
    subheader "Поиск актуальной версии..."
    local version
    version="$(gh_latest "MetaCubeX/mihomo" 'v[0-9]+\\.[0-9]+\\.[0-9]+')"
    [ -z "$version" ] && die "Не удалось получить версию Mihomo"
    info "Найдена версия: ${version}"
    
    # Загрузка бинарника
    local filename="mihomo-linux-${arch}-${version}.gz"
    local url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}"
    local tmp="/tmp/mihomo.gz"
    
    subheader "Загрузка ${filename}..."
    if ! fetch_file "$url" "$tmp"; then
        die "Ошибка загрузки ядра Mihomo"
    fi
    
    # Установка
    subheader "Распаковка и установка..."
    if ! gunzip -c "$tmp" > "$MIHOMO_BIN" 2>/dev/null; then
        rm -f "$tmp"
        die "Ошибка распаковки"
    fi
    chmod +x "$MIHOMO_BIN"
    rm -f "$tmp"
    
    # Проверка работоспособности
    if ! "$MIHOMO_BIN" -v >/dev/null 2>&1; then
        die "Ядро не проходит проверку целостности"
    fi
    info "Ядро установлено: $("$MIHOMO_BIN" -v 2>&1 | head -1)"
    
    # Создание init-скрипта
    subheader "Настройка службы..."
    cat > /etc/init.d/mihomo << 'MHSERVICE'
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1
BIN="/usr/bin/mihomo"
DIR="/etc/mihomo"
CONF="${DIR}/config.yaml"

start_service() {
    [ -x "$BIN" ] || return 1
    [ -s "$CONF" ] || return 1
    procd_open_instance
    procd_set_param command "$BIN" -d "$DIR" -f "$CONF"
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_set_param respawn
    procd_close_instance
}

service_triggers() {
    procd_add_reload_trigger "mihomo"
}
MHSERVICE
    chmod +x /etc/init.d/mihomo
    /etc/init.d/mihomo enable 2>/dev/null || true
    
    info "Служба Mihomo настроена"
}

#-------------------------------------------------------------------------------
#  MODULE: Hev-Socks5-Tunnel
#-------------------------------------------------------------------------------
install_hev_tunnel() {
    step "Установка Hev-Socks5-Tunnel"
    
    subheader "Установка пакета..."
    pkg_install hev-socks5-tunnel || warn "Пакет hev-socks5-tunnel может быть недоступен"
    
    # Конфигурация
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml << 'HEVCFG'
tunnel:
  name: Mihomo
  mtu: 8500
  multi-queue: false
  ipv4: 198.18.0.1
socks5:
  port: 7890
  address: 127.0.0.1
  udp: 'udp'
HEVCFG
    chmod 600 /etc/hev-socks5-tunnel/main.yml
    
    # Очистка старых UCI настроек
    subheader "Очистка старых конфигураций..."
    uci delete network.Mihomo 2>/dev/null || true
    
    local section
    for section in $(uci show firewall 2>/dev/null | grep -E "\.(name|src|dest)='Mihomo'" | cut -d= -f1 | cut -d. -f1 | sort -u); do
        uci delete "$section" 2>/dev/null || true
    done
    uci commit firewall 2>/dev/null || true
    
    # Настройка сервиса
    subheader "Конфигурация hev-socks5-tunnel..."
    uci set hev-socks5-tunnel.config.enabled='1' 2>/dev/null || true
    uci set hev-socks5-tunnel.config.configfile='/etc/hev-socks5-tunnel/main.yml' 2>/dev/null || true
    uci commit hev-socks5-tunnel 2>/dev/null || true
    /etc/init.d/hev-socks5-tunnel restart >/dev/null 2>&1 || true
    sleep 2
    
    # Сетевой интерфейс
    subheader "Настройка сети..."
    if ! uci get network.Mihomo >/dev/null 2>&1; then
        uci add network interface
    fi
    uci set network.Mihomo.proto='none'
    uci set network.Mihomo.device='Mihomo'
    uci commit network
    /etc/init.d/network reload >/dev/null 2>&1
    
    # Firewall
    subheader "Правила фаервола..."
    local zone_fwd
    zone_fwd="$(uci add firewall zone)"
    uci set "firewall.${zone_fwd}.name=Mihomo"
    uci set "firewall.${zone_fwd}.input=REJECT"
    uci set "firewall.${zone_fwd}.output=REJECT"
    uci set "firewall.${zone_fwd}.forward=REJECT"
    uci set "firewall.${zone_fwd}.masq=1"
    uci set "firewall.${zone_fwd}.mtu_fix=1"
    uci add_list "firewall.${zone_fwd}.network=Mihomo"
    
    local fwd_rule
    fwd_rule="$(uci add firewall forwarding)"
    uci set "firewall.${fwd_rule}.src=lan"
    uci set "firewall.${fwd_rule}.dest=Mihomo"
    
    uci commit firewall
    /etc/init.d/firewall restart >/dev/null 2>&1
    
    info "Hev-Socks5-Tunnel настроен"
}

#-------------------------------------------------------------------------------
#  MODULE: MagiTrickle
#-------------------------------------------------------------------------------
install_magitrickle_app() {
    step "Установка MagiTrickle"
    
    # Получение версий
    local mt_ver mod_ver arch
    mt_ver="$(gh_latest "MagiTrickle/MagiTrickle")"
    mod_ver="$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/badigit/MagiTrickle_mod_badigit/releases/latest" 2>/dev/null | sed -E 's#.*/tag/v?##')"
    arch="$(grep '^OPENWRT_ARCH=' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'unknown')"
    
    # Меню выбора
    printf "\n${C_YELLOW}╭─ Выбор версии MagiTrickle ─────────────${C_RESET}\n"
    printf "${C_YELLOW}│${C_RESET}  ${C_CYAN}1)${C_RESET} Оригинальный ${C_GREEN}v${mt_ver}${C_RESET}\n"
    printf "${C_YELLOW}│${C_RESET}  ${C_CYAN}2)${C_RESET} Mod by badigit ${C_GREEN}v${mod_ver}${C_RESET}\n"
    printf "${C_YELLOW}╰─${C_RESET} Введите номер [1]: "
    
    local choice
    read -r choice 2>/dev/null || choice="1"
    
    local base_url pkg_ext
    case "$choice" in
        2)
            base_url="https://github.com/badigit/MagiTrickle_mod_badigit/releases/download/${mod_ver}"
            info "Выбран: MagiTrickle mod"
            ;;
        *)
            base_url="https://github.com/MagiTrickle/MagiTrickle/releases/download/${mt_ver}"
            info "Выбран: Оригинальный MagiTrickle"
            ;;
    esac
    
    [ "$PKG_MGR" = "apk" ] && pkg_ext="apk" || pkg_ext="ipk"
    
    # Бэкап конфигурации
    [ -f "$MAGITRICKLE_CFG" ] && cp "$MAGITRICKLE_CFG" "/tmp/mt_backup_$(date +%s).yaml"
    
    # Удаление старой версии
    pkg_remove magitrickle
    
    # Поиск и загрузка пакета
    subheader "Поиск пакета..."
    local pkg_list tmp_pkg actual_pkg
    pkg_list="$(curl -Ls "$base_url" 2>/dev/null || echo "")"
    actual_pkg="$(echo "$pkg_list" | grep -oE "magitrickle_[^\"' ]+\\.${pkg_ext}" | head -1)"
    
    if [ -z "$actual_pkg" ]; then
        die "Не удалось найти пакет MagiTrickle для скачивания"
    fi
    
    tmp_pkg="/tmp/magitrickle.${pkg_ext}"
    subheader "Загрузка ${actual_pkg}..."
    
    if ! fetch_file "${base_url}/${actual_pkg}" "$tmp_pkg"; then
        die "Ошибка загрузки MagiTrickle"
    fi
    
    # Установка
    subheader "Установка пакета..."
    if [ "$PKG_MGR" = "apk" ]; then
        apk add --allow-untrusted "$tmp_pkg" >/dev/null 2>&1 || die "Ошибка установки (apk)"
    else
        opkg install "$tmp_pkg" >/dev/null 2>&1 || die "Ошибка установки (opkg)"
    fi
    rm -f "$tmp_pkg"
    
    # Конфигурация
    subheader "Применение конфигурации..."
    local cfg_url="https://raw.githubusercontent.com/StressOzz/Use_WARP_on_OpenWRT/refs/heads/main/files/MagiTrickle/configAD.yaml"
    mkdir -p "$(dirname "$MAGITRICKLE_CFG")"
    
    if ! fetch_file "$cfg_url" "$MAGITRICKLE_CFG"; then
        warn "Не удалось загрузить конфиг, используется дефолтный"
    fi
    
    # Запуск службы
    /etc/init.d/magitrickle enable >/dev/null 2>&1
    /etc/init.d/magitrickle restart >/dev/null 2>&1
    
    # LuCI интеграция
    subheader "Интеграция с LuCI..."
    mkdir -p "$LUCI_MT_VIEW" /usr/share/luci/menu.d
    
    cat > "${LUCI_MT_VIEW}/magitrickle.js" << 'MTJS'
'use strict';
'require view';
return view.extend({
    render: function() {
        var ip = window.location.hostname;
        var url = 'http://' + ip + ':8080';
        return E('div', {
            style: 'width:100%;height:92vh;margin:-20px -20px 0 -20px;overflow:hidden;'
        }, E('iframe', {
            src: url,
            style: 'width:100%;height:100%;border:none;'
        }));
    }
});
MTJS
    
    cat > /usr/share/luci/menu.d/luci-app-magitrickle.json << 'MTMENU'
{
    "admin/services/magitrickle": {
        "title": "MagiTrickle",
        "order": 60,
        "action": {
            "type": "view",
            "path": "magitrickle/magitrickle"
        }
    }
}
MTMENU
    
    info "MagiTrickle установлен и настроен"
}

#-------------------------------------------------------------------------------
#  MODULE: LuCI Interface for Mihomo
#-------------------------------------------------------------------------------
setup_luci_interface() {
    subheader "Настройка LuCI интерфейса для Mihomo..."
    
    mkdir -p "${LUCI_MIHOMO_VIEW}/ace"
    mkdir -p /usr/share/luci/menu.d
    mkdir -p /usr/share/rpcd/acl.d
    
    # Menu entry
    cat > /usr/share/luci/menu.d/luci-app-mihomo.json << 'MENUEOF'
{
    "admin/services/mihomo": {
        "title": "Mihomo",
        "order": 60,
        "action": {
            "type": "view",
            "path": "mihomo/config"
        }
    }
}
MENUEOF
    
    # ACL rules
    cat > /usr/share/rpcd/acl.d/luci-app-mihomo.json << 'ACLEOF'
{
    "luci-app-mihomo": {
        "description": "Mihomo management",
        "read": {
            "file": {
                "/etc/mihomo/config.yaml": ["read"],
                "/etc/mihomo/rule-files/": ["list"]
            }
        },
        "write": {
            "file": {
                "/etc/mihomo/config.yaml": ["write"],
                "/usr/bin/mihomo": ["exec"],
                "/etc/init.d/mihomo": ["exec"]
            }
        }
    }
}
ACLEOF
    
    # ACE Editor assets
    subheader "Загрузка ACE Editor..."
    local ace_ver
    ace_ver="$(curl -s https://api.cdnjs.com/libraries/ace 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 | head -1)"
    [ -z "$ace_ver" ] && ace_ver="1.43.3"
    
    local ace_files="ace.js theme-merbivore_soft.js theme-tomorrow.js mode-yaml.js worker-yaml.js"
    for f in $ace_files; do
        if ! fetch_file "https://cdn.jsdelivr.net/npm/ace-builds@${ace_ver}/src-min-noconflict/${f}" "${LUCI_MIHOMO_VIEW}/ace/${f}"; then
            fetch_file "https://cdnjs.cloudflare.com/ajax/libs/ace/${ace_ver}/${f}" "${LUCI_MIHOMO_VIEW}/ace/${f}" || \
                warn "Не загружен: $f"
        fi
    done
    
    # Main view file - external file approach for reliability
    subheader "Создание интерфейса..."
    
    # Write the JavaScript view file
    cat > "${LUCI_MIHOMO_VIEW}/config.js" << 'LUCIVIEW'
'use strict';
'require view';
'require fs';
'require ui';
'require rpc';

var ACE_DIR = '/luci-static/resources/view/mihomo/ace/';
var MAIN_CONFIG = '/etc/mihomo/config.yaml';
var RULE_DIR = '/etc/mihomo/rule-files/';
var editor = null;
var currentFile = MAIN_CONFIG;
var cachedRuleFiles = [];
var mainConfigContent = '';

var callServiceList = rpc.declare({
    object: 'service',
    method: 'list',
    params: ['name']
});

function escapeHtml(text) {
    if (typeof text !== 'string') return text;
    return text.replace(/[&<>"']/g, function(m) {
        return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m];
    });
}

function validatePath(path, base) {
    if (!path || typeof path !== 'string') return false;
    if (path.indexOf('..') !== -1 || path.indexOf('\0') !== -1) return false;
    var resolved = path.replace(/\/+/g, '/');
    return resolved.indexOf(base) === 0 && resolved.length <= 1024;
}

function validateFilename(name) {
    if (!name || typeof name !== 'string') return false;
    return /^[a-zA-Z0-9._-]+$/.test(name) && name.length <= 255;
}

function sanitizeName(n) {
    return n ? n.replace(/[<>"'`]/g, '') : '';
}

function loadScript(src) {
    return new Promise(function(resolve, reject) {
        var script = document.createElement('script');
        script.src = src;
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
    });
}

function detectRuleType(line) {
    line = line.trim();
    if (line.indexOf(':') !== -1 && !line.match(/http(s)?:\/\//)) return 'IP-CIDR6';
    if (/^\d{1,3}(\.\d{1,3}){3}\/?\d*$/.test(line)) return 'IP-CIDR';
    if (line.startsWith('.')) return 'DOMAIN-WILDCARD';
    var dots = (line.match(/\./g) || []).length;
    if (dots >= 2) return 'DOMAIN';
    if (dots === 1) return 'DOMAIN-SUFFIX';
    return 'DOMAIN-KEYWORD';
}

function isDarkMode() {
    try {
        var rgb = window.getComputedStyle(document.body).backgroundColor.match(/\d+/g);
        if (rgb) {
            var luma = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2];
            return luma < 128;
        }
    } catch(e) {}
    return false;
}

return view.extend({
    currentVersion: '?',
    latestVersion: null,
    
    getVersion: function() {
        return fs.stat('/usr/bin/mihomo').then(function() {
            return fs.exec('/usr/bin/mihomo', ['--v']);
        }).then(function(res) {
            var m = (res.stdout || '').match(/v(\d+\.\d+\.\d+)/);
            return m ? m[0] : '?';
        }).catch(function() { return '?'; });
    },
    
    checkUpdates: function(manual) {
        var self = this;
        if (manual) ui.showModal(null, [E('p', {'class':'spinning'}, _('Проверка'))]);
        
        var cmd = 'wget -qO- https://api.github.com/repos/MetaCubeX/mihomo/releases/latest 2>/dev/null | grep tag_name | sed "s/.*v\\([0-9.]*\\).*/v\\1/"';
        
        fs.exec('/bin/sh', ['-c', cmd]).then(function(res) {
            if (manual) ui.hideModal();
            var lv = (res.stdout || '').trim();
            if (!lv.match(/^v\d+\.\d+\.\d+$/)) return;
            self.latestVersion = lv;
            self.renderUpdateStatus();
        }).catch(function(e) {
            if (manual) {
                ui.hideModal();
                ui.addNotification(null, E('p', e.message), 'error');
            }
        });
    },
    
    renderUpdateStatus: function() {
        var el = document.getElementById('mihomo-ver-info');
        var btn = document.getElementById('mihomo-update-btn');
        if (!el || !btn) return;
        
        if (this.latestVersion === this.currentVersion) {
            el.textContent = _('(актуально)');
            el.style.color = '#5cb85c';
            btn.textContent = _('Проверить');
            btn.className = 'btn cbi-button-neutral';
            btn.onclick = function() { location.reload(); };
        } else {
            el.textContent = _('(доступно: %s)').format(this.latestVersion);
            el.style.color = '#f39c12';
            btn.textContent = _('Обновить');
            btn.className = 'btn cbi-button-action';
            btn.onclick = ui.createHandlerFn(this, 'doUpdate');
        }
        el.style.display = 'inline';
    },
    
    doUpdate: function() {
        if (!this.latestVersion) return;
        var self = this;
        var arch = 'arm64';
        var url = 'https://github.com/MetaCubeX/mihomo/releases/download/' + this.latestVersion + '/mihomo-linux-' + arch + '-' + this.latestVersion + '.gz';
        
        var steps = [
            {msg: _('Бэкап'), cmd: 'cp -f /usr/bin/mihomo /tmp/mihomo.bak'},
            {msg: _('Стоп'), cmd: '/etc/init.d/mihomo stop'},
            {msg: _('Загрузка'), cmd: 'wget -qO /tmp/m.gz "' + url + '" && test -s /tmp/m.gz'},
            {msg: _('Распаковка'), cmd: 'gzip -dc /tmp/m.gz > /tmp/mn && test -s /tmp/mn'},
            {msg: _('Права'), cmd: 'chmod 755 /tmp/mn'},
            {msg: _('Проверка'), cmd: '/tmp/mn -v 2>&1 || true'},
            {msg: _('Установка'), cmd: 'mv -f /tmp/mn /usr/bin/mihomo'},
            {msg: _('Права'), cmd: 'chmod 755 /usr/bin/mihomo'},
            {msg: _('Запуск'), cmd: '/etc/init.d/mihomo start'},
            {msg: _('Очистка'), cmd: 'rm -f /tmp/m.gz /tmp/mihomo.bak'}
        ];
        
        var i = 0;
        var run = function() {
            if (i >= steps.length) {
                ui.hideModal();
                location.reload();
                return;
            }
            var s = steps[i++];
            ui.showModal(null, [E('p', {'class':'spinning'}, _(s.msg))]);
            fs.exec('/bin/sh', ['-c', s.cmd]).then(run).catch(function(e) {
                ui.addNotification(null, E('p', e.message), 'error');
                run();
            });
        };
        run();
    },
    
    load: function() {
        return Promise.all([
            fs.read(MAIN_CONFIG).catch(function() { return ''; }),
            callServiceList('mihomo').catch(function() { return {}; }),
            fs.list(RULE_DIR).catch(function() { return []; })
        ]);
    },
    
    render: function(data) {
        data = data || [];
        mainConfigContent = data[0] || '';
        var svc = data[1] || {};
        cachedRuleFiles = (data[2] || []).sort(function(a,b) { return a.name.localeCompare(b.name); });
        var running = !!(svc.mihomo && svc.mihomo.instances && svc.mihomo.instances.main && svc.mihomo.instances.main.running);
        
        var verEl = E('span', {id: 'mihomo-ver-info', style: 'margin-left:10px;font-size:0.9em;opacity:0.7;'}, _('Загрузка'));
        var updBtn = E('button', {id: 'mihomo-update-btn', 'class': 'btn cbi-button-neutral', style: 'margin-left:10px;font-size:0.9em;', disabled: true}, _('Проверить'));
        
        var statusBadge = running 
            ? E('span', {'class': 'label success', style: 'margin-left:14px;font-size:0.85em;'}, _('работает'))
            : E('span', {'class': 'label', style: 'margin-left:14px;font-size:0.85em;'}, _('остановлен'));
        
        var svcBtn = running
            ? E('button', {'class': 'btn cbi-button-reset', style: 'margin-left:16px;', click: ui.createHandlerFn(this, 'svcAction', 'stop')}, _('Стоп'))
            : E('button', {'class': 'btn cbi-button-positive', style: 'margin-left:16px;', click: ui.createHandlerFn(this, 'svcAction', 'start')}, _('Старт'));
        
        var header = E('div', {style: 'display:flex;align-items:center;margin-bottom:1rem;flex-wrap:wrap;'}, [
            E('h2', {style: 'margin:0;'}, 'Mihomo'),
            statusBadge, svcBtn, verEl, updBtn
        ]);
        
        var self = this;
        this.getVersion().then(function(v) {
            self.currentVersion = v;
            var ve = document.getElementById('mihomo-version');
            if (ve) ve.textContent = v.replace('v', '');
            var ub = document.getElementById('mihomo-update-btn');
            if (ub) {
                ub.disabled = false;
                ub.onclick = function() { self.checkUpdates(true); };
            }
            self.checkUpdates(false);
        });
        
        var dark = isDarkMode();
        var css = dark 
            ? ':root{--bg:#2d2d2d;--bg2:#1C1C1C;--txt:#e0e0e0;--dim:#969696;--brd:#444}'
            : ':root{--bg:#e0e0e0;--bg2:#fff;--txt:#333;--dim:#666;--brd:#E0E0E0}';
        
        var styles = E('style', {}, css + 
            '.btn{min-height:1.8rem;display:inline-flex;align-items:center;padding:0 1rem}' +
            '.tab-bar{display:flex;background:var(--bg)}' +
            '.tab{padding:0.6em 1.2em;cursor:pointer;background:var(--bg);color:var(--dim);margin-right:1px}' +
            '.tab.active{background:var(--bg2);color:var(--txt);border:1px solid var(--brd)}' +
            '.tab-x{margin-left:0.6em;color:#999;cursor:pointer}' +
            '.tab-x:hover{background:#c0392b;color:#fff}' +
            '.toolbar{background:var(--bg);border:1px solid var(--brd);padding:0.8rem}' +
            '.toolbar textarea{width:100%;height:6em;background:var(--bg2);color:var(--txt);border:1px solid var(--brd);font-family:monospace}' +
            '#ace_editor_container{width:100%;height:60vh;border:1px solid var(--brd);border-top:none}');
        
        var tabBar = E('div', {id: 'mihomo-tabs', 'class': 'tab-bar'});
        var toolbar = E('div', {id: 'mihomo-toolbar'});
        var editorDiv = E('div', {id: 'ace_editor_container'});
        
        var actions = E('div', {style: 'display:flex;gap:0.5rem;margin-top:1rem;'}, [
            E('button', {'class': 'btn cbi-button-neutral', click: ui.createHandlerFn(this, 'checkConfig')}, _('Проверить')),
            E('button', {'class': 'btn cbi-button-positive', click: ui.createHandlerFn(this, 'saveConfig', running)}, _('Сохранить')),
            E('button', {'class': 'btn cbi-button-neutral', click: ui.createHandlerFn(this, 'openDash', mainConfigContent)}, _('Панель')),
            E('button', {'class': 'btn cbi-button-neutral', click: ui.createHandlerFn(this, 'showLogs')}, _('Лог'))
        ]);
        
        var outputBox = E('div', {id: 'mihomo-output', style: 'display:none;margin-top:1rem;border:1px solid var(--brd);border-radius:4px;'}, [
            E('div', {style: 'background:var(--bg2);padding:0.6rem 0.8rem;border-bottom:1px solid var(--brd);display:flex;align-items:center;'}, [
                E('strong', {style: 'font-size:0.9em'}, 'Вывод:'),
                E('button', {style: 'background:none;border:none;color:var(--txt);font-size:1.5em;cursor:pointer;margin-left:1rem;', click: function() { document.getElementById('mihomo-output').style.display = 'none'; }}, '×')
            ]),
            E('pre', {id: 'mihomo-output-text', style: 'margin:0;padding:1rem;background:var(--bg2);color:var(--txt);font-family:monospace;max-height:25rem;overflow:auto;'}, '')
        ]);
        
        loadScript(ACE_DIR + 'ace.js').then(function() {
            ace.config.set('basePath', ACE_DIR);
            editor = ace.edit("ace_editor_container");
            editor.setTheme(dark ? "ace/theme/merbivore_soft" : "ace/theme/tomorrow");
            editor.session.setMode("ace/mode/yaml");
            editor.setOptions({fontSize: "0.95em", showPrintMargin: false, wrap: true, tabSize: 2, useSoftTabs: true, highlightActiveLine: false});
            editor.setValue(mainConfigContent, -1);
            setTimeout(function() { editor.resize(); }, 100);
        }).catch(console.error);
        
        this.renderTabs(tabBar);
        this.renderToolbar(toolbar, MAIN_CONFIG);
        
        return E('div', {'class': 'cbi-map'}, [header, styles, tabBar, toolbar, editorDiv, actions, outputBox]);
    },
    
    renderTabs: function(container) {
        L.dom.content(container, []);
        var self = this;
        
        var mainTab = E('div', {
            'class': currentFile === MAIN_CONFIG ? 'tab active' : 'tab',
            click: ui.createHandlerFn(this, 'switchTab', MAIN_CONFIG)
        }, E('span', {}, 'Конфиг'));
        container.appendChild(mainTab);
        
        cachedRuleFiles.forEach(function(f) {
            if (f.type === 'file') {
                var fp = RULE_DIR + f.name;
                if (!validatePath(fp, RULE_DIR)) return;
                var active = currentFile === fp;
                var name = escapeHtml(sanitizeName(f.name));
                var content = [E('span', {}, name)];
                if (active) {
                    content.push(E('span', {'class': 'tab-x', title: _('Удалить'), click: function(e) { e.stopPropagation(); self.deleteFile(fp); }}, '×'));
                }
                var tab = E('div', {
                    'class': active ? 'tab active' : 'tab',
                    click: ui.createHandlerFn(self, 'switchTab', fp)
                }, content);
                container.appendChild(tab);
            }
        });
        
        container.appendChild(E('div', {
            'class': 'tab',
            title: _('Новый файл'),
            click: ui.createHandlerFn(this, 'createFile')
        }, '+'));
    },
    
    renderToolbar: function(container, filePath) {
        L.dom.content(container, []);
        if (filePath === MAIN_CONFIG) {
            container.style.display = 'none';
            return;
        }
        container.style.display = 'block';
        container.className = 'toolbar';
        
        var self = this;
        var placeholder = filePath.endsWith('.txt') ? 'google.com\nyoutube.com' : 'google.com\n104.28.0.0/16';
        var input = E('textarea', {placeholder: placeholder});
        
        var btn = E('button', {'class': 'btn', click: function() {
            var text = input.value.trim();
            if (!text || !editor) return;
            var lines = text.split('\n');
            lines.forEach(function(l) {
                l = l.trim();
                if (!l) return;
                if (filePath.endsWith('.txt')) {
                    editor.navigateFileEnd();
                    editor.insert((editor.getValue().endsWith('\n') ? '' : '\n') + l + '\n');
                } else {
                    var t = detectRuleType(l);
                    if (t === 'IP-CIDR' && l.indexOf('/') === -1) l += '/32';
                    var rules = '  - ' + t + ',' + l;
                    var cc = editor.getValue();
                    var hasPayload = cc.split('\n').some(function(x) { return x.trim() === 'payload:'; });
                    if (hasPayload) {
                        editor.navigateFileEnd();
                        editor.insert('\n' + rules + '\n');
                    } else {
                        editor.navigateFileEnd();
                        editor.insert((cc.endsWith('\n') ? '' : '\n\n') + 'payload:\n' + rules + '\n');
                    }
                }
            });
            input.value = '';
            editor.focus();
        }}, _('Добавить'));
        
        var row = E('div', {style: 'display:flex;gap:0.8rem;align-items:center;'}, [
            E('div', {style: 'flex-grow:1;'}, input),
            btn
        ]);
        container.appendChild(row);
    },
    
    switchTab: function(path, ev) {
        if (!validatePath(path, '/etc/mihomo/')) return;
        if (path === currentFile) return;
        
        var self = this;
        ui.showModal(null, [E('p', {'class': 'spinning'}, _('Загрузка'))]);
        
        fs.read(path).then(function(content) {
            currentFile = path;
            if (editor) {
                editor.setValue(content || '', -1);
                editor.session.setMode(path.endsWith('.txt') ? "ace/mode/text" : "ace/mode/yaml");
            }
            self.renderTabs(document.getElementById('mihomo-tabs'));
            self.renderToolbar(document.getElementById('mihomo-toolbar'), path);
            ui.hideModal();
        }).catch(function() {
            ui.hideModal();
        });
    },
    
    createFile: function() {
        var self = this;
        var nameInput = E('input', {type: 'text', style: 'width:100%;', placeholder: 'my-rules'});
        var typeSelect = E('select', {style: 'width:100%;'}, [
            E('option', {value: '.yaml'}, '.yaml'),
            E('option', {value: '.txt'}, '.txt')
        ]);
        
        var footer = E('div', {style: 'margin-top:1rem;display:flex;gap:0.5rem;'}, [
            E('button', {'class': 'btn', click: ui.hideModal}, _('Отмена')),
            E('button', {'class': 'btn cbi-button-positive', click: function() {
                var fn = nameInput.value.trim();
                if (!fn || !validateFilename(fn)) return;
                var fp = RULE_DIR + fn + typeSelect.value;
                ui.showModal(null, [E('p', {'class': 'spinning'}, _('Создание'))]);
                fs.write(fp, '').then(function() {
                    return fs.list(RULE_DIR);
                }).then(function(files) {
                    cachedRuleFiles = (files || []).sort(function(a,b) { return a.name.localeCompare(b.name); });
                    self.switchTab(fp);
                    ui.hideModal();
                });
            }}, _('Создать'))
        ]);
        
        ui.showModal(_('Новый файл'), [
            E('div', {}, [
                E('div', {style: 'margin-bottom:0.5rem;'}, [E('label', {style: 'margin-right:0.5rem;'}, 'Имя:'), nameInput]),
                E('div', {}, [E('label', {style: 'margin-right:0.5rem;'}, 'Тип:'), typeSelect])
            ]),
            footer
        ]);
        nameInput.focus();
    },
    
    deleteFile: function(path) {
        if (!validatePath(path, RULE_DIR) || path === MAIN_CONFIG) return;
        if (!confirm(_('Удалить %s?').format(path.split('/').pop()))) return;
        
        var self = this;
        ui.showModal(null, [E('p', {'class': 'spinning'}, _('Удаление'))]);
        
        fs.remove(path).then(function() {
            return fs.list(RULE_DIR);
        }).then(function(files) {
            cachedRuleFiles = (files || []).sort(function(a,b) { return a.name.localeCompare(b.name); });
            if (currentFile === path) self.switchTab(MAIN_CONFIG);
            else {
                self.renderTabs(document.getElementById('mihomo-tabs'));
                ui.hideModal();
            }
        });
    },
    
    saveConfig: function(wasRunning) {
        if (!editor) return;
        var content = editor.getValue();
        if (currentFile === MAIN_CONFIG) mainConfigContent = content;
        
        ui.showModal(null, [E('p', {'class': 'spinning'}, _('Сохранение'))]);
        
        var self = this;
        fs.write(currentFile, content).then(function() {
            if (currentFile === MAIN_CONFIG) {
                return fs.exec('/usr/bin/mihomo', ['-d', '/etc/mihomo', '-t', MAIN_CONFIG]).then(function(res) {
                    if (res.code !== 0) throw new Error((res.stdout || '') + (res.stderr || ''));
                    if (wasRunning) return fs.exec('/etc/init.d/mihomo', ['restart']);
                });
            }
        }).then(function() {
            ui.hideModal();
            if (currentFile === MAIN_CONFIG) setTimeout(function() { location.reload(); }, 500);
        }).catch(function(e) {
            ui.hideModal();
            ui.addNotification(null, E('p', e.message), 'error');
        });
    },
    
    checkConfig: function() {
        if (currentFile !== MAIN_CONFIG || !editor) return;
        ui.showModal(null, [E('p', {'class': 'spinning'}, _('Проверка'))]);
        
        var self = this;
        fs.write(MAIN_CONFIG, editor.getValue()).then(function() {
            return fs.exec('/usr/bin/mihomo', ['-d', '/etc/mihomo', '-t']);
        }).then(function(res) {
            ui.hideModal();
            var out = document.getElementById('mihomo-output-text');
            var box = document.getElementById('mihomo-output');
            if (out && box) {
                out.textContent = (res.stdout || '') + (res.stderr || '');
                box.style.display = 'block';
            }
            ui.addNotification(null, E('pre', {}, (res.stdout || '') + (res.stderr || '')), res.code !== 0 ? 'error' : 'info');
        }).catch(function(e) {
            ui.hideModal();
            ui.addNotification(null, E('p', e.message), 'error');
        });
    },
    
    svcAction: function(action) {
        ui.showModal(null, [E('p', {'class': 'spinning'}, _('Выполнение'))]);
        fs.exec('/etc/init.d/mihomo', [action]).then(function() {
            location.reload();
        }).catch(function(e) {
            ui.hideModal();
            ui.addNotification(null, E('p', e.message), 'error');
        });
    },
    
    showLogs: function() {
        fs.exec('/sbin/logread', ['-e', 'mihomo']).then(function(res) {
            var text = res.stdout || _('Нет записей');
            var out = document.getElementById('mihomo-output-text');
            var box = document.getElementById('mihomo-output');
            if (out && box) {
                out.textContent = text;
                box.style.display = 'block';
            }
        }).catch(function(e) {
            ui.addNotification(null, E('p', e.message), 'error');
        });
    },
    
    openDash: function(content) {
        var host = window.location.hostname;
        var port = '9090';
        try {
            var m = content.match(/external-controller:\s*([0-9.]+):(\d+)/);
            if (m && m[1] && m[2]) {
                var ip = m[1].trim();
                if (/^(\d{1,3}\.){3}\d{1,3}$/.test(ip) && ip !== '0.0.0.0') host = ip;
                var pn = parseInt(m[2].trim(), 10);
                if (!isNaN(pn) && pn >= 1 && pn <= 65535) port = m[2].trim();
            }
        } catch(e) {}
        window.open('http://' + host + ':' + port + '/ui/', '_blank');
    }
});
LUCIVIEW
    
    info "LuCI интерфейс готов"
}

#-------------------------------------------------------------------------------
#  FINALIZATION
#-------------------------------------------------------------------------------
finalize_install() {
    header "Завершение установки"
    
    subheader "Настройка прав доступа..."
    find /www/luci-static/resources/view -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod +x /etc/init.d/mihomo /etc/init.d/magitrickle 2>/dev/null || true
    
    subheader "Очистка кэша и перезапуск сервисов..."
    rm -rf /tmp/luci-* 2>/dev/null || true
    /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    /etc/init.d/uhttpd restart >/dev/null 2>&1 || true
    
    # Get IP for display
    local my_ip
    my_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || echo '192.168.1.1')"
    
    echo ""
    success "🎉 Установка успешно завершена!"
    echo ""
    printf "${C_CYAN}╭─ Панели управления ─────────────────${C_RESET}\n"
    printf "${C_CYAN}│${C_RESET} ${C_BOLD}Mihomo:${C_RESET}     http://${my_ip}:9090/ui/\n"
    printf "${C_CYAN}│${C_RESET} ${C_BOLD}MagiTrickle:${C_RESET} http://${my_ip}:8080/\n"
    printf "${C_CYAN}╰─────────────────────────────────────${C_RESET}\n"
    echo ""
    info "Доступ в LuCI: ${C_CYAN}Services → Mihomo / MagiTrickle${C_RESET}"
    echo ""
}

#-------------------------------------------------------------------------------
#  MAIN ENTRY POINT
#-------------------------------------------------------------------------------
main() {
    # Check requirements
    command -v curl >/dev/null 2>&1 || die "Требуется: curl"
    command -v wget >/dev/null 2>&1 || die "Требуется: wget"
    command -v uci >/dev/null 2>&1 || die "Требуется: uci"
    
    # Clear and show banner
    clear
    printf "${C_CYAN}"
    printf "╔════════════════════════════════════╗\n"
    printf "║  ${C_BOLD}Mihomo + MagiTrickle Installer${C_RESET}${C_CYAN}  ║\n"
    printf "║  v2.1.1 • OpenWRT Optimized${C_RESET}${C_CYAN}      ║\n"
    printf "╚════════════════════════════════════╝\n"
    printf "${C_RESET}\n"
    
    # Initialize
    init_pkgmgr
    log "Система пакетов: ${C_GREEN}${PKG_MGR}${C_RESET}"
    
    # Run installation steps
    install_dependencies
    install_mihomo_core
    install_hev_tunnel
    install_magitrickle_app
    setup_luci_interface
    finalize_install
}

# Execute main function
main "$@"
```
