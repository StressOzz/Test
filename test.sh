
#!/bin/sh
# zapret_autoconfig - автоматическая настройка обхода блокировок
# Совместимость: OpenWRT ash

#########################################
# КОНФИГУРАЦИЯ
#########################################

ZAPRET_DOWNLOAD_URL=$(curl -s https://api.github.com/repos/bol-van/zapret/releases/latest \
					| jq -r '.assets[] | select(.name | contains ("openwrt")) | .browser_download_url')

# Пути и директории
ZAPRET_ORIG_DIR="/opt/zapret_orig"
ZAPRET_MAIN_DIR="/opt/zapret"
ZAPRET_CONFIG_FILE="/etc/config/zapret"
CONFIG_DIR="/etc/zapret_autoconfig"
BACKUP_DIR="${CONFIG_DIR}/backup"
TEMP_DIR="/tmp/zapret"
RESTORE_SCRIPT="${CONFIG_DIR}/restore_services_state.sh"
UNINSTALL_FILE="${CONFIG_DIR}/uninstall"
FOUND_STRATEGY="${CONFIG_DIR}/found_strategy.txt"
PRESET_STRATEGY="${CONFIG_DIR}/preset_strategy.txt"

# Сервисы для управления (список через пробел)
MANAGED_SERVICES="zapret ruantiblock youtubeUnblock podkop sing-box"

# Параметры тестирования
TEST_ADDRESS="rr5---sn-385ou-8v1s.googlevideo.com"
TEST_URL="https://www.youtube.com"
USER_AGENT="Mozilla"
CURL_MAX_TIME=1.5

# Цвета для вывода
if [ -t 1 ]; then
    # Если это терминал, определяем цвета
    RED='\033[1;91m'
    GREEN='\033[1;92m'
    YELLOW='\033[1;93m'
    BLUE='\033[1;94m'
    NC='\033[0m' # No Color - сброс
else
    # Если вывод перенаправлен (например, в файл), определяем пустые строки
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    NC=''
fi

# Версия
VERSION="zapret_autoconfig v0.1.0 (latest)"

# Глобальные переменные состояния
OPKG_UPDATED=0
MAX_STRATEGIES=5
FULLDELETE=0

#########################################
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
#########################################

# Логирование
log_info() {
	echo "[INFO] $*"
}

log_warn() {
	printf "${YELLOW}[WARN] %s${NC}\n" "$*" >&2
}

log_error() {
	printf "${RED}[ERROR] %s${NC}\n" "$*" >&2
}

log_success() {
	printf "${GREEN}[SUCCESS] %s${NC}\n" "$*"
}

# Проверка прав
check_root() {
	if [ "$(id -u)" -ne 0 ]; then
		log_error "Требуются права root"
		exit 1
	fi
}

# Безопасное скачивание файла
safe_download() {
	_url="$1"
	_dest="$2"
	
	log_info "Скачивание: $_url -> $_dest"
	
    # Создаем директорию
    mkdir -p "$(dirname "$_dest")" || {
        log_error "Не могу создать директорию для $_dest"
        return 1
    }
	
	
	if ! wget -q --timeout=10 -O "$_dest.tmp" "$_url" 2>/dev/null; then
		if ! curl -L -f --max-time 10 -s "$_url" -o "$_dest.tmp"; then
			log_error "Не удалось скачать $_url"
			return 1
		fi
	fi
	
	# Проверка, что файл не пустой
	if [ ! -s "$_dest.tmp" ]; then
		log_error "Скачанный файл пуст: $_url"
		rm -f "$_dest.tmp"
		return 1
	fi
	
	mv "$_dest.tmp" "$_dest"
	chmod +x "$_dest" 2>/dev/null || true
	return 0
}

# Проверка состояния сервиса
service_is_enabled() {
	_service="$1"
	if [ -x "/etc/init.d/$_service" ]; then
		/etc/init.d/"$_service" enabled >/dev/null 2>&1
		return $?
	fi
	return 1
}

service_is_running() {
	_service="$1"
	if [ -x "/etc/init.d/$_service" ]; then
		/etc/init.d/"$_service" running >/dev/null 2>&1
		return $?
	fi
	return 1
}

