#!/bin/sh
set -eu

MIHOMO_DIR="/etc/mihomo"
MIHOMO_BIN="/usr/bin/mihomo"
INITD="/etc/init.d/mihomo"
CFG="${MIHOMO_DIR}/config.yaml"

info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
err()  { echo "[ERR ] $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || err "Не найдена команда: $1"; }

check_openwrt() {
  [ -r /etc/openwrt_release ] || err "Это не OpenWrt (нет /etc/openwrt_release)"
  . /etc/openwrt_release
  maj="${DISTRIB_RELEASE%%.*}"
  [ "${maj:-0}" -ge 22 ] || err "Нужен OpenWrt 22.03+ (у тебя: ${DISTRIB_RELEASE:-unknown})"
}

detect_used_arch() {
  # как в твоём примере
  LOCAL_ARCH="$(awk -F"'" '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release 2>/dev/null | head -n1)"
  [ -z "${LOCAL_ARCH:-}" ] && LOCAL_ARCH="$(opkg print-architecture 2>/dev/null | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}')"
  USED_ARCH="$LOCAL_ARCH"
  [ -n "${USED_ARCH:-}" ] || err "Не смог определить USED_ARCH"
  echo "$USED_ARCH"
}

install_deps() {
  need_cmd opkg
  info "opkg update..."
  opkg update >/dev/null 2>&1 || err "opkg update не удался"

  info "Установка зависимостей (curl/ca/kmod-tun)..."
  opkg install curl ca-bundle ca-certificates kmod-tun >/dev/null 2>&1 || err "opkg install не удался"
}

get_latest_tag() {
  need_cmd curl
  tag="$(curl -fsSL -o /dev/null -w '%{url_effective}' "https://github.com/MetaCubeX/mihomo/releases/latest" \
    | sed -n 's#.*/tag/\(v[0-9][0-9.]*\)$#\1#p')"
  [ -n "${tag:-}" ] || err "Не смог определить latest tag"
  echo "$tag"
}

download_and_install() {
  USED_ARCH="$(detect_used_arch)"
  tag="$(get_latest_tag)"

  tmp="/tmp/mihomo.gz"
  url="https://github.com/MetaCubeX/mihomo/releases/download/${tag}/mihomo-linux-${USED_ARCH}-${tag}.gz"

  info "USED_ARCH: $USED_ARCH"
  info "Версия: $tag"
  info "Скачивание: $url"

  mkdir -p "$MIHOMO_DIR" || err "Не могу создать $MIHOMO_DIR"

  curl -fL --retry 3 --retry-delay 2 "$url" -o "$tmp" || err "Не скачалось (возможно, такого arch нет в релизах): $USED_ARCH"

  gzip -dc "$tmp" > "${MIHOMO_BIN}.new" 2>/dev/null || err "Не распаковывается gzip"
  chmod 0755 "${MIHOMO_BIN}.new" || err "chmod не удался"

  if ! "${MIHOMO_BIN}.new" -v >/dev/null 2>&1; then
    rm -f "${MIHOMO_BIN}.new" "$tmp"
    err "Бинарник не запускается (не тот arch/ABI)"
  fi

  mv -f "${MIHOMO_BIN}.new" "$MIHOMO_BIN" || err "Не могу установить $MIHOMO_BIN"
  rm -f "$tmp"
}

write_default_config_if_missing() {
  if [ -f "$CFG" ]; then
    info "Конфиг уже есть: $CFG (не трогаю)"
    return 0
  fi

  info "Создаю минимальный конфиг: $CFG"
  cat >"$CFG" <<'EOF'
mode: rule
ipv6: false
mixed-port: 7890
allow-lan: true
log-level: error
external-controller: 0.0.0.0:9090

dns:
  enable: true
  listen: 0.0.0.0:7880
  ipv6: false
  default-nameserver:
    - 77.88.8.8
    - 8.8.8.8
  nameserver:
    - https://common.dot.dns.yandex.net/dns-query
    - https://dns.google/dns-query

proxies:
  - name: direct
    type: direct

proxy-groups: []

rules:
  - MATCH,DIRECT
EOF
}

write_initd() {
  if [ -f "$INITD" ]; then
    info "init.d уже есть: $INITD (не перезаписываю)"
    return 0
  fi

  info "Создаю сервис: $INITD"
  cat >"$INITD" <<EOF
#!/bin/sh /etc/rc.common
START=99
USE_PROCD=1

PROG="${MIHOMO_BIN}"
CONF="${CFG}"
WORKDIR="${MIHOMO_DIR}"

start_service() {
  procd_open_instance
  procd_set_param command "\$PROG" -d "\$WORKDIR" -f "\$CONF"
  procd_set_param respawn
  procd_set_param stdout 1
  procd_set_param stderr 1
  procd_close_instance
}

reload_service() {
  stop
  start
}
EOF
  chmod 0755 "$INITD" || err "chmod init.d не удался"
}

enable_and_start() {
  info "Включаю и запускаю сервис..."
  "$INITD" enable >/dev/null 2>&1 || true
  "$INITD" restart >/dev/null 2>&1 || "$INITD" start >/dev/null 2>&1 || err "Не смог запустить mihomo"
}

main() {
  check_openwrt
  install_deps
  download_and_install
  write_default_config_if_missing
  write_initd
  enable_and_start
  info "Готово. Проверка: $MIHOMO_BIN -v ; logread -e mihomo"
}

main "$@"
