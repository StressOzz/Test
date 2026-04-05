```sh
#!/bin/sh
#===============================================================================
#  Mihomo + MagiTrickle Installer for OpenWRT
#  Author: StressOzz Remix | Optimized Edition
#  License: MIT
#===============================================================================

set -euo pipefail

#-------------------------------------------------------------------------------
#  CONFIGURATION
#-------------------------------------------------------------------------------
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.1.0"
readonly MIHOMO_DIR="/etc/mihomo"
readonly MIHOMO_BIN="/usr/bin/mihomo"
readonly MAGITRICKLE_CFG="/etc/magitrickle/state/config.yaml"
readonly LUCI_MIHOMO_VIEW="/www/luci-static/resources/view/mihomo"
readonly LUCI_MT_VIEW="/www/luci-static/resources/view/magitrickle"

# Colors
readonly C_RESET='\033[0m'
readonly C_BOLD='\033[1m'
readonly C_RED='\033[31m'
readonly C_GREEN='\033[32m'
readonly C_YELLOW='\033[33m'
readonly C_BLUE='\033[34m'
readonly C_CYAN='\033[36m'
readonly C_MAGENTA='\033[35m'
readonly C_WHITE='\033[37m'

# Progress
readonly STEP_TOTAL=5
STEP_CURRENT=0

#-------------------------------------------------------------------------------
#  UTILITIES
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

# Check requirements
require() {
    command -v "$1" >/dev/null 2>&1 || die "Требуется утилита: $1"
}

# Detect package manager
PKG_MGR=""
init_pkgmgr() {
    if command -v apk >/dev/null 2>&1; then
        PKG_MGR="apk"
    elif command -v opkg >/dev/null 2>&1; then
        PKG_MGR="opkg"
    else
        die "Не найдена система пакетов (apk/opkg)"
    fi
}

pkg() {
    case "$PKG_MGR" in
        apk)
            case "$1" in
                update) apk update -q ;;
                install) shift; apk add -q "$@" ;;
                remove)  shift; apk del -q "$@" ;;
            esac
            ;;
        opkg)
            case "$1" in
                update) opkg update -q ;;
                install) shift; opkg install -q "$@" ;;
                remove)  shift; opkg remove -q "$@" ;;
            esac
            ;;
    esac
}

# Fetch latest version from GitHub
gh_latest() {
    local repo="$1" pattern="${2:-'[0-9]+\\.[0-9]+\\.[0-9]+'}"
    curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null \
        | grep -oE "$pattern" | head -1
}

# Download with retry
fetch() {
    local url="$1" dest="$2" max_retry=3 retry=0
    while [ $retry -lt $max_retry ]; do
        if curl -Lf --connect-timeout 10 -sS -o "$dest" "$url" 2>/dev/null && [ -s "$dest" ]; then
            return 0
        fi
        retry=$((retry + 1))
        sleep 1
    done
    return 1
}

# Architecture detection for Mihomo
detect_arch() {
    local arch="$(uname -m)" endian
    case "$arch" in
        x86_64) echo "amd64" ;;
        i?86)   echo "386" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7*) echo "armv7" ;;
        armv5*|armv4*) echo "armv5" ;;
        mips*)
            endian=$(hexdump -s 5 -n 1 -e '1/1 "%d"' /bin/busybox 2>/dev/null || echo 0)
            local fpu=$(grep -c "FPU" /proc/cpuinfo 2>/dev/null || echo 0)
            local float="softfloat"; [ "$fpu" -gt 0 ] && float="hardfloat"
            [ "$endian" = "1" ] && echo "mipsle-${float}" || echo "mips-${float}"
            ;;
        riscv64) echo "riscv64" ;;
        *) die "Неподдерживаемая архитектура: $arch" ;;
    esac
}

# Check disk space
check_space() {
    local path="$1" required_kb="$2"
    local avail=$(df -k "$path" 2>/dev/null | awk 'NR==2{print $4}')
    [ "$avail" -ge "$required_kb" ] || {
        error "Недостаточно места в $path: $((avail/1024))MB (требуется $((required_kb/1024))MB)"
        return 1
    }
}

#-------------------------------------------------------------------------------
#  INSTALLATION MODULES
#-------------------------------------------------------------------------------

install_deps() {
    step "Зависимости"
    subheader "Обновление индексов пакетов..."
    pkg update || warn "Обновление пакетов завершилось с предупреждениями"
    
    subheader "Установка компонентов..."
    local deps="ca-certificates kmod-tun kmod-nft-tproxy kmod-nft-nat curl"
    [ "$PKG_MGR" = "opkg" ] && deps="$deps libcurl4 ca-bundle"
    pkg install $deps || die "Не удалось установить зависимости"
    info "Зависимости установлены"
}

install_mihomo() {
    step "Ядро Mihomo"
    
    # Space check
    check_space /tmp 16000 || die
    check_space / 18000 || die
    
    # Stop service if running
    [ -f /etc/init.d/mihomo ] && /etc/init.d/mihomo stop 2>/dev/null || true
    
    # Architecture
    local arch="$(detect_arch)"
    subheader "Архитектура: ${C_CYAN}$(uname -m)${C_RESET} → ${C_GREEN}${arch}${C_RESET}"
    
    # Prepare directories
    mkdir -p "${MIHOMO_DIR}"/{proxy-providers,rule-providers,rule-files,UI}
    echo "$arch" > "${MIHOMO_DIR}/.arch"
    
    # Get latest version
    subheader "Поиск последней версии..."
    local version="$(gh_latest "MetaCubeX/mihomo" 'v[0-9]+\\.[0-9]+\\.[0-9]+')"
    [ -z "$version" ] && die "Не удалось получить версию Mihomo"
    info "Актуальная версия: ${C_GREEN}${version}${C_RESET}"
    
    # Download
    local filename="mihomo-linux-${arch}-${version}.gz"
    local url="https://github.com/MetaCubeX/mihomo/releases/download/${version}/${filename}"
    local tmp="/tmp/mihomo.gz"
    
    subheader "Загрузка ${filename}..."
    fetch "$url" "$tmp" || die "Ошибка загрузки ядра"
    
    # Install
    subheader "Установка..."
    gunzip -c "$tmp" > "$MIHOMO_BIN" || die "Ошибка распаковки"
    chmod +x "$MIHOMO_BIN"
    rm -f "$tmp"
    
    # Verify
    "$MIHOMO_BIN" -v >/dev/null 2>&1 || die "Ядро не проходит проверку"
    info "Ядро установлено: ${C_GREEN}$("$MIHOMO_BIN" -v | head -1)${C_RESET}"
    
    # Init script
    cat > /etc/init.d/mihomo <<'INIT'
#!/bin/sh /etc/rc.common
START=99; USE_PROCD=1
BIN="/usr/bin/mihomo"; DIR="/etc/mihomo"; CONF="${DIR}/config.yaml"
start_service() {
    [ -x "$BIN" ] && [ -s "$CONF" ] || return 1
    procd_open_instance; procd_set_param command "$BIN" -d "$DIR" -f "$CONF"
    procd_set_param stdout 1 stderr 1 respawn; procd_close_instance
}
service_triggers() { procd_add_reload_trigger "mihomo"; }
INIT
    chmod +x /etc/init.d/mihomo
    /etc/init.d/mihomo enable 2>/dev/null || true
    
    info "Служба настроена"
}

install_hev() {
    step "Hev-Socks5-Tunnel"
    subheader "Установка пакета..."
    pkg install hev-socks5-tunnel 2>/dev/null || warn "Пакет может быть недоступен"
    
    mkdir -p /etc/hev-socks5-tunnel
    cat > /etc/hev-socks5-tunnel/main.yml <<'HEV'
tunnel:
  name: Mihomo
  mtu: 8500
  multi-queue: false
  ipv4: 198.18.0.1
socks5:
  port: 7890
  address: 127.0.0.1
  udp: 'udp'
HEV
    chmod 600 /etc/hev-socks5-tunnel/main.yml
    
    # Cleanup UCI
    uci delete network.Mihomo 2>/dev/null || true
    for s in $(uci show firewall 2>/dev/null | grep -E "\.(name|src|dest)='Mihomo'" | cut -d= -f1 | cut -d. -f1 | sort -u); do
        uci delete "$s" 2>/dev/null || true
    done
    uci commit firewall 2>/dev/null || true
    
    # Configure
    uci set hev-socks5-tunnel.config.enabled='1' 2>/dev/null || true
    uci set hev-socks5-tunnel.config.configfile='/etc/hev-socks5-tunnel/main.yml' 2>/dev/null || true
    uci commit hev-socks5-tunnel 2>/dev/null || true
    /etc/init.d/hev-socks5-tunnel restart >/dev/null 2>&1 || true
    
    # Network
    uci set network.Mihomo=interface 2>/dev/null || uci add network interface
    uci set network.Mihomo.proto='none'
    uci set network.Mihomo.device='Mihomo'
    uci commit network
    /etc/init.d/network reload >/dev/null 2>&1
    
    # Firewall
    local zone=$(uci add firewall zone)
    uci set "firewall.${zone}.name=Mihomo"
    uci set "firewall.${zone}.input=REJECT" "firewall.${zone}.output=REJECT" "firewall.${zone}.forward=REJECT"
    uci set "firewall.${zone}.masq=1" "firewall.${zone}.mtu_fix=1"
    uci add_list "firewall.${zone}.network=Mihomo"
    local fwd=$(uci add firewall forwarding)
    uci set "firewall.${fwd}.src=lan" "firewall.${fwd}.dest=Mihomo"
    uci commit firewall
    /etc/init.d/firewall restart >/dev/null 2>&1
    
    info "Hev-Socks5-Tunnel настроен"
}

install_magitrickle() {
    step "MagiTrickle"
    
    # Version selection
    local mt_ver="$(gh_latest "MagiTrickle/MagiTrickle")"
    local mod_ver="$(curl -Ls -o /dev/null -w '%{url_effective}' "https://github.com/badigit/MagiTrickle_mod_badigit/releases/latest" 2>/dev/null | sed -E 's#.*/tag/v?##')"
    local arch="$(grep '^OPENWRT_ARCH=' /etc/os-release 2>/dev/null | cut -d'"' -f2 || echo 'unknown')"
    
    printf "\n${C_YELLOW}╭─ Выбор версии MagiTrickle ─────────────${C_RESET}\n"
    printf "${C_YELLOW}│${C_RESET}  ${C_CYAN}1)${C_RESET} Оригинальный ${C_GREEN}v${mt_ver}${C_RESET}\n"
    printf "${C_YELLOW}│${C_RESET}  ${C_CYAN}2)${C_RESET} Mod by badigit ${C_GREEN}v${mod_ver}${C_RESET}\n"
    printf "${C_YELLOW}╰─${C_RESET} Введите номер [1]: "
    read -r choice 2>/dev/null || choice=1
    
    local base_url pkg_url pkg_ext
    case "$choice" in
        2)
            base_url="https://github.com/badigit/MagiTrickle_mod_badigit/releases/download/${mod_ver}"
            info "Выбран: ${C_CYAN}MagiTrickle mod${C_RESET}"
            ;;
        *)
            base_url="https://github.com/MagiTrickle/MagiTrickle/releases/download/${mt_ver}"
            info "Выбран: ${C_CYAN}Оригинальный MagiTrickle${C_RESET}"
            ;;
    esac
    
    [ "$PKG_MGR" = "apk" ] && pkg_ext="apk" || pkg_ext="ipk"
    pkg_url="${base_url}/magitrickle_*$pkg_ext"
    
    # Backup config
    [ -f "$MAGITRICKLE_CFG" ] && cp "$MAGITRICKLE_CFG" "/tmp/mt_backup_$(date +%s).yaml"
    
    # Remove old
    pkg remove magitrickle 2>/dev/null || true
    
    # Download & install
    local tmp="/tmp/magitrickle.${pkg_ext}"
    subheader "Загрузка пакета..."
    # Get actual filename
    local actual_pkg="$(curl -Ls "$base_url" 2>/dev/null | grep -oE "magitrickle_[^\"']+\\.${pkg_ext}" | head -1)"
    [ -z "$actual_pkg" ] && die "Не удалось найти пакет для скачивания"
    pkg_url="${base_url}/${actual_pkg}"
    
    fetch "$pkg_url" "$tmp" || die "Ошибка загрузки MagiTrickle"
    subheader "Установка..."
    [ "$PKG_MGR" = "apk" ] && apk add --allow-untrusted "$tmp" >/dev/null 2>&1 || opkg install "$tmp" >/dev/null 2>&1
    rm -f "$tmp"
    
    # Config
    subheader "Применение конфигурации..."
    local cfg_url="https://raw.githubusercontent.com/StressOzz/Use_WARP_on_OpenWRT/refs/heads/main/files/MagiTrickle/configAD.yaml"
    mkdir -p "$(dirname "$MAGITRICKLE_CFG")"
    fetch "$cfg_url" "$MAGITRICKLE_CFG" || warn "Не удалось загрузить конфиг, используется дефолтный"
    
    # Start service
    /etc/init.d/magitrickle enable restart >/dev/null 2>&1
    
    # LuCI page
    mkdir -p "$LUCI_MT_VIEW" /usr/share/luci/menu.d
    cat > "${LUCI_MT_VIEW}/magitrickle.js" <<'MTJS'
'use strict';'require view';
return view.extend({render:function(){
return E('div',{style:'width:100%;height:92vh;margin:-20px -20px 0 -20px;overflow:hidden;'},
E('iframe',{src:'http://'+window.location.hostname+':8080',style:'width:100%;height:100%;border:none;'}));}});
MTJS
    cat > /usr/share/luci/menu.d/luci-app-magitrickle.json <<'MTM'
{"admin/services/magitrickle":{"title":"MagiTrickle","order":60,"action":{"type":"view","path":"magitrickle/magitrickle"}}}
MTM
    
    info "MagiTrickle установлен"
}

setup_luci_mihomo() {
    subheader "Настройка LuCI интерфейса..."
    
    mkdir -p "${LUCI_MIHOMO_VIEW}/ace" /usr/share/luci/menu.d /usr/share/rpcd/acl.d
    
    # Menu & ACL
    echo '{"admin/services/mihomo":{"title":"Mihomo","order":60,"action":{"type":"view","path":"mihomo/config"}}}' \
        > /usr/share/luci/menu.d/luci-app-mihomo.json
    
    cat > /usr/share/rpcd/acl.d/luci-app-mihomo.json <<'ACL'
{"luci-app-mihomo":{"description":"Mihomo","read":{"file":{"/etc/mihomo/config.yaml":["read"],"/etc/mihomo/rule-files/":["list"]}},"write":{"file":{"/etc/mihomo/config.yaml":["write"],"/usr/bin/mihomo":["exec"],"/etc/init.d/mihomo":["exec"]}}}}
ACL
    
    # ACE Editor
    local ace_ver="$(curl -s https://api.cdnjs.com/libraries/ace 2>/dev/null | grep -o '"version":"[^"]*"' | cut -d'"' -f4 | head -1)"
    [ -z "$ace_ver" ] && ace_ver="1.43.3"
    
    for f in ace.js theme-merbivore_soft.js theme-tomorrow.js mode-yaml.js worker-yaml.js; do
        fetch "https://cdn.jsdelivr.net/npm/ace-builds@${ace_ver}/src-min-noconflict/${f}" "${LUCI_MIHOMO_VIEW}/ace/${f}" || \
        fetch "https://cdnjs.cloudflare.com/ajax/libs/ace/${ace_ver}/${f}" "${LUCI_MIHOMO_VIEW}/ace/${f}" || \
        warn "Не загружен: $f"
    done
    
    # Main view (minified for speed)
    cat > "${LUCI_MIHOMO_VIEW}/config.js" <<'VIEW'
'use strict';'require view';'require fs';'require ui';'require rpc';
var D='/luci-static/resources/view/mihomo/ace/',C='/etc/mihomo/config.yaml',R='/etc/mihomo/rule-files/',e=null,f=C,r=[],c='',l={},A=['start','stop','restart','check','logs'];
var S=rpc.declare({object:'service',method:'list',params:['name']});
function H(t){return typeof t!='string'?t:t.replace(/[&<>"']/g,function(m){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m];});}
function P(p,b){return p&&typeof p=='string'&&!p.includes('..')&&!p.includes('\0')&&!p.includes('~')&&p.replace(/\/+/g,'/').startsWith(b)&&p.length<=1024;}
function V(n){return n&&/^[a-zA-Z0-9._-]+$/.test(n)&&n.length<=255&&!['con','prn','aux','nul','com1','lpt1','.'].includes(n.toLowerCase());}
function T(t){if(!t)return'';return t.replace(/[<>"'`]/g,'');}
function L(s){return new Promise(function(a,b){if(l[s]){a();return;}var d=document.createElement('script');d.src=s;d.onload=function(){l[s]=true;a();};d.onerror=b;document.head.appendChild(d);});}
function DRT(l){l=l.trim();if(l.includes(':')&&!l.match(/http(s)?:\/\//))return'IP-CIDR6';if(/^\d{1,3}(\.\d{1,3}){3}\/?\d*$/.test(l))return'IP-CIDR';if(l.startsWith('.'))return'DOMAIN-WILDCARD';var d=(l.replace(/^\./,'').match(/\./g)||[]).length;return d>=2?'DOMAIN':d===1?'DOMAIN-SUFFIX':'DOMAIN-KEYWORD';}
function GPS(f){if(f===C)return'';var n=f.split('/').pop().replace(/\.(yaml|txt)$/,''),t=f.endsWith('.txt');return n+'-list:\n  type: file\n  behavior: '+(t?'domain':'classical')+'\n  format: '+(t?'text':'yaml')+'\n  path: ./rule-files/'+f.split('/').pop();}
function IDM(){try{var r=window.getComputedStyle(document.body).backgroundColor.match(/\d+/g);if(r)return 0.2126*r[0]+0.7152*r[1]+0.0722*r[2]<128;}catch(e){}return false;}
return view.extend({v:'?',lv:null,ub:null,lve:null,
GV:function(){return fs.stat('/usr/bin/mihomo').then(function(){return fs.exec('/usr/bin/mihomo',['--v']);}).then(function(r){var m=(r.stdout||'').match(/v(\d+\.\d+\.\d+)/);return m?m[0]:'?';}).catch(function(){return'?';});},
RUS:function(lv,im){this.lv=lv;if(this.lve){this.lve.textContent=_('(ядро %s)').format(lv.replace('v',''));this.lve.style.display='inline';this.lve.style.color=lv!==this.v?'#5cb85c':'';}if(lv===this.v){this.ub.textContent=_('Проверить');this.ub.className='btn cbi-button-neutral';this.ub.onclick=function(){location.reload();};if(im)location.reload();}else{this.ub.textContent=_('Обновить');this.ub.className='btn cbi-button-action';this.ub.onclick=ui.createHandlerFn(this,'UPD');}},
CFU:function(im){var self=this,k='mt_upd',t=36e5;if(!im){try{var o=localStorage.getItem(k);if(o){var j=JSON.parse(o);if(j.v&&Date.now()-j.t<t){this.RUS(j.v,false);return;}}}catch(e){}}if(im)ui.showModal(null,[E('p',{'class':'spinning'},_('Проверка'))]);var cmd='wget -qO- https://api.github.com/repos/MetaCubeX/mihomo/releases/latest|grep tag_name|sed "s/.*v\\([0-9.]*\\).*/v\\1/"';fs.exec('/bin/sh',['-c',cmd]).then(function(r){if(im)ui.hideModal();var lv=(r.stdout||'').trim();if(!lv.match(/^v\d+\.\d+\.\d+$/))return;try{localStorage.setItem(k,JSON.stringify({v:lv,t:Date.now()}));}catch(e){}self.RUS(lv,im);}).catch(function(e){if(im){ui.hideModal();ui.addNotification(null,E('p',e.message),'error');}});},
UPD:function(){if(!this.lv)return;this.ub.disabled=true;this.ub.textContent=_('Загрузка...');var ar='arm64',u='https://github.com/MetaCubeX/mihomo/releases/download/'+this.lv+'/mihomo-linux-'+ar+'-'+this.lv+'.gz',st=[{m:'Бэкап',c:'cp -f /usr/bin/mihomo /tmp/mihomo.bak'},{m:'Стоп',c:'/etc/init.d/mihomo stop'},{m:'Скачивание',c:'wget -qO /tmp/m.gz "'+u+'"&&test -s /tmp/m.gz'},{m:'Распаковка',c:'gzip-dc /tmp/m.gz>/tmp/mn&&test -s /tmp/mn'},{m:'Права',c:'chmod 755 /tmp/mn'},{m:'Проверка',c:'/tmp/mn -v||true'},{m:'Установка',c:'mv -f /tmp/mn /usr/bin/mihomo'},{m:'Права',c:'chmod 755 /usr/bin/mihomo'},{m:'Старт',c:'/etc/init.d/mihomo start'},{m:'Чистка',c:'rm -f /tmp/m.gz /tmp/mihomo.bak'}],i=0,ex=function(){if(i>=st.length){ui.hideModal();location.reload();return Promise.resolve();}var s=st[i++];ui.showModal(null,[E('p',{'class':'spinning'},_(s.m))]);return fs.exec('/bin/sh',['-c',s.c]).then(ex).catch(function(e){ui.addNotification(null,E('p',e.message),'error');ex();});};ex();},
load:function(){return Promise.all([fs.read(C).catch(function(){return'';}),S('mihomo').catch(function(){return{}}),fs.list(R).catch(function(){return[]});]);},
render:function(d){d=d||[];c=d[0]||'';var si=d[1]||{},rf=(d[2]||[]).sort(function(a,b){return a.name.localeCompare(b.name);}),ir=!!(si.mihomo&&si.mihomo.instances.main.running);r=rf;
var vc=E('span',{style:'margin-left:10px;font-size:0.9em;opacity:0.7;'},_('Загрузка')),lve=E('span',{id:'mt-lv',style:'margin-left:4px;font-size:0.9em;opacity:0.7;display:none;'},''),ub=E('button',{id:'mt-ub','class':'btn cbi-button-neutral',style:'margin-left:10px;font-size:0.9em;',disabled:true},_('Проверить')),sb=ir?E('span',{'class':'label success',style:'margin-left:14px;font-size:0.85em;'},_('работает')):E('span',{'class':'label',style:'margin-left:14px;font-size:0.85em;'},_('остановлен')),svb=ir?E('button',{'class':'btn cbi-button-reset',style:'margin-left:16px;','click':ui.createHandlerFn(this,'SA','stop')},_('Стоп')):E('button',{'class':'btn cbi-button-positive',style:'margin-left:16px;','click':ui.createHandlerFn(this,'SA','start')},_('Старт'));
var hdr=E('div',{style:'display:flex;align-items:center;margin-bottom:1rem;flex-wrap:wrap;'},[E('h2',{style:'margin:0;'},'Mihomo'),sb,svb,vc,lve,ub]);this.lve=lve;this.ub=ub;
var self=this;this.GV().then(function(v){self.v=v;var ve=document.getElementById('mihomo-version');if(ve)ve.textContent=v.replace('v','');var ubt=document.getElementById('mt-ub');if(ubt){ubt.disabled=false;ubt.onclick=function(){self.CFU(true);};}self.CFU(false);});
var dr=IDM(),cv=dr?`:root{--bg:#2d2d2d;--bg2:#1C1C1C;--txt:#e0e0e0;--dim:#969696;--brd:#444}`:`:root{--bg:#e0e0e0;--bg2:#fff;--txt:#333;--dim:#666;--brd:#E0E0E0;}`,cs=E('style',{},cv+`.btn{min-height:1.8rem;display:inline-flex;align-items:center;padding:0 1rem}.tab-bar{display:flex;background:var(--bg)}.tab{padding:0.6em 1.2em;cursor:pointer;background:var(--bg);color:var(--dim);margin-right:1px}.tab.active{background:var(--bg2);color:var(--txt);border:1px solid var(--brd)}.tab-x{margin-left:0.6em;color:#999}.tab-x:hover{background:#c0392b;color:#fff}.toolbar{background:var(--bg);border:1px solid var(--brd);padding:0.8rem}.toolbar textarea{width:100%;height:6em;background:var(--bg2);color:var(--txt);border:1px solid var(--brd);font-family:monospace}#ace_editor_container{width:100%;height:60vh;border:1px solid var(--brd);border-top:none}`);
var tb=E('div',{'id':'mt-tb','class':'tab-bar'}),tc=E('div',{'id':'mt-tc'}),ec=E('div',{'id':'ace_editor_container'});
var bc=E('div',{style:'display:flex;gap:0.5rem;margin-top:1rem;'},[E('button',{'class':'btn cbi-button-neutral','click':ui.createHandlerFn(this,'CHK')},_('Проверить')),E('button',{'class':'btn cbi-button-positive','click':ui.createHandlerFn(this,'SAV',ir)},_('Сохранить')),E('button',{'class':'btn cbi-button-neutral','click':ui.createHandlerFn(this,'DASH',c)},_('Панель')),E('button',{'class':'btn cbi-button-neutral','click':ui.createHandlerFn(this,'LOGS')},_('Лог'))]);
var ob=E('div',{'id':'mt-ob',style:'display:none;margin-top:1rem;border:1px solid var(--brd);border-radius:4px;'},[E('div',{style:'background:var(--bg2);padding:0.6rem 0.8rem;border-bottom:1px solid var(--brd);display:flex;align-items:center;'},[E('strong',{style:'font-size:0.9em'},'Вывод:'),E('button',{style:'background:none;border:none;color:var(--txt);font-size:1.5em;cursor:pointer;margin-left:1rem;','click':function(){document.getElementById('mt-ob').style.display='none';}},'×')]),E('pre',{'id':'mt-ot',style:'margin:0;padding:1rem;background:var(--bg2);color:var(--txt);font-family:monospace;max-height:25rem;overflow:auto;'},'')]);
L(D+'ace.js').then(function(){ace.config.set('basePath',D);e=ace.edit("ace_editor_container");e.setTheme(dr?"ace/theme/merbivore_soft":"ace/theme/tomorrow");e.session.setMode("ace/mode/yaml");e.setOptions({fontSize:"0.95em",showPrintMargin:false,wrap:true,tabSize:2,useSoftTabs:true,highlightActiveLine:false});e.setValue(c,-1);setTimeout(function(){e.resize();},100);}).catch(console.error);
this.RTB(tb);this.RTL(tc,C);setTimeout(function(){this.UV(C);}.bind(this),100);
return E('div',{'class':'cbi-map'},[hdr,cs,tb,tc,ec,bc,ob]);},
UV:function(p){var im=p===C;document.getElementById('bottom-buttons')&&(document.getElementById('bottom-buttons').style.display=im?'flex':'none');},
RTB:function(c){L.dom.content(c,[]);var self=this,mt=E('div',{'class':f===C?'tab active':'tab','click':ui.createHandlerFn(this,'TC',C)},E('span',{},'Конфиг'));c.appendChild(mt);r.forEach(function(fi){if(fi.type==='file'){var fp=R+fi.name;if(!P(fp,R))return;var ia=f===fp,sn=H(T(fi.name)),tc=[E('span',{},sn)];if(ia)tc.push(E('span',{'class':'tab-x','title':_('Удалить'),'click':ui.createHandlerFn(self,'DF',fp)},'×'));var tb=E('div',{'class':ia?'tab active':'tab','click':ui.createHandlerFn(self,'TC',fp)},tc);c.appendChild(tb);}});c.appendChild(E('div',{'class':'tab','title':_('Новый'),'click':ui.createHandlerFn(this,'CF')},'+'));},
RTL:function(c,p){L.dom.content(c,[]);if(p===C){c.style.display='none';return;}c.style.display='block';c.className='toolbar';var self=this,inp=E('textarea',{placeholder:p.endsWith('.txt')?'google.com\nyoutube.com':'google.com\n104.28.0.0/16'});var row=E('div',{'class':'toolbar-row'},[E('div',{style:'flex-grow:1;'},inp),E('button',{'class':'btn','click':function(){if(p.endsWith('.txt')){var ls=inp.value.trim().split('\n');ls.forEach(function(l){l=l.trim();if(l){e.navigateFileEnd();e.insert((e.getValue().endsWith('\n')?'':'\n')+l+'\n');}});}else{var ls=inp.value.trim().split('\n'),nr=[];ls.forEach(function(l){l=l.trim();if(l){var t=DRT(l);if(t==='IP-CIDR'&&!l.includes('/'))l+='/32';nr.push('  - '+t+','+l);}});if(nr.length){var cc=e.getValue(),pi=cc.split('\n').findIndex(function(l){return l.trim()==='payload:';});if(pi!==-1){e.gotoLine(cc.split('\n').length+1,0);e.insert(nr.join('\n')+'\n');}else{e.navigateFileEnd();e.insert((cc.endsWith('\n')?'':'\n\n')+'payload:\n'+nr.join('\n')+'\n');}}}inp.value='';e.focus();}},_('Добавить'))]);c.appendChild(row);},
TC:function(p,ev){if(!P(p,'/etc/mihomo/'))return;if(ev&&ev.target.classList.contains('tab-x')){ev.stopPropagation();return;}if(p===f)return;var self=this;ui.showModal(null,[E('p',{'class':'spinning'},_('Загрузка'))]);fs.read(p).then(function(ct){f=p;if(e){e.setValue(ct||'',-1);e.session.setMode(p.endsWith('.txt')?"ace/mode/text":"ace/mode/yaml");}self.RTB(document.getElementById('mt-tb'));self.RTL(document.getElementById('mt-tc'),p);self.UV(p);ui.hideModal();}).catch(function(){ui.hideModal();});},
CF:function(){var self=this,ni=E('input',{type:'text',style:'width:100%;',placeholder:'my-rules'}),ts=E('select',{style:'width:100%;'},[E('option',{value:'.yaml'},'.yaml'),E('option',{value:'.txt'},'.txt')]),ft=E('div',{style:'margin-top:1rem;display:flex;gap:0.5rem;'},[E('button',{'class':'btn','click':ui.hideModal},_('Отмена')),E('button',{'class':'btn cbi-button-positive','click':function(){var fn=ni.value.trim();if(!fn||!V(fn))return;var fp=R+fn+ts.value;ui.showModal(null,[E('p',{'class':'spinning'},_('Создание'))]);fs.write(fp,'').then(function(){return fs.list(R);}).then(function(fs){r=(fs||[]).sort(function(a,b){return a.name.localeCompare(b.name);});self.TC(fp);ui.hideModal();});}},_('Создать'))]);ui.showModal(_('Новый файл'),[E('div',{},[E('div',{style:'margin-bottom:0.5rem;'},[E('label',{style:'margin-right:0.5rem;'},'Имя:'),ni]),E('div',{},[E('label',{style:'margin-right:0.5rem;'},'Тип:'),ts])]),ft]);ni.focus();},
DF:function(p){if(!P(p,R)||p===C)return;if(!confirm(_('Удалить %s?').format(p.split('/').pop())))return;var self=this;ui.showModal(null,[E('p',{'class':'spinning'},_('Удаление'))]);fs.remove(p).then(function(){return fs.list(R);}).then(function(fs){r=(fs||[]).sort(function(a,b){return a.name.localeCompare(b.name);});if(f===p)self.TC(C);else{self.RTB(document.getElementById('mt-tb'));ui.hideModal();}});},
SAV:function(ir){if(!e)return;var ct=e.getValue();if(f===C)c=ct;ui.showModal(null,[E('p',{'class':'spinning'},_('Сохранение'))]);fs.write(f,ct).then(function(){if(f===C)return fs.exec('/usr/bin/mihomo',['-d','/etc/mihomo','-t',C]).then(function(r){if(r.code!==0)throw new Error((r.stdout||'')+(r.stderr||''));if(ir)return fs.exec('/etc/init.d/mihomo',['restart']);});}).then(function(){ui.hideModal();if(f===C)setTimeout(function(){location.reload();},500);}).catch(function(e){ui.hideModal();ui.addNotification(null,E('p',e.message),'error');});},
CHK:function(){if(f!==C||!e)return;ui.showModal(null,[E('p',{'class':'spinning'},_('Проверка'))]);fs.write(C,e.getValue()).then(function(){return fs.exec('/usr/bin/mihomo',['-d','/etc/mihomo','-t']);}).then(function(r){ui.hideModal();ui.addNotification(null,E('pre',{},(r.stdout||'')+(r.stderr||'')),r.code!==0?'error':'info');}).catch(function(e){ui.hideModal();ui.addNotification(null,E('p',e.message),'error');});},
SA:function(a){if(!A.includes(a))return;ui.showModal(null,[E('p',{'class':'spinning'},_('Выполнение'))]);fs.exec('/etc/init.d/mihomo',[a]).then(function(){location.reload();}).catch(function(e){ui.hideModal();ui.addNotification(null,E('p',e.message),'error');});},
LOGS:function(){fs.exec('/sbin/logread',['-e','mihomo']).then(function(r){var lc=r.stdout||"Нет записей";document.getElementById('mt-ot').textContent=lc;document.getElementById('mt-ob').style.display='block';}).catch(function(e){ui.addNotification(null,E('p',e.message),'error');});},
DASH:function(ct){var h=window.location.hostname,p='9090';try{var m=ct.match(/external-controller:\s*([0-9.]+):(\d+)/);if(m&&m[1]&&m[2]){var ip=m[1].trim();if(/^(\d{1,3}\.){3}\d{1,3}$/.test(ip)&&ip!=='0.0.0.0')h=ip;var pn=parseInt(m[2].trim(),10);if(!isNaN(pn)&&pn>=1&&pn<=65535)p=m[2].trim();}}catch(e){}window.open('http://'+h+':'+p+'/ui/','_blank');}});
VIEW
    
    info "LuCI интерфейс Mihomo готов"
}

finalize() {
    header "Завершение"
    
    subheader "Настройка прав..."
    find /www/luci-static/resources/view -type f -exec chmod 644 {} \; 2>/dev/null || true
    chmod +x /etc/init.d/mihomo /etc/init.d/magitrickle 2>/dev/null || true
    
    subheader "Очистка кэша..."
    rm -rf /tmp/luci-* 2>/dev/null || true
    /etc/init.d/rpcd restart >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    
    echo ""
    success "🎉 Установка завершена!"
    echo ""
    printf "${C_CYAN}╭─ Панели управления ─────────────────${C_RESET}\n"
    printf "${C_CYAN}│${C_RESET} Mihomo:     ${C_GREEN}http://%s:9090/ui/${C_RESET}\n" "$(hostname -I 2>/dev/null | awk '{print $1}' || echo '192.168.1.1')"
    printf "${C_CYAN}│${C_RESET} MagiTrickle:${C_GREEN}http://%s:8080/${C_RESET}\n" "$(hostname -I 2>/dev/null | awk '{print $1}' || echo '192.168.1.1')"
    printf "${C_CYAN}╰─────────────────────────────────────${C_RESET}\n"
    echo ""
    info "LuCI → Services → Mihomo / MagiTrickle"
    echo ""
}

#-------------------------------------------------------------------------------
#  MAIN
#-------------------------------------------------------------------------------
main() {
    require curl wget uci
    
    # Banner
    clear
    printf "${C_CYAN}"
    printf "╔════════════════════════════════════╗\n"
    printf "║  ${C_BOLD}Mihomo + MagiTrickle Installer${C_RESET}${C_CYAN}  ║\n"
    printf "║  v%s • OpenWRT Optimized${C_RESET}${C_CYAN}      ║\n" "$SCRIPT_VERSION"
    printf "╚════════════════════════════════════╝\n"
    printf "${C_RESET}\n"
    
    init_pkgmgr
    log "Система пакетов: ${C_GREEN}${PKG_MGR}${C_RESET}"
    
    install_deps
    install_mihomo
    install_hev
    install_magitrickle
    setup_luci_mihomo
    finalize
}

# Entry point
main "$@"
```
