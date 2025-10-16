#!/bin/sh
# zapret auto-picker (OpenWRT 24+)
# Авто-подбор конфигурации, без вопросов, без Telegram
# Выводит результат в "Zapret" формате (текстом) и записывает NFQWS_OPT в конфиг
# Работает в ash / BusyBox

set -eu

LOCKDIR="/var/lock/zapret_config.lock"
CONFIG_FILE="/opt/zapret/config"
SERVICE_SCRIPT="/etc/init.d/zapret"
BACKUP_DIR="/var/backups/zapret_auto"
LOGFILE="/var/log/zapret_auto_picker.log"

MAX_ATTEMPTS=10
YOUTUBE_URL="https://www.youtube.com"

# option pools (простые пробел-разделённые строки)
FILTER_TCP_OPTIONS="80 443 80,443"
FILTER_UDP_OPTIONS="443 50000-65535 50000-50100"
DPI_DESYNC_MODES="fake fakedsplit multidisorder fakeddisorder split split2"
DPI_DESYNC_FOOLING="badsum md5sig badseq padencap none"
DPI_DESYNC_REPEATS="6 8 11 16"
DPI_DESYNC_TTLS="2 4"
HOSTLISTS="/opt/zapret/ipset/zapret-hosts-google.txt /opt/zapret/ipset/zapret-hosts-user.txt"
FAKE_TLS_FILES="/opt/zapret/files/fake/tls_clienthello_www_google_com.bin ''"
FAKE_QUIC_FILES="/opt/zapret/files/fake/quic_initial_www_google_com.bin ''"

mkdir -p "$(dirname "$LOGFILE")" "$BACKUP_DIR" || true

log() {
  echo "$(date +'%F %T') $*" >> "$LOGFILE" 2>/dev/null || true
}

# atomic lock via mkdir
lock_acquire() {
  if mkdir "$LOCKDIR" 2>/dev/null; then
    trap 'rm -rf "$LOCKDIR"; exit' INT TERM EXIT
    return 0
  fi
  return 1
}

lock_release() {
  rm -rf "$LOCKDIR" || true
  trap - INT TERM EXIT
}

# robust random index (no $RANDOM)
rand_index() {
  count=$1
  rnd=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ' || true)
  if [ -z "$rnd" ]; then
    rnd=$(date +%s)
  fi
  idx=$(( (rnd % count) + 1 ))
  echo "$idx"
}

# pick random token from space-separated list argument
pick_random() {
  list="$1"
  set -- $list
  count=$#
  if [ "$count" -eq 0 ]; then
    echo ""
    return
  fi
  idx=$(rand_index "$count")
  i=1
  for item in "$@"; do
    if [ "$i" -eq "$idx" ]; then
      echo "$item"
      return
    fi
    i=$((i+1))
  done
}

# quick YouTube check
check_youtube() {
  # try head and check HTTP code
  if curl -s -I --max-time 8 "$YOUTUBE_URL" 2>/dev/null | head -n1 | grep -qi "HTTP/"; then
    code=$(curl -s -I --max-time 8 "$YOUTUBE_URL" 2>/dev/null | head -n1 | awk '{print $2}' || true)
    case "$code" in
      200|301|302|303|307|308) return 0 ;;
    esac
  fi
  # fallback small GET
  if curl -s --max-time 10 --head "$YOUTUBE_URL" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# safely replace or append NFQWS_OPT= line; backup original
replace_config_line() {
  new_value="$1"
  [ -f "$CONFIG_FILE" ] || touch "$CONFIG_FILE"
  cp -a "$CONFIG_FILE" "${BACKUP_DIR}/config.$(date +%s)" || true

  if grep -q '^NFQWS_OPT=' "$CONFIG_FILE" 2>/dev/null; then
    # replace line
    awk -v nv="$new_value" 'BEGIN{q="\""} /^NFQWS_OPT=/{print "NFQWS_OPT=" q nv q; next} {print}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  else
    echo "NFQWS_OPT=\"$new_value\"" >> "$CONFIG_FILE"
  fi
  chmod 600 "$CONFIG_FILE" || true
}

restart_zapret() {
  if [ -x "$SERVICE_SCRIPT" ]; then
    "$SERVICE_SCRIPT" restart >/dev/null 2>&1 || true
    sleep 10
  else
    log "WARN: service script $SERVICE_SCRIPT not found"
  fi
}

# main
if ! lock_acquire; then
  echo "Script already running — exit." >&2
  exit 1
fi

log "Start picker"

if check_youtube; then
  log "YouTube available — no action."
  lock_release
  exit 0
fi

attempt=0
success=0
best_tcp_cfg=""
best_udp_cfg=""
best_full_line=""

