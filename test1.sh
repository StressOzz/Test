#!/bin/bash

# Улучшенная версия скрипта для автоматической настройки Zapret.
# Изменения:
# - Переход на bash для лучшей поддержки массивов и функций.
# - Опции теперь в массивах для избежания проблем с разбором строк.
# - Улучшенная функция pick_random для работы с массивами.
# - Проверка существования файлов, директорий и прав.
# - Обработка ошибок для curl, сервиса и т.д.
# - Логирование в файл /var/log/zapret-auto-config.log.
# - Проверка успешности рестарта сервиса (простая проверка процесса).
# - Если токены Telegram пустые, пропускаем отправку сообщений.
# - Увеличен таймаут проверки YouTube и добавлена проверка HTTP статуса.
# - Более robust sed для замены конфига (учитывает пробелы).
# - Добавлена проверка на существование lock-директории.
# - Опционально: больше попыток, но с экспоненциальным backoff в sleep.

(
  # Создаем директорию для lock если не существует
  LOCK_DIR="/var/run"
  [ ! -d "$LOCK_DIR" ] && sudo mkdir -p "$LOCK_DIR" && sudo chmod 755 "$LOCK_DIR"

  LOCK_FILE="$LOCK_DIR/zapret_config.lock"
  exec 9>"$LOCK_FILE"
  flock -n 9 || {
    echo "Скрипт уже запущен, выход." >&2
    exit 1
  }

  # Логирование
  LOG_FILE="/var/log/zapret-auto-config.log"
  log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
  }

  CONFIG_FILE="/opt/zapret/config"
  SERVICE_SCRIPT="/etc/init.d/zapret"
  TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"  # Можно задать через env
  TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"     # Можно задать через env
  MAX_ATTEMPTS=15  # Увеличено для надежности
  YOUTUBE_URL="https://www.youtube.com"
  CHECK_TIMEOUT=15  # Увеличен таймаут

  # Массивы опций для правильного выбора
  declare -a FILTER_TCP_OPTIONS=("80" "443" "80,443")
  declare -a FILTER_UDP_OPTIONS=("443" "50000-65535" "50000-50100")
  declare -a DPI_DESYNC_MODES=("fake" "fakedsplit" "multidisorder" "fakeddisorder" "split" "split2")
  declare -a DPI_DESYNC_FOOLING=("badsum" "md5sig" "badseq" "padencap" "none")
  declare -a DPI_DESYNC_REPEATS=("6" "8" "11" "16")
  declare -a DPI_DESYNC_TTLS=("2" "4")
  declare -a HOSTLISTS=("/opt/zapret/ipset/zapret-hosts-google.txt" "/opt/zapret/ipset/zapret-hosts-user.txt")
  declare -a FAKE_TLS_FILES=("/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" "")
  declare -a FAKE_QUIC_FILES=("/opt/zapret/files/fake/quic_initial_www_google_com.bin" "")

  # Проверки prerequisites
  [ ! -f "$CONFIG_FILE" ] && { log "ERROR: Config file $CONFIG_FILE not found."; exit 1; }
  [ ! -w "$CONFIG_FILE" ] && { log "ERROR: Config file $CONFIG_FILE not writable."; exit 1; }
  [ ! -x "$SERVICE_SCRIPT" ] && { log "ERROR: Service script $SERVICE_SCRIPT not executable."; exit 1; }
  for hostlist in "${HOSTLISTS[@]}"; do
    [ ! -f "$hostlist" ] && { log "WARNING: Hostlist $hostlist not found."; }
  done

  pick_random() {
    local -n array_ref=$1  # Намеринг для ссылки на массив
    local count=${#array_ref[@]}
    [ $count -eq 0 ] && { echo ""; return; }
    local index=$(( RANDOM % count ))
    echo "${array_ref[$index]}"
  }

  send_telegram() {
    local message="$1"
    [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ] && {
      log "WARNING: Telegram tokens not set, skipping message."
      return 0
    }
    if curl -s --max-time 10 -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" -d text="$message" >/dev/null 2>&1; then
      log "Telegram message sent."
    else
      log "ERROR: Failed to send Telegram message."
    fi
  }

  check_youtube() {
    # Проверяем HTTP статус (должен быть 200 или redirect)
    local status=$(curl -s --max-time "$CHECK_TIMEOUT" -I -w "%{http_code}" "$YOUTUBE_URL" -o /dev/null 2>&1)
    [ "$status" = "200" ] || [ "$status" = "301" ] || [ "$status" = "302" ]
  }

  is_service_running() {
    # Простая проверка: ищем процессы zapret (адаптировать под реальные процессы, напр. nfqws)
    pgrep -f "nfqws\|zapret" >/dev/null 2>&1
  }

  generate_config() {
    local tcp_filter udp_filter dpi_mode dpi_fooling dpi_repeats dpi_ttl hostlist fake_tls fake_quic
    tcp_filter=$(pick_random FILTER_TCP_OPTIONS)
    udp_filter=$(pick_random FILTER_UDP_OPTIONS)
    dpi_mode=$(pick_random DPI_DESYNC_MODES)
    dpi_fooling=$(pick_random DPI_DESYNC_FOOLING)
    dpi_repeats=$(pick_random DPI_DESYNC_REPEATS)
    dpi_ttl=$(pick_random DPI_DESYNC_TTLS)
    hostlist=$(pick_random HOSTLISTS)
    fake_tls=$(pick_random FAKE_TLS_FILES)
    fake_quic=$(pick_random FAKE_QUIC_FILES)

    local config="--filter-tcp=$tcp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"
    config="$config --dpi-desync-autottl=$dpi_ttl"
    config="$config --dpi-desync-fooling=$dpi_fooling"
    config="$config --dpi-desync-repeats=$dpi_repeats"
    if [ -n "$fake_tls" ] && [ "$fake_tls" != "" ]; then
      [ -f "$fake_tls" ] && config="$config --dpi-desync-fake-tls=$fake_tls" || log "WARNING: Fake TLS file $fake_tls not found, skipping."
    fi
    config="$config --new"
    config="$config --filter-udp=$udp_filter $hostlist"
    config="$config --dpi-desync=$dpi_mode"  # Повтор для UDP, как в оригинале
    config="$config --dpi-desync-repeats=$dpi_repeats"
    if [ -n "$fake_quic" ] && [ "$fake_quic" != "" ]; then
      [ -f "$fake_quic" ] && config="$config --dpi-desync-fake-quic=$fake_quic" || log "WARNING: Fake QUIC file $fake_quic not found, skipping."
    fi

    echo "$config"
  }

  replace_config_line() {
    local new_value="$1"
    # Более robust sed: удаляем старую строку и добавляем новую в конец, если не существует
    if grep -q "^NFQWS_OPT=" "$CONFIG_FILE" 2>/dev/null; then
      sed -i "/^NFQWS_OPT=/d" "$CONFIG_FILE"
    fi
    echo "NFQWS_OPT=\"$new_value\"" >> "$CONFIG_FILE"
    log "Config updated: NFQWS_OPT=\"$new_value\""
  }

  restart_zapret() {
    log "Restarting Zapret service..."
    if $SERVICE_SCRIPT restart >/dev/null 2>&1; then
      # Ждем запуска с backoff
      local wait=5
      while [ $wait -le 30 ]; do
        sleep $wait
        if is_service_running; then
          log "Zapret service restarted successfully."
          return 0
        fi
        wait=$((wait * 2))
      done
      log "ERROR: Zapret service failed to restart."
      return 1
    else
      log "ERROR: Failed to restart Zapret service."
      return 1
    fi
  }

  log "Starting YouTube accessibility check..."
  if check_youtube; then
    log "YouTube is accessible, no bypass needed. Exiting."
    exit 0
  fi

  send_telegram "⚠️ YouTube недоступен! Начинаем подбор обхода Zapret..."

  local attempt=0
  while [ $attempt -lt $MAX_ATTEMPTS ]; do
    attempt=$((attempt + 1))
    log "Attempt #$attempt..."

    local new_config=$(generate_config)
    log "Generated config: $new_config"
    replace_config_line "$new_config"
    if ! restart_zapret; then
      log "Failed to restart service on attempt #$attempt, skipping check."
      continue
    fi

    if check_youtube; then
      send_telegram "✅ Zapret обход настроен успешно на попытке #$attempt! Конфиг:\n$new_config"
      log "YouTube accessible with new config. Success!"
      exit 0
    else
      log "YouTube still inaccessible on attempt #$attempt."
    fi
  done

  send_telegram "❌ Zapret обход НЕ удалось настроить за $MAX_ATTEMPTS попыток."
  log "Failed after $MAX_ATTEMPTS attempts."
  exit 1

) 9>"$LOCK_FILE"