# Подсчет строк в файле (совместимый с ash)
strategy_counter() {
	local FILE="$1"
	# Подсчет количества строк в файле
	if [ ! -f "$FILE" ]; then
		#echo "Файл $FILE не найден"
		echo "0"
	else
		wc -l <"$FILE"
	fi
}


check_owrt_version() {

	# _version=$(awk -F"'" '/DISTRIB_RELEASE/ {print $2}' /etc/openwrt_release)
	. /etc/openwrt_release
	_version="$DISTRIB_RELEASE"
	# Убираем всё после первой точки для проверки мажорной версии
	# _major_ver=$(echo "$_version" | awk -F. '{print $1}')
	_major_ver=${_version%%.*}
	# Проверяем численно
	if ! [ "$_major_ver" -ge 24 ] 2>/dev/null; then
		log_error "Ошибка: Установлена OpenWRT версии $_version"
		log_error "Требуется версия 24.x.x или выше"
		exit 1
	fi

	echo -e "${GREEN}OpenWRT версии $_version - OK${NC}"
	
}


#########################################
# ОСНОВНЫЕ ФУНКЦИИ
#########################################


# СОХРАНЕНИЕ СОСТОЯНИЯ СЕРВИСОВ

save_services_state() {
	log_info "Сохранение состояния сервисов..."
	
	# Создаем директории
	mkdir -p "$(dirname "$RESTORE_SCRIPT")"
	
	# Заголовок скрипта восстановления
	cat > "$RESTORE_SCRIPT" << 'EOF'
#!/bin/sh
# Восстановление состояния сервисов
# Сгенерировано автоматически
EOF
	
	# Сохраняем состояние важных сервисов
	for _service in $MANAGED_SERVICES; do
		if service_is_enabled "$_service"; then
			echo "service $_service enable" >> "$RESTORE_SCRIPT"
			echo "service $_service start" >> "$RESTORE_SCRIPT"
		else
			echo "service $_service disable" >> "$RESTORE_SCRIPT"
			echo "service $_service stop" >> "$RESTORE_SCRIPT"			
		fi
	done
	
	# Добавляем команду удаления zapret, если он не установлен
	if ! opkg list-installed | grep -q "^zapret "; then
		cat >> "$RESTORE_SCRIPT" << 'EOF'

# Удаление zapret и зависимостей
opkg remove --force-removal-of-dependent-packages \
	zapret \
	luci-app-zapret
EOF
	fi
	
	chmod +x "$RESTORE_SCRIPT"
	log_success "Состояние сервисов сохранено"
}

# СОЗДАНИЕ РЕЗЕРВНОЙ КОПИИ

create_backup() {
	_backup_file=""
	
	# Создаем директории
	mkdir -p "$BACKUP_DIR" "$CONFIG_DIR"
	
	# Резервная копия конфигурации zapret
	if [ -f "/etc/config/zapret" ]; then
		_backup_file="${BACKUP_DIR}/config_zapret_$(date +'%Y-%m-%d_%H-%M-%S')"
		cp -f "/etc/config/zapret" "$_backup_file"
		echo "$_backup_file" > "$UNINSTALL_FILE"
		# log_info "Резервная копия создана: $_backup_file"
	else
		printf "" # log_warn "Файл конфигурации zapret не найден"
	fi
	
	# Запрос на создание резервной копии роутера
	echo
	printf "${YELLOW}ВАЖНО: Создайте полную резервную копию настроек роутера!${NC}\n"
	echo
	printf "Создана ли резервная копия? (y/N): "
	read -r _answer
	if [ "$_answer" != "y" ] && [ "$_answer" != "Y" ]; then
		log_error "Резервная копия не создана. Выход."
		exit 1
	fi
}

# УСТАНОВКА НЕОБХОДИМЫХ ПАКЕТОВ