while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  log "Attempt #$attempt"

  tcp_filter=$(pick_random "$FILTER_TCP_OPTIONS")
  udp_filter=$(pick_random "$FILTER_UDP_OPTIONS")
  dpi_mode_tcp=$(pick_random "$DPI_DESYNC_MODES")
  dpi_mode_udp=$(pick_random "$DPI_DESYNC_MODES")
  dpi_fooling_tcp=$(pick_random "$DPI_DESYNC_FOOLING")
  dpi_repeats_tcp=$(pick_random "$DPI_DESYNC_REPEATS")
  dpi_repeats_udp=$(pick_random "$DPI_DESYNC_REPEATS")
  dpi_ttl_tcp=$(pick_random "$DPI_DESYNC_TTLS")
  hostlist=$(pick_random "$HOSTLISTS")
  fake_tls=$(pick_random "$FAKE_TLS_FILES")
  fake_quic=$(pick_random "$FAKE_QUIC_FILES")

  # build tcp section (as lines)
  tcp_lines="--filter-tcp=${tcp_filter}"
  # add hostlist if exists (file)
  if [ -n "$hostlist" ] && [ -f "$hostlist" ]; then
    tcp_lines="${tcp_lines} ${hostlist}"
  fi
  tcp_lines="${tcp_lines}\n\n--dpi-desync=${dpi_mode_tcp}"
  tcp_lines="${tcp_lines}\n--dpi-desync-repeats=${dpi_repeats_tcp}"
  tcp_lines="${tcp_lines}\n--dpi-desync-fooling=${dpi_fooling_tcp}"
  tcp_lines="${tcp_lines}\n--dpi-desync-autottl=${dpi_ttl_tcp}"
  # fake tls (only if file exists)
  if [ -n "$fake_tls" ] && [ "$fake_tls" != "''" ] && [ -f "$fake_tls" ]; then
    tcp_lines="${tcp_lines}\n--dpi-desync-fake-tls=${fake_tls}"
  fi

  # build udp section
  udp_lines="--filter-udp=${udp_filter}"
  if [ -n "$hostlist" ] && [ -f "$hostlist" ]; then
    udp_lines="${udp_lines} ${hostlist}"
  fi
  udp_lines="${udp_lines}\n\n--dpi-desync=${dpi_mode_udp}"
  udp_lines="${udp_lines}\n--dpi-desync-repeats=${dpi_repeats_udp}"
  # fake quic
  if [ -n "$fake_quic" ] && [ "$fake_quic" != "''" ] && [ -f "$fake_quic" ]; then
    udp_lines="${udp_lines}\n--dpi-desync-fake-quic=${fake_quic}"
  fi

  # final NFQWS_OPT single-line (space separated, safe)
  # join tcp options (without literal \n)
  nfqws_line="--filter-tcp=${tcp_filter}"
  if [ -n "$hostlist" ] && [ -f "$hostlist" ]; then
    nfqws_line="${nfqws_line} ${hostlist}"
  fi
  nfqws_line="${nfqws_line} --dpi-desync=${dpi_mode_tcp} --dpi-desync-repeats=${dpi_repeats_tcp} --dpi-desync-fooling=${dpi_fooling_tcp} --dpi-desync-autottl=${dpi_ttl_tcp}"
  if [ -n "$fake_tls" ] && [ "$fake_tls" != "''" ] && [ -f "$fake_tls" ]; then
    nfqws_line="${nfqws_line} --dpi-desync-fake-tls=${fake_tls}"
  fi
  nfqws_line="${nfqws_line} --new"
  nfqws_line="${nfqws_line} --filter-udp=${udp_filter}"
  if [ -n "$hostlist" ] && [ -f "$hostlist" ]; then
    nfqws_line="${nfqws_line} ${hostlist}"
  fi
  nfqws_line="${nfqws_line} --dpi-desync=${dpi_mode_udp} --dpi-desync-repeats=${dpi_repeats_udp}"
  if [ -n "$fake_quic" ] && [ "$fake_quic" != "''" ] && [ -f "$fake_quic" ]; then
    nfqws_line="${nfqws_line} --dpi-desync-fake-quic=${fake_quic}"
  fi

  log "Trying config: $nfqws_line"
  replace_config_line "$nfqws_line"
  restart_zapret

  if check_youtube; then
    log "Success on attempt #$attempt"
    success=1
    best_tcp_cfg="$tcp_lines"
    best_udp_cfg="$udp_lines"
    best_full_line="$nfqws_line"
    break
  else
    log "Attempt #$attempt failed"
  fi
done

if [ "$success" -eq 0 ]; then
  log "All attempts failed"
  lock_release
  echo "ERROR: не удалось подобрать обход за $MAX_ATTEMPTS попыток" >&2
  exit 2
fi

# print result in Zapret format (as requested)
# replace literal \n with real newlines
printf "%b\n\n%b\n\n%b\n" "$best_tcp_cfg" "$best_udp_cfg" "" 

# also save condensed one-line NFQWS_OPT into a file for quick copy
echo "$best_full_line" > /tmp/zapret_best_line.txt
log "Saved best line to /tmp/zapret_best_line.txt"

lock_release
exit 0
