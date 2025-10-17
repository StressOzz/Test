#!/bin/sh

(
  flock -n 9 || {
    echo "Скрипт уже запущен, выход."
    exit 1
  }

  # Configurable variables
  CONFIG_FILE="/opt/zapret/config"
  SERVICE_SCRIPT="/etc/init.d/zapret"
  TELEGRAM_BOT_TOKEN=""  # вставь токен бота
  TELEGRAM_CHAT_ID=""    # вставь id чата
  LOGFILE="/var/log/zapret-config.log"
  MAX_ATTEMPTS=10
  YOUTUBE_URL="https://www.youtube.com"

  FILTER_TCP_OPTIONS="80 443 80,443"
  FILTER_UDP_OPTIONS="443 50000-65535 50000-50100"
  DPI_DESYNC_MODES="fake fakedsplit multidisorder fakeddisorder split split2"
  DPI_DESYNC_FOOLING="badsum md5sig badseq padencap none"
  DPI_DESYNC_REPEATS="6 8 11 16"
  DPI_DESYNC_TTLS="2 4"
  HOSTLISTS="/opt/zapret/ipset/zapret-hosts-google.txt /opt/zapret/ipset/zapret-hosts-user.txt"
  FAKE_TLS_FILES="/opt/zapret/files/fake/tls_clienthello_www_google_com.bin none"
  FAKE_QUIC_FILES="/opt/zapret/files/fake/quic_initial_www_google_com.bin none"

  # Logging setup
  mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null
  log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $*" | tee -a "$LOGFILE" >&2
  }

  pick_random() {
    items="$1"
    set -- $items
    count=$#
    if [ $count -eq 0 ]; then
      echo ""
      return
    fi
    # POSIX-friendly random: use /dev/urandom if available, fallback to date
    r=$(od -An -N1 -tu1 /dev/urandom 2>/dev/null | tr -d ' \n' || echo $(($(date +%s) % 256)))
    index=$(( (r % count) + 1 ))
    i=1
    for item; do
      if [ $i -eq $index ]; then
        echo "$item"
        return
      fi
      i=$((i + 1))
    done
  }

  send_telegram() {
    message="$1"
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
      log "Telegram not configured, skipping notification: $message"
      return 0
    fi
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d text="$message" >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log "Failed to send Telegram message"
    fi
  }

  check_youtube() {
    curl -s --max-time 10 --connect-timeout 5 -I "$YOUTUBE_URL" >/dev/null 2>&1
    return $?
  }

  generate_config() {
    tcp_filter=$(pick_random "$FILTER_TCP_OPTIONS")
    udp_filter=$(pick_random "$FILTER_UDP_OPTIONS")
    dpi_mode=$(pick_random "$DPI_DESYNC_MODES")
    dpi_fooling=$(pick_random "$DPI_DESYNC_FOOLING")
    dpi_repeats=$(pick_random "$DPI_DESYNC_REPEATS")
    dpi_ttl=$(pick_random "$DPI_DESYNC_TTLS")

    # Pick valid hostlist
    hostlist=""
    attempts=0
    while [ -z "$hostlist" ] && [ $attempts -lt 3 ]; do
      candidate=$(pick_random "$HOSTLISTS")
      if [ -f "$candidate" ]; then
        hostlist="$candidate"
      fi
      attempts=$((attempts + 1))
    done
    if [ -z "$hostlist" ]; then
      log "No valid hostlist found, exiting."
      exit 1
    fi

    config="--filter-tcp=$tcp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"
    config="$config --dpi-desync-autottl=$dpi_ttl"
    config="$config --dpi-desync-fooling=$dpi_fooling"
    config="$config --dpi-desync-repeats=$dpi_repeats"

    fake_tls=$(pick_random "$FAKE_TLS_FILES")
    if [ "$fake_tls" != "none" ]; then
      if [ -f "$fake_tls" ]; then
        config="$config --dpi-desync-fake-tls=$fake_tls"
      else
        log "Warning: fake TLS file '$fake_tls' not found, skipping."
      fi
    fi

    config="$config --new"
    config="$config --filter-udp=$udp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"
    config="$config --dpi-desync-repeats=$dpi_repeats"

    fake_quic=$(pick_random "$FAKE_QUIC_FILES")
    if [ "$fake_quic" != "none" ]; then
      if [ -f "$fake_quic" ]; then
        config="$config --dpi-desync-fake-quic=$fake_quic"
      else
        log "Warning: fake QUIC file '$fake_quic' not found, skipping."
      fi
    fi

    echo "$config"
  }

  replace_config_line() {
    new_value="$1"
    if [ ! -f "$CONFIG_FILE" ]; then
      log "Config file $CONFIG_FILE does not exist, creating with new value."
      echo "NFQWS_OPT=\"$new_value\"" > "$CONFIG_FILE"
      return
    fi
    if ! grep -q "^NFQWS_OPT=" "$CONFIG_FILE" 2>/dev/null; then
      log "No NFQWS_OPT line found, appending new value."
      echo "NFQWS_OPT=\"$new_value\"" >> "$CONFIG_FILE"
      return
    fi
    if sed -i "/^NFQWS_OPT=/c\NFQWS_OPT=\"$new_value\"" "$CONFIG_FILE" 2>/dev/null; then
      # Verify update (approximate check)
      if ! grep -q "^NFQWS_OPT=\"$new_value\"" "$CONFIG_FILE" 2>/dev/null; then
        log "Warning: Config update verification failed (possible quoting issue)."
      fi
    else
      log "Failed to update config file."
      exit 1
    fi
  }

  restart_zapret() {
    log "Restarting zapret service..."
    $SERVICE_SCRIPT restart >/dev/null 2>&1
    if [ $? -ne 0 ]; then
      log "Warning: zapret restart failed."
    fi
    sleep 15  # Allow time for service to stabilize
  }

  log "=== Starting zapret config optimization ==="
  if ! [ -f "$CONFIG_FILE" ]; then
    log "Error: Config file $CONFIG_FILE not found!"
    exit 1
  fi
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
  log "Backup created: ${CONFIG_FILE}.bak"

  log "Проверяем доступность YouTube..."
  if check_youtube; then
    log "YouTube доступен, обход не требуется. Выход."
    send_telegram "✅ YouTube доступен, скрипт завершен без изменений."
    exit 0
  fi

  send_telegram "⚠️ YouTube недоступен! Начинаем подбор обхода Zapret..."

  attempt=0
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    log "Попытка #$attempt из $MAX_ATTEMPTS..."

    new_config=$(generate_config)
    log "Новый конфиг: $new_config"
    replace_config_line "$new_config"
    restart_zapret

    if check_youtube; then
      send_telegram "✅ Zapret обход настроен успешно на попытке #$attempt! Конфиг:\n\`\`\`$new_config\`\`\`"
      log "YouTube доступен, конфиг успешно подобран."
      exit 0
    else
      log "YouTube недоступен с текущим конфигом."
    fi
  done

  log "❌ Не удалось подобрать рабочий конфиг за $MAX_ATTEMPTS попыток."
  cp "${CONFIG_FILE}.bak" "$CONFIG_FILE"
  log "Восстановлен оригинальный конфиг из бэкапа."
  restart_zapret
  send_telegram "❌ Zapret обход НЕ удалось настроить за $MAX_ATTEMPTS попыток. Восстановлен оригинальный конфиг."
  exit 1

) 9>/var/run/zapret_config.lock