install_requirements() {
	_retries=3
	_i=1
	
	log_info "Установка необходимых пакетов..."
	echo
	echo -e "${GREEN}В ответ на все вопросы просто жмите Enter${NC}"
	echo
	sleep 3   

	# Обновление списка пакетов с проверкой ошибок в логе
	while [ "$_i" -le "$_retries" ]; do
		log_info "Попытка обновления списка пакетов ($_i/$_retries)"
		
		opkg update > /tmp/opkg_update_log 2>&1
		
		# Проверяем на ключевые слова об ошибках
		if grep -qi "failed\|error\|unable\|not found" /tmp/opkg_update_log; then
			log_warn "Обнаружены ошибки в логе, повтор..."
		else
			# Нет ключевых слов об ошибках
			log_success "Списки обновлены (без явных ошибок)"
			OPKG_UPDATED=1
			break
		fi
		
		if [ "$_i" -eq "$_retries" ]; then
			log_error "Не удалось обновить список пакетов после $_retries попыток"
			echo ""
			echo "=== АНАЛИЗ ЛОГА ==="
			
			# Показываем только строки с ошибками в цвете 208
			awk 'tolower($0) ~ /failed|error|unable|not found|bad address|wget returned/ {
				print "\033[38;5;208m" $0 "\033[0m"
				next
			}
			{print}' /tmp/opkg_update_log
			
			echo "=== КОНЕЦ ==="
			exit 1
		fi
		
		sleep 2
		_i=$((_i + 1))
	done
	
	echo
	# Установка пакетов
	for _pkg in curl ipset libcurl jq zapret luci-app-zapret luci-app-youtubeUnblock; do
		printf "[INFO] Установка $_pkg... "
		if ! opkg list-installed "$_pkg" | grep -q "^${_pkg}"; then
			if ! opkg install --force-reinstall "$_pkg" >/dev/null 2>&1; then
				log_error "Не удалось установить $_pkg"
				return 1
			else 
				echo "$_pkg установлен"
			fi
			else echo "Пакет $_pkg уже установлен. Пропускаем."
		fi
	done
	echo
	

	# УСТАНОВКА ОРИГИНАЛЬНОГО ZAPRET
	
	# Скачиваем новейший оригинальный zapret
	safe_download $ZAPRET_DOWNLOAD_URL $TEMP_DIR/zapret-latest.tar.gz

	# Устанавливаем оригинальный zapret
	mkdir -p $ZAPRET_ORIG_DIR
	cd $TEMP_DIR
	tar -xvzf $TEMP_DIR/zapret-latest.tar.gz
	rm -v $TEMP_DIR/zapret-latest.tar.gz
	cp -vr $TEMP_DIR/zapret-v*/* /opt/zapret_orig/
	rm -rfv zapret-v*

	cd
	cd $ZAPRET_ORIG_DIR
	printf '\n\n\n' | ./install_bin.sh
	printf '\n\n\n' | ./install_prereq.sh
	
	# Удаляем лишние бинарники
	mv $ZAPRET_ORIG_DIR/binaries/linux-arm64 /tmp/
	rm -r $ZAPRET_ORIG_DIR/binaries/*
	mv /tmp/linux-arm64 /opt/zapret_orig/binaries/
	
	# Установка wrapper'а для сканирования
	safe_download https://raw.githubusercontent.com/kkkkCampbell/trash/refs/heads/zapret_autoconfig/blockcheck_wrapper.sh $ZAPRET_ORIG_DIR/blockcheck_wrapper.sh 
	
	/etc/init.d/zapret enable
	/etc/init.d/zapret start
	
	return 0
}

# ФУНКЦИЯ ПОДБОРА СТРАТЕГИЙ

strategy_scan() {
	clear
	
	# Параметры тестирования
	export SCANLEVEL="standart"
	export REPEATS=3
	export PARALLEL=1
	export SKIP_TPWS=1
	export ENABLE_HTTP=0
	export ENABLE_HTTPS_TLS12=1
	export ENABLE_HTTPS_TLS13=1
	export FWTYPE="nftables"
	export DOMAINS="rr5---sn-385ou-8v1s.googlevideo.com"
	export IPVS=4
	export CURL_MAX_TIME=1.5
	export BATCH=1
	
	# Останавливаем youtubeUnblock
	log_info "Останавливаем youtubeUnblock"
	/etc/init.d/youtubeUnblock stop >/dev/null 2>&1
	/etc/init.d/youtubeUnblock disable >/dev/null 2>&1

	# Останавливаем zapret
	log_info "Останавливаем zapret"
	/etc/init.d/zapret stop >/dev/null 2>&1
	sleep 1
	killall nfqws >/dev/null 2>&1

    # Запускаем поиск стратегий
	# [ ! -d "/tmp/resscan/" ] && mkdir "/tmp/resscan/"
	mkdir -p "/tmp/resscan/"
	sh $ZAPRET_ORIG_DIR/blockcheck_wrapper.sh

    if [ ! -s "/tmp/resscan/final.txt" ]; then
        log_error "Ошибка: не удалось извлечь стратегию"
        exit 1
	else
		mv /tmp/resscan/final.txt "$FOUND_STRATEGY"
    fi
	
	# Запускаем zapret
	log_info "Запускаем zapret"
	/etc/init.d/zapret start >/dev/null 2>&1
	keyb_buffer_clear
	sleep 2
	
}

# ФУНКЦИЯ РУЧНОГО ТЕСТИРОВАНИЯ СТРАТЕГИЙ

strategy_testing() {

	i=1
	
	# Запоминаем текущую стратегию, чтобы восстановить её, если ни одна стратегия не подойдёт.
	local _old_strategy=$(uci get zapret.config.NFQWS_OPT)
	
	local _strat_counter=$(strategy_counter "$FOUND_STRATEGY")
	while [ "${i}" -le "${_strat_counter}" ]; do
		
		# Чтение строки по номеру
		STRAT=$(sed -n "${i}p" "$FOUND_STRATEGY")
		
		# Удаляем лишние пробелы
		STRAT=$(echo "$STRAT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
		
		if [ -z "$STRAT" ]; then
			echo "Строка $i пуста, пропускаем..."
			i=$((i + 1))
			continue
		fi
		
		echo
		echo " Применяем стратегию $i из $_strat_counter"
		[ "$_strat_counter" -gt 9 ] && printf "="
		echo "============================"
		# echo -e "${GREEN}$STRAT${NC}"
		
		# Применяем стратегию
		strategy_replace "$STRAT"
		sleep 1
		
		# Тестируем подключение к ютубу		
		TLS12=0; TLS13=0
		if curl --tlsv1.2 --max-time $CURL_MAX_TIME --user-agent  "$USER_AGENT" -s -o /dev/null "$TEST_URL" >/dev/null 2>&1; then 
			printf "\033[32m1.2✓ \033[0m "
			TLS12=1
		else 
			printf "\033[31m1.2✗ \033[0m"
		fi
		
 		if curl --tlsv1.3 --max-time $CURL_MAX_TIME --user-agent "$USER_AGENT" -s -o /dev/null "$TEST_URL" >/dev/null 2>&1; then
			printf "\033[32m1.3✓ \033[0m "
			TLS13=1
		else
			printf "\033[31m1.3✗ \033[0m"; 
		fi
		
		case $((TLS12 + TLS13)) in
			0)
				printf "Нерабочая стратегия." 
				;;
			1) 
				printf "${YELLOW}Частично рабочая стратегия.${NC}" 
				;;
			2)
				echo -e "${GREEN}НАЙДЕНА ПОЛНОСТЬЮ РАБОЧАЯ СТРАТЕГИЯ!${NC}"
				# echo "$STRAT" > /etc/zapret_autoconfig/zapret_success_strategy.txt
				echo "Проверяйте доступ к Ютуб."
				printf "Всё нормально - 1. Не пашет - Enter. > "
				read -r answer
				case $answer in 1) break ;; *) echo "Продолжение тестирования" ;; esac
				;;
		esac
		echo
		i=$((i + 1))
	done
	echo $answer

	if [ -z "$answer" ] || [ "$answer" -ne 1 ]; then
		echo "Протестированы все стратегии. Рабочая не найдена."
		# Восстанавливаем старую стратегию
		uci set zapret.config.NFQWS_OPT="$_old_strategy"
		uci commit zapret
		/etc/init.d/zapret restart >/dev/null 2>&1
		
		# Пауза
		read -t 2
	fi
}


# ФУНКЦИЯ ЗАМЕНЫ КОНФИГУРАЦИИ ZAPRET

strategy_replace() {

    local STRAT="$1"

    # Останавливаем zapret если запущен
    if [ -x /etc/init.d/zapret ] && /etc/init.d/zapret status >/dev/null 2>&1; then 
        # echo "Останавливаю zapret..."
        /etc/init.d/zapret stop >/dev/null 2>&1
    fi
	killall nfqws >/dev/null 2>&1

    # Создаём временный файл с обновлённой конфигурацией
    local TMPFILE=$(mktemp)
    

# Перенастраиваем конфигурацию
# cat > "$TMPFILE" << 'EOF'

# config main 'config'
	# option run_on_boot '1'
	# option FWTYPE 'nftables'
	# option POSTNAT '1'
	# option FLOWOFFLOAD 'none'
	# option INIT_APPLY_FW '1'
	# option DISABLE_IPV4 '0'
	# option DISABLE_IPV6 '1'
	# option FILTER_TTL_EXPIRED_ICMP '1'
	# option MODE_FILTER 'hostlist'
	# option DISABLE_CUSTOM '0'
	# option WS_USER 'daemon'
	# option DAEMON_LOG_ENABLE '0'
	# option DAEMON_LOG_FILE '/tmp/zapret+<DAEMON_NAME>+<DAEMON_IDNUM>+<DAEMON_CFGNAME>.log'
	# option AUTOHOSTLIST_RETRANS_THRESHOLD '3'
	# option AUTOHOSTLIST_FAIL_THRESHOLD '3'
	# option AUTOHOSTLIST_FAIL_TIME '60'
	# option AUTOHOSTLIST_DEBUGLOG '0'
	# option NFQWS_ENABLE '1'
	# option DESYNC_MARK '0x40000000'
	# option DESYNC_MARK_POSTNAT '0x20000000'
	# option FILTER_MARK '	'
	# option NFQWS_PORTS_TCP '80,443'
	# option NFQWS_PORTS_UDP '443'
	# option NFQWS_TCP_PKT_OUT '9'
	# option NFQWS_TCP_PKT_IN '3'
	# option NFQWS_UDP_PKT_OUT '9'
	# option NFQWS_UDP_PKT_IN '0'
	# option NFQWS_PORTS_TCP_KEEPALIVE '0'
	# option NFQWS_PORTS_UDP_KEEPALIVE '0'
	# option NFQWS_OPT '
# --filter-tcp=443
# --hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
# --hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
# --hostlist-exclude-domains=openwrt.org
# EOF
    # # Добавляем новую опцию со стратегией
	# # echo "$STRAT"
    # echo "$STRAT" | tr ' ' '\n' >> "$TMPFILE"
	# echo "'
	# ">> "$TMPFILE"
	
    # # Заменяем оригинальный файл
	# rm -r /etc/config/zapret
    # mv "$TMPFILE" /etc/config/zapret >/dev/null 2>&1
	cd $ZAPRET_MAIN_DIR/

    uci set zapret.config.NFQWS_OPT="
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--hostlist-exclude-domains=openwrt.org
${STRAT}"
	uci commit zapret
	
	# Запускаем синхронизацию конфигов (вот додумались блин)
	echo "Запускаю синхронизацию конфигов"
	sh sync_config.sh

    # Запускаем zapret
    printf "Запускаю zapret... "
    /etc/init.d/zapret start >/dev/null 2>&1

    if ! /etc/init.d/zapret status >/dev/null 2>&1; then
        echo "Предупреждение: zapret не запустился автоматически"
    fi
}

# Очистка буфера клавиатуры
keyb_buffer_clear() {
	while read -t 1 -n 1000 cleared; do
		printf ""
	done
}

# Главное меню
show_main_menu() {
	_strategy_count=$(strategy_counter $FOUND_STRATEGY)
	
	clear
	echo "$VERSION"
	echo
	echo "1 - Запуск ПОИСКА стратегий. Применяются стратегии по (2). В наличии: $_strategy_count"
	echo
	echo "2 - ТЕСТИРОВАНИЕ и ПРИМЕНЕНИЕ найденных стратегий"
	echo "3 - Сколько стратегий найти? Сейчас ищем: $MAX_STRATEGIES"
	echo
	echo "0 - Выход"
	echo "00 - Полное удаление скрипта и зависимостей (кроме бэкапов zapret)"
	echo
	printf "Введите номер пункта меню > "
}

# Обработка выбора в меню
handle_menu_choice() {
	_choice="$1"
	
	case "$_choice" in
		0)
			log_info "Выход"
			service zapret restart >/dev/null 2>&1 || true
			exit 0
			;;
		00)
			log_info "Полное удаление скрипта (кроме бэкапов zapret)"
			
			# Восстановление состояния сервисов
			if [ -f "$RESTORE_SCRIPT" ]; then
				log_info "Восстановление сервисов..."
				sh "$RESTORE_SCRIPT" || true
			fi
			
			# Восстановление конфигурации zapret
			if [ -f "$UNINSTALL_FILE" ]; then
				_backup_file=$(head -n 1 "$UNINSTALL_FILE" 2>/dev/null)
				if [ -f "$_backup_file" ]; then
					log_info "Восстановление конфигурации zapret..."
					cp -f "$_backup_file" "/etc/config/zapret" 2>/dev/null || true
				fi
			fi
			
			# Очистка
			log_info "Очистка файлов..."
			rm -f "$ZAPRET_ORIG_DIR/already_installed" 2>/dev/null || true
			rm -f "$CONFIG_DIR/restore_services_state.sh"
			rm -f "$CONFIG_DIR/uninstall"
			rm -rf "$ZAPRET_ORIG_DIR/" 2>/dev/null || true			
			log_success "Удаление завершено"
			echo
			echo "Бэкапы конфигураций zapret находятся в директории:"
			echo -e "${YELLOW}$CONFIG_DIR/backup${NC}"
			#echo "  opkg remove --force-removal-of-dependent-packages zapret luci-app-zapret"
			echo
			exit 0
			;;
		1)
			log_info "Запуск поиска стратегий..."
				# Вызов функции поиска стратегий
				strategy_scan
			;;
		2)
			log_info "Тестирование стратегий..."
				strategy_testing
			;;
		3)
			printf "Сколько стратегий надо найти? > "
			read -r _new_max
			if echo "$_new_max" | grep -q '^[0-9][0-9]*$'; then
				if [ "$_new_max" -gt 0 ]; then
					export MAX_STRATEGIES="$_new_max"
					log_success "Установлено: $MAX_STRATEGIES"
				else
					log_warn "Число должно быть больше 0"
				fi
			else
				log_warn "Некорректное значение"
			fi
			;;
		*)
			log_warn "Неизвестная команда: $_choice"
			sleep 1
			;;
	esac
}

#########################################
# ГЛАВНАЯ ПРОГРАММА
#########################################

main() {
	
	clear
	# Проверка версии опенврт
	check_owrt_version
	sleep 2
	clear
	
	# Проверка прав
	check_root
	
	log_info "Запуск $VERSION"
	
	# Инициализация при первом запуске
	if [ ! -f "$ZAPRET_ORIG_DIR/already_installed" ]; then
	
		create_backup
		save_services_state
		
		if ! install_requirements; then
			log_error "Не удалось установить необходимые пакеты"
			exit 1
		fi
		
		# Помечаем как установленное
		mkdir -p "$ZAPRET_ORIG_DIR"
		touch "$ZAPRET_ORIG_DIR/already_installed"
		
		log_success "Инициализация завершена"
	fi
	
	# Останавливаем конфликтующие сервисы
	if service_is_running "youtubeUnblock"; then
		log_info "Останавливаю youtubeUnblock..."
		/etc/init.d/youtubeUnblock stop >/dev/null 2>&1 || true
		/etc/init.d/youtubeUnblock disable >/dev/null 2>&1 || true
	fi
	
	# Главный цикл меню
	while true; do
		show_main_menu
		read -r choice
		
		handle_menu_choice "$choice"

	done
}

# Простая очистка при завершении
cleanup() {
	echo
	log_info "Завершение работы..."
	# Можно добавить код очистки
}

# Запуск с обработкой прерываний
trap cleanup EXIT
main "$@"
