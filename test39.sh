#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# =========================================
ZAPRET_MANAGER_VERSION="7.6"; ZAPRET_VERSION="72.20251227"; STR_VERSION_AUTOINSTALL="v6"
GREEN="\033[1;32m"; RED="\033[1;31m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"; BLUE="\033[0;34m"; NC="\033[0m"; DGRAY="\033[38;5;244m"
WORKDIR="/tmp/zapret-update"; CONF="/etc/config/zapret"; CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"
EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"; fileDoH="/etc/config/https-dns-proxy"
EXCLUDE_URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"
HOSTS_LIST="185.87.51.182 4pda.to www.4pda.to app.4pda.to appbk.4pda.to|130.255.77.28 ntc.party|30.255.77.28 ntc.party|173.245.58.219 rutor.info d.rutor.info|185.39.18.98 lib.rus.ec www.lib.rus.ec
57.144.222.34 instagram.com www.instagram.com|157.240.9.174 instagram.com www.instagram.com|157.240.245.174 instagram.com www.instagram.com|157.240.205.174 instagram.com www.instagram.com"
hosts_add(){ echo "$HOSTS_LIST" | tr '|' '\n' | grep -Fxv -f /etc/hosts >> /etc/hosts; /etc/init.d/dnsmasq restart >/dev/null 2>&1; }
hosts_clear(){ echo "$HOSTS_LIST" | tr '|' '\n' | while IFS= read -r line; do [ -n "$line" ] && sed -i "\|$line|d" /etc/hosts; done; /etc/init.d/dnsmasq restart >/dev/null 2>&1; }
# ==========================================
# Получение версии
# ==========================================
get_versions() { LOCAL_ARCH=$(awk -F\' '/DISTRIB_ARCH/ {print $2}' /etc/openwrt_release); [ -z "$LOCAL_ARCH" ] && LOCAL_ARCH=$(opkg print-architecture | grep -v "noarch" | sort -k3 -n | tail -n1 | awk '{print $2}')
USED_ARCH="$LOCAL_ARCH"; LATEST_URL="https://github.com/remittor/zapret-openwrt/releases/download/v${ZAPRET_VERSION}/zapret_v${ZAPRET_VERSION}_${LOCAL_ARCH}.zip"
INSTALLED_VER=$(opkg list-installed zapret | awk '{sub(/-r[0-9]+$/, "", $3); print $3}'); [ -z "$INSTALLED_VER" ] && INSTALLED_VER="не найдена"
ZAPRET_STATUS=$([ -f /etc/init.d/zapret ] && /etc/init.d/zapret status 2>/dev/null | grep -qi running && echo "${GREEN}запущен${NC}" || echo "${RED}остановлен${NC}"); [ -f /etc/init.d/zapret ] || ZAPRET_STATUS=""
[ "$INSTALLED_VER" = "$ZAPRET_VERSION" ] && INST_COLOR=$GREEN INSTALLED_DISPLAY="$INSTALLED_VER" || { INST_COLOR=$RED; INSTALLED_DISPLAY=$([ "$INSTALLED_VER" != "не найдена" ] && echo "$INSTALLED_VER" || echo "$INSTALLED_VER"); }; }
# ==========================================
# Установка Zapret
# ==========================================
install_Zapret() { local NO_PAUSE=$1; get_versions; if [ "$INSTALLED_VER" = "$ZAPRET_VERSION" ]; then echo -e "\nZapret ${GREEN}уже установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; return; fi
[ "$NO_PAUSE" != "1" ] && echo; echo -e "${MAGENTA}Устанавливаем ZAPRET${NC}"; if [ -f /etc/init.d/zapret ]; then echo -e "${CYAN}Останавливаем ${NC}zapret" && /etc/init.d/zapret stop >/dev/null 2>&1; for pid in $(pgrep -f /opt/zapret 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done; fi
echo -e "${CYAN}Обновляем список пакетов${NC}"; opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
mkdir -p "$WORKDIR"; rm -f "$WORKDIR"/* 2>/dev/null; cd "$WORKDIR" || return; FILE_NAME=$(basename "$LATEST_URL"); if ! command -v unzip >/dev/null 2>&1; then
echo -e "${CYAN}Устанавливаем ${NC}unzip" && opkg install unzip >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить unzip!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }; fi
echo -e "${CYAN}Скачиваем архив ${NC}$FILE_NAME"; wget -q -U "Mozilla/5.0" -O "$FILE_NAME" "$LATEST_URL" || { echo -e "\n${RED}Не удалось скачать ${NC}$FILE_NAME\n"; read -p "Нажмите Enter..." dummy; return; }
echo -e "${CYAN}Распаковываем архив${NC}"; unzip -o "$FILE_NAME" >/dev/null; for PKG in zapret_*.ipk luci-app-zapret_*.ipk; do [ -f "$PKG" ] && echo -e "${CYAN}Устанавливаем ${NC}$PKG" && opkg install --force-reinstall "$PKG" >/dev/null 2>&1 || { echo -e "\n${RED}Не удалось установить $PKG!${NC}\n"
read -p "Нажмите Enter..." dummy; return; } ; done; echo -e "${CYAN}Удаляем временные файлы${NC}"; cd /; rm -rf "$WORKDIR" /tmp/*.ipk /tmp/*.zip /tmp/*zapret* 2>/dev/null; if [ -f /etc/init.d/zapret ]; then echo -e "Zapret ${GREEN}установлен!${NC}\n"
[ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter..." dummy; else echo -e "\n${RED}Zapret не был установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; fi; }
# ==========================================
# Установка скриптов
# ==========================================
show_script_50() { [ -f "/opt/zapret/init.d/openwrt/custom.d/50-script.sh" ] || return; line=$(head -n1 /opt/zapret/init.d/openwrt/custom.d/50-script.sh)
name=$(case "$line" in *QUIC*) echo "50-quic4all" ;; *stun*) echo "50-stun4all" ;; *"discord media"*) echo "50-discord-media" ;; *"discord subnets"*) echo "50-discord" ;; *) echo "" ;; esac); }
scrypt_install() { local NO_PAUSE=$1; [ ! -f /etc/init.d/zapret ] && { echo -e "\n${RED}Zapret не установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
while true; do [ "$NO_PAUSE" != "1" ] && clear && echo -e "${MAGENTA}Меню установки скриптов${NC}"; [ "$NO_PAUSE" != "1" ] && show_script_50 && [ -n "$name" ] && echo -e "\n${YELLOW}Установлен скрипт:${NC} $name"
if [ "$NO_PAUSE" = "1" ]; then SELECTED="50-stun4all"; URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-stun4all"; else
echo -e "\n${CYAN}1) ${GREEN}Установить скрипт ${NC}50-stun4all\n${CYAN}2) ${GREEN}Установить скрипт ${NC}50-quic4all\n${CYAN}3) ${GREEN}Установить скрипт ${NC}50-discord-media\n${CYAN}4) ${GREEN}Установить скрипт ${NC}50-discord"
echo -ne "${CYAN}5) ${GREEN}Удалить скрипт${NC}\n${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n\n${YELLOW}Выберите пункт:${NC} " && read choiceSC; case "$choiceSC" in
1) SELECTED="50-stun4all"; URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-stun4all" ;; 2) SELECTED="50-quic4all"; URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-quic4all" ;;
3) SELECTED="50-discord-media"; URL="https://raw.githubusercontent.com/bol-van/zapret/master/init.d/custom.d.examples.linux/50-discord-media" ;; 4) SELECTED="50-discord"; URL="https://raw.githubusercontent.com/bol-van/zapret/v70.5/init.d/custom.d.examples.linux/50-discord" ;;
5) echo -e "\n${MAGENTA}Удаляем скрипт${NC}"; rm -f "$CUSTOM_DIR/50-script.sh" 2>/dev/null;chmod +x /opt/zapret/sync_config.sh && /opt/zapret/sync_config.sh && /etc/init.d/zapret restart >/dev/null 2>&1; echo -e "${GREEN}Скрипт удалён!${NC}\n"; read -p "Нажмите Enter..." dummy; continue ;; *) return ;; esac; fi
if wget -q -U "Mozilla/5.0" -O "$CUSTOM_DIR/50-script.sh" "$URL"; then [ "$NO_PAUSE" != "1" ] && echo; echo -e "${MAGENTA}Устанавливаем скрипт${NC}\n${GREEN}Скрипт ${NC}$SELECTED${GREEN} успешно установлен!${NC}\n"; else echo -e "\n${RED}Ошибка при скачивании скрипта!${NC}\n"; read -p "Нажмите Enter..." dummy; continue; fi
sed -i "/DISABLE_CUSTOM/s/'1'/'0'/" /etc/config/zapret; chmod +x /opt/zapret/sync_config.sh && /opt/zapret/sync_config.sh && /etc/init.d/zapret restart >/dev/null 2>&1; [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter..." dummy; [ "$NO_PAUSE" = "1" ] && break; done }
# ==========================================
# FIX GAME
# ==========================================
fix_GAME() { local NO_PAUSE=$1; [ ! -f /etc/init.d/zapret ] && { echo -e "\n${RED}Zapret не установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
[ "$NO_PAUSE" != "1" ] && echo; echo -e "${MAGENTA}Настраиваем стратегию для игр${NC}"; if grep -q "option NFQWS_PORTS_UDP.*1024-19293,19345-49999,50101-65535" "$CONF" && grep -q -- "--filter-udp=1024-19293,19345-49999,50101-65535" "$CONF"; then echo -e "${CYAN}Удаляем из стратегии настройки для игр${NC}"
sed -i ':a;N;$!ba;s|--new\n--filter-udp=1024-19293,19345-49999,50101-65535\n--dpi-desync=fake\n--dpi-desync-cutoff=d2\n--dpi-desync-any-protocol=1\n--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com\.bin\n*||g' "$CONF"
sed -i "s/,1024-19293,19345-49999,50101-65535//" "$CONF"; chmod +x /opt/zapret/sync_config.sh && /opt/zapret/sync_config.sh && /etc/init.d/zapret restart >/dev/null 2>&1; echo -e "${GREEN}Настройки для игр удалены!${NC}\n"; read -p "Нажмите Enter..." dummy; return; fi
if ! grep -q "option NFQWS_PORTS_UDP.*1024-19293,19345-49999,50101-65535" "$CONF"; then sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'$/,1024-19293,19345-49999,50101-65535'/" "$CONF"; fi; if ! grep -q -- "--filter-udp=1024-19293,19345-49999,50101-65535" "$CONF"; then last_line=$(grep -n "^'$" "$CONF" | tail -n1 | cut -d: -f1)
if [ -n "$last_line" ]; then sed -i "${last_line},\$d" "$CONF"; fi; printf "%s\n" "--new" "--filter-udp=1024-19293,19345-49999,50101-65535" "--dpi-desync=fake" "--dpi-desync-cutoff=d2" "--dpi-desync-any-protocol=1" "--dpi-desync-fake-unknown-udp=/opt/zapret/files/fake/quic_initial_www_google_com.bin" "'" >> "$CONF"; fi
echo -e "${CYAN}Добавляем в стратегию настройки для игр${NC}"; chmod +x /opt/zapret/sync_config.sh && /opt/zapret/sync_config.sh && /etc/init.d/zapret restart >/dev/null 2>&1; echo -e "${GREEN}Игровые настройки добавлены!${NC}\n";[ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter..." dummy; }
# ==========================================
# Zapret под ключ
# ==========================================
zapret_key(){ clear; echo -e "${MAGENTA}Удаление, установка и настройка Zapret${NC}\n"; get_versions; uninstall_zapret "1"; install_Zapret "1"
[ ! -f /etc/init.d/zapret ] && return; menu_str "1"; echo; scrypt_install "1"; fix_GAME "1"; echo -e "Zapret ${GREEN}установлен и настроен!${NC}\n"; read -p "Нажмите Enter..." dummy; }
# ==========================================
# Вернуть настройки по умолчанию
# ==========================================
comeback_def () { if [ -f /opt/zapret/restore-def-cfg.sh ]; then echo -e "\n${MAGENTA}Возвращаем настройки по умолчанию${NC}"; rm -f /opt/zapret/init.d/openwrt/custom.d/50-script.sh; for i in 1 2 3 4; do rm -f "/opt/zapret/ipset/cust$i.txt"; done
[ -f /etc/init.d/zapret ] && /etc/init.d/zapret stop >/dev/null 2>&1; echo -e "${CYAN}Возвращаем ${NC}настройки${CYAN}, ${NC}стратегию${CYAN} и ${NC}hostlist${CYAN} к значениям по умолчанию${NC}"; cp -f /opt/zapret/ipset_def/* /opt/zapret/ipset/
chmod +x /opt/zapret/restore-def-cfg.sh && /opt/zapret/restore-def-cfg.sh; chmod +x /opt/zapret/sync_config.sh && /opt/zapret/sync_config.sh; /etc/init.d/zapret restart >/dev/null 2>&1
hosts_clear; echo -e "Настройки по умолчанию ${GREEN}возвращены!${NC}\n"; else echo -e "\n${RED}Zapret не установлен!${NC}\n"; fi; read -p "Нажмите Enter..." dummy; }
# ==========================================
# Cтарт/стоп Zapret
# ==========================================
stop_zapret() { echo -e "\n${MAGENTA}Останавливаем Zapret${NC}\n${CYAN}Останавливаем ${NC}Zapret"; /etc/init.d/zapret stop >/dev/null 2>&1
for pid in $(pgrep -f /opt/zapret 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done; echo -e "Zapret ${GREEN}остановлен!${NC}\n"; read -p "Нажмите Enter..." dummy; }
start_zapret() { if [ -f /etc/init.d/zapret ]; then echo -e "\n${MAGENTA}Запускаем Zapret${NC}"; echo -e "${CYAN}Запускаем ${NC}Zapret";
/etc/init.d/zapret start >/dev/null 2>&1; chmod +x /opt/zapret/sync_config.sh; /opt/zapret/sync_config.sh && /etc/init.d/zapret restart >/dev/null 2>&1
echo -e "Zapret ${GREEN}запущен!${NC}\n"; else echo -e "\n${RED}Zapret не установлен!${NC}\n"; fi; read -p "Нажмите Enter..." dummy; }
# ==========================================
# Полное удаление Zapret
# ==========================================
uninstall_zapret() { local NO_PAUSE=$1; [ "$NO_PAUSE" != "1" ] && echo; echo -e "${MAGENTA}Удаляем ZAPRET${NC}\n${CYAN}Останавливаем ${NC}zapret\n${CYAN}Убиваем процессы${NC}"
/etc/init.d/zapret stop >/dev/null 2>&1; for pid in $(pgrep -f /opt/zapret 2>/dev/null); do kill -9 "$pid" 2>/dev/null; done
echo -e "${CYAN}Удаляем пакеты${NC}"; opkg --force-removal-of-dependent-packages --autoremove remove zapret luci-app-zapret >/dev/null 2>&1
echo -e "${CYAN}Удаляем временные файлы${NC}"; rm -rf /opt/zapret /etc/config/zapret /etc/firewall.zapret /etc/init.d/zapret /tmp/*zapret* /var/run/*zapret* /tmp/*.ipk /tmp/*.zip 2>/dev/null
crontab -l 2>/dev/null | grep -v -i "zapret" | crontab - 2>/dev/null; nft list tables 2>/dev/null | awk '{print $2}' | grep -E '(zapret|ZAPRET)' | while read t; do [ -n "$t" ] && nft delete table "$t" 2>/dev/null; done
hosts_clear; echo -e "Zapret ${GREEN}полностью удалён!${NC}\n"; [ "$NO_PAUSE" != "1" ] && read -p "Нажмите Enter..." dummy; }
# ==========================================
# Подбор стратегии для Ютуб
# ==========================================
auto_stryou() {
    CONF="/etc/config/zapret"
    STR_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/ListStrYou"
    TMP_LIST="/tmp/zapret_yt_list.txt"
    SAVED_STR="/opt/StrYou"
    OLD_STR="/opt/StrOLD"

    TEST_HOST="https://rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"
    TIMEOUT=3

    # Сохраняем текущее состояние после строки option NFQWS_OPT '
    awk '/^[[:space:]]*option NFQWS_OPT '\''/{flag=1} flag{print}' "$CONF" > "$OLD_STR"

    # Скачать список стратегий
    curl -fsSL "$STR_URL" -o "$TMP_LIST" || { echo "Не удалось скачать список"; read -p "Нажмите Enter..." dummy </dev/tty; return 1; }

    TOTAL=$(grep -c '^Yv[0-9]\+' "$TMP_LIST")
    echo "[ZAPRET] Найдено стратегий: $TOTAL"
    echo

    CURRENT_NAME=""
    CURRENT_BODY=""
    COUNT=0

    apply_strategy() {
        NAME="$1"
        BODY="$2"
        # Удаляем старую стратегию
        sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
        {
            echo "  option NFQWS_OPT '"
            echo "#AUTO $NAME"
            printf "%b\n" "$BODY"
            echo "'"
        } >> "$CONF"
        chmod +x /opt/zapret/sync_config.sh
        /opt/zapret/sync_config.sh
        /etc/init.d/zapret restart >/dev/null 2>&1
    }

    check_access() {
        curl -s --connect-timeout "$TIMEOUT" -m "$TIMEOUT" "$TEST_HOST" >/dev/null && echo "ok" || echo "fail"
    }

    while IFS= read -r LINE || [ -n "$LINE" ]; do
        if echo "$LINE" | grep -q '^Yv[0-9]\+'; then
            if [ -n "$CURRENT_NAME" ]; then
                COUNT=$((COUNT + 1))
                echo "[ZAPRET] Применяем стратегию: $CURRENT_NAME ($COUNT/$TOTAL)"
                apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"

                STATUS=$(check_access)
                if [ "$STATUS" = "ok" ]; then
                    echo "✅ Доступ есть"
                    echo "Проверьте видео в браузере"
                    echo "Enter — оставить стратегию, N — продолжить перебор"
                    read -r ANSWER </dev/tty
                    if [ -z "$ANSWER" ]; then
                        # Сохраняем рабочую стратегию
                        {
                            echo "#$CURRENT_NAME"
                            printf "%b\n" "$CURRENT_BODY"
                        } > "$SAVED_STR"
                        echo "🏁 Рабочая стратегия: $CURRENT_NAME сохранена в $SAVED_STR"

                        # Применяем StrNEW в конфиг
                        sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
                        cat /opt/StrNEW >> "$CONF"
                        chmod +x /opt/zapret/sync_config.sh
                        /opt/zapret/sync_config.sh
                        /etc/init.d/zapret restart >/dev/null 2>&1

                        read -p "Нажмите Enter, чтобы вернуться в меню..." dummy </dev/tty
                        return 0
                    fi
                else
                    echo "❌ Нет доступа"
                fi
            fi
            CURRENT_NAME="$LINE"
            CURRENT_BODY=""
        else
            [ -n "$LINE" ] && CURRENT_BODY="${CURRENT_BODY}${LINE}\n"
        fi
    done < "$TMP_LIST"

    # Последняя стратегия
    if [ -n "$CURRENT_NAME" ]; then
        COUNT=$((COUNT + 1))
        echo "[ZAPRET] ▶ Применяем стратегию: $CURRENT_NAME ($COUNT/$TOTAL)"
        apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"

        STATUS=$(check_access)
        if [ "$STATUS" = "ok" ]; then
            echo "✅ Доступ есть"
            echo "Проверьте видео в браузере"
            echo "Enter — оставить стратегию, N — продолжить перебор"
            read -r ANSWER </dev/tty
            if [ -z "$ANSWER" ]; then
                # Сохраняем рабочую стратегию
                {
                    echo "#$CURRENT_NAME"
                    printf "%b\n" "$CURRENT_BODY"
                } > "$SAVED_STR"
                echo "🏁 Рабочая стратегия: $CURRENT_NAME сохранена в $SAVED_STR"

                # Применяем StrNEW в конфиг
                sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
                cat /opt/StrNEW >> "$CONF"
                chmod +x /opt/zapret/sync_config.sh
                /opt/zapret/sync_config.sh
                /etc/init.d/zapret restart >/dev/null 2>&1

                read -p "Нажмите Enter, чтобы вернуться в меню..." dummy </dev/tty
                return 0
            fi
        else
            echo "❌ Нет доступа"
        fi
    fi

    # Восстанавливаем старое состояние конфигурации, если стратегия не подошла
    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
    cat "$OLD_STR" >> "$CONF"
    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1

    echo "🚫 Рабочая стратегия не найдена"
    read -p "Нажмите Enter, чтобы вернуться в меню..." dummy </dev/tty
    return 1
}


# ==========================================
# Выбор стратегий
# ==========================================
show_current_strategy() { [ -f "$CONF" ] || return; for v in v1 v2; do grep -q "#$v" "$CONF" && { ver="$v"; return; } done; }

strategy_v1() {
    printf '%s\n' "#Yv02" "--filter-tcp=443" "--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt" "--dpi-desync=multisplit" "--dpi-desync-split-pos=1,sniext+1" "--dpi-desync-split-seqovl=1"
    printf '%s\n' "#v1" "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=rzd.ru" "--dpi-desync-hostfakesplit-midhost=host-2" "--dpi-desync-split-seqovl=726" "--dpi-desync-fooling=badsum,badseq" "--dpi-desync-badseq-increment=0"
}

strategy_v2() {
    printf '%s\n' "#v2" "--new" "--filter-tcp=443" "--hostlist-exclude=/opt/zapret/ipset/zapret-hosts-user-exclude.txt" "--dpi-desync=hostfakesplit" "--dpi-desync-hostfakesplit-mod=host=m.ok.ru"
    printf '%s\n' "--dpi-desync-hostfakesplit-midhost=host-2" "--dpi-desync-split-seqovl=1" "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/TLS_ClientHello_rkn_gov_ru.bin" "--dpi-desync-fooling=badsum,badseq" "--dpi-desync-badseq-increment=0"
}

dis_str() {
    if ! grep -q "option NFQWS_PORTS_UDP.*19294-19344,50000-50100" "$CONF"; then
        sed -i "/^[[:space:]]*option NFQWS_PORTS_UDP '/s/'$/,19294-19344,50000-50100'/"
    fi
    if ! grep -q "option NFQWS_PORTS_TCP.*2053,2083,2087,2096,8443" "$CONF"; then
        sed -i "/^[[:space:]]*option NFQWS_PORTS_TCP '/s/'$/,2053,2083,2087,2096,8443'/"
    fi
    if ! grep -q -- "--filter-udp=19294-19344,50000-50100" "$CONF"; then
        last_line1=$(grep -n "^'$" "$CONF" | tail -n1 | cut -d: -f1)
        [ -n "$last_line1" ] && sed -i "${last_line1},\$d" "$CONF"
        printf "%s\n" \
            "--new" \
            "--filter-udp=19294-19344,50000-50100" \
            "--filter-l7=discord,stun" \
            "--dpi-desync=fake" \
            "--dpi-desync-repeats=6" \
            "--new" \
            "--filter-tcp=2053,2083,2087,2096,8443" \
            "--hostlist-domains=discord.media" \
            "--dpi-desync=multisplit" \
            "--dpi-desync-split-seqovl=652" \
            "--dpi-desync-split-pos=2" \
            "--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin" \
            "'" >> "$CONF"
    fi
}

menu_str() {
    [ ! -f /etc/init.d/zapret ] && {
        echo -e "\n${RED}Zapret не установлен!${NC}\n"
        read -p "Нажмите Enter..." dummy
        return
    }

    while true; do
        clear
        echo -e "${MAGENTA}Меню стратегии${NC}\n"
        show_current_strategy
        [ -n "$ver" ] && echo -e "${YELLOW}Используется стратегия:${NC} $ver\n"

        echo -e "${CYAN}1) ${GREEN}Установить стратегию${NC} v1"
        echo -e "${CYAN}2) ${GREEN}Установить стратегию${NC} v2"
        echo -e "${CYAN}0) ${GREEN}Подобрать стратегию для ${NC}YouTube"
        echo -ne "${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n\n${YELLOW}Выберите пункт:${NC} "

        read choiceST

        case "$choiceST" in
            1) install_strategy v1 ;;
            2) install_strategy v2 ;;
            0) auto_stryou ;;
            *) return ;;
        esac
    done
}

install_strategy() {
    local version="$1"
    local fileGP="/opt/zapret/ipset/zapret-hosts-google.txt"

    echo -e "\n${MAGENTA}Устанавливаем стратегию ${version}${NC}\n${CYAN}Меняем стратегию${NC}"

    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$CONF"
    {
        echo "  option NFQWS_OPT '"
        strategy_"$version"
        echo "'"
    } >> "$CONF"

    cat <<'EOF' | grep -Fxv -f "$fileGP" 2>/dev/null >> "$fileGP"
gvt1.com
googleplay.com
play.google.com
beacons.gvt2.com
play.googleapis.com
play-fe.googleapis.com
lh3.googleusercontent.com
android.clients.google.com
connectivitycheck.gstatic.com
play-lh.googleusercontent.com
play-games.googleusercontent.com
prod-lt-playstoregatewayadapter-pa.googleapis.com
EOF

    echo -e "${CYAN}Редактируем ${NC}/etc/hosts${NC}"
    hosts_add

    dis_str
    echo -e "${CYAN}Применяем новую стратегию и настройки${NC}"

    chmod +x /opt/zapret/sync_config.sh
    /opt/zapret/sync_config.sh
    /etc/init.d/zapret restart >/dev/null 2>&1

    echo -e "${GREEN}Стратегия ${NC}${version} ${GREEN}установлена!${NC}\n"
    read -p "Нажмите Enter..." dummy
}


# ==========================================
# DNS over HTTPS
# ==========================================
DoH_menu() { while true; do get_doh_status; clear; echo -e "${MAGENTA}Меню DNS over HTTPS${NC}\n"; opkg list-installed | grep -q '^https-dns-proxy ' && doh_st="Удалить" || doh_st="Установить"
[ -n "$DOH_STATUS" ] && opkg list-installed | grep -q '^https-dns-proxy ' && echo -e "${YELLOW}DNS over HTTPS: ${NC}$DOH_STATUS\n"
echo -e "${CYAN}1)${GREEN} $doh_st ${NC}DNS over HTTPS\n${CYAN}2)${GREEN} Настроить ${NC}Comss DNS\n${CYAN}3)${GREEN} Настроить ${NC}Xbox DNS\n${CYAN}4)${GREEN} Настроить ${NC}dns.malw.link"
echo -ne "${CYAN}5)${GREEN} Настроить ${NC}dns.malw.link (CloudFlare)\n${CYAN}6)${GREEN} Вернуть ${NC}настройки по умолчанию\n${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n\n${YELLOW}Выберите пункт:${NC} "
read -r choiceDOH; [ -z "$choiceDOH" ] && return; case "$choiceDOH" in 1) D_o_H ;; 2) doh_install && setup_doh "$doh_comss" "Comss.one DNS" ;; 3) doh_install && setup_doh "$doh_xbox" "Xbox DNS" ;; 4) doh_install && setup_doh "$doh_query" "dns.malw.link" ;;
5) doh_install && setup_doh "$doh_queryCF" "dns.malw.link (CloudFlare)" ;; 6) doh_install && setup_doh "$doh_def" "настройки по умолчанию" ;; *) return ;; esac; done; }
setup_doh() { local config="$1"; local name="$2"; echo -e "\n${MAGENTA}Настраиваем DNS over HTTPS${NC}\n${CYAN}Настраиваем ${NC}$name\n${CYAN}Применяем новые настройки${NC}"; rm -f "$fileDoH"; printf '%s\n' "$doh_set" "$config" > "$fileDoH"
/etc/init.d/https-dns-proxy reload >/dev/null 2>&1; /etc/init.d/https-dns-proxy restart >/dev/null 2>&1; echo -e "DNS over HTTP ${GREEN}настроен!${NC}\n"; read -p "Нажмите Enter..." dummy; }
get_doh_status() { DOH_STATUS=""; [ ! -f "$fileDoH" ] && return; if grep -q "dns.comss.one" "$fileDoH"; then DOH_STATUS="Comss DNS"; elif grep -q "xbox-dns.ru" "$fileDoH"; then DOH_STATUS="Xbox DNS"; elif grep -q "5u35p8m9i7.cloudflare-gateway.com" "$fileDoH"; then
DOH_STATUS="dns.malw.link (CloudFlare)"; elif grep -q "dns.malw.link" "$fileDoH"; then DOH_STATUS="dns.malw.link"; else DOH_STATUS="установлен"; fi; }
D_o_H() { if opkg list-installed | grep -q '^https-dns-proxy '; then echo -e "\n${MAGENTA}Удаляем DNS over HTTPS\n${CYAN}Удаляем пакеты${NC}"; opkg --force-removal-of-dependent-packages --autoremove remove https-dns-proxy luci-app-https-dns-proxy >/dev/null 2>&1
echo -e "${CYAN}Удаляем файлы конфигурации ${NC}"; rm -f /etc/config/https-dns-proxy /etc/init.d/https-dns-proxy; echo -e "DNS over HTTPS${GREEN} удалён!${NC}\n"; read -p "Нажмите Enter..." dummy; else
echo -e "\n${MAGENTA}Устанавливаем DNS over HTTPS\n${CYAN}Обновляем список пакетов${NC}"; opkg update >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при обновлении списка пакетов!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
echo -e "${CYAN}Устанавливаем ${NC}https-dns-proxy"; opkg install https-dns-proxy >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при установки!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
echo -e "${CYAN}Устанавливаем ${NC}luci-app-https-dns-proxy"; opkg install luci-app-https-dns-proxy >/dev/null 2>&1 || { echo -e "\n${RED}Ошибка при установки!${NC}\n"; read -p "Нажмите Enter..." dummy; return; }
echo -e "DNS over HTTPS${GREEN} установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; fi; }; doh_install() { [ -f "$fileDoH" ] && return 0; echo -e "\n${RED}DNS over HTTPS не установлен!${NC}\n"; read -p "Нажмите Enter..." dummy; return 1; }
doh_set=$(printf "%s\n" "config main 'config'" "	option canary_domains_icloud '1'" "	option canary_domains_mozilla '1'" "	option dnsmasq_config_update '*'" "	option force_dns '1'" "	list force_dns_port '53'" "	list force_dns_port '853'" "	list force_dns_src_interface 'lan'" \
"	option procd_trigger_wan6 '0'" "	option heartbeat_domain 'heartbeat.melmac.ca'" "	option heartbeat_sleep_timeout '10'" "	option heartbeat_wait_timeout '10'" "	option user 'nobody'" "	option group 'nogroup'" "	option listen_addr '127.0.0.1'")
doh_def=$(printf "%s\n" "" "config https-dns-proxy" "	option bootstrap_dns '1.1.1.1,1.0.0.1'" "	option resolver_url 'https://cloudflare-dns.com/dns-query'" \
"	option listen_port '5053'" "" "config https-dns-proxy" "	option bootstrap_dns '8.8.8.8,8.8.4.4'" "	option resolver_url 'https://dns.google/dns-query'" "	option listen_port '5054'")
doh_comss=$(printf "%s\n" "" "config https-dns-proxy" "	option resolver_url 'https://dns.comss.one/dns-query'"); doh_xbox=$(printf "%s\n" "" "config https-dns-proxy" "	option resolver_url 'https://xbox-dns.ru/dns-query'")
doh_query=$(printf "%s\n" "" "config https-dns-proxy" "	option resolver_url 'https://dns.malw.link/dns-query'"); doh_queryCF=$(printf "%s\n" "" "config https-dns-proxy" "	option resolver_url 'https://5u35p8m9i7.cloudflare-gateway.com/dns-query'")
# ==========================================
# Доступ из браузера
# ==========================================
web_is_enabled(){ command -v ttyd >/dev/null 2>&1 && uci -q get ttyd.@ttyd[0].command | grep -q "/usr/bin/zms"; }
toggle_web() { if web_is_enabled; then echo -e "\n${MAGENTA}Удаляем доступ из браузера${NC}";opkg remove luci-app-ttyd ttyd >/dev/null 2>&1; rm -f /etc/config/ttyd; rm -f /usr/bin/zms
echo -e "${GREEN}Доступ удалён!${NC}\n"; read -p "Нажмите Enter..." dummy; else echo -e "\n${MAGENTA}Активируем доступ из браузера${NC}"; echo 'sh <(wget -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh)' > /usr/bin/zms
chmod +x /usr/bin/zms; echo -e "${CYAN}Обновляем список пакетов${NC}"; if ! opkg update >/dev/null 2>&1; then echo -e "\n${RED}Ошибка при обновлении!${NC}\n"; return; fi; echo -e "${CYAN}Устанавливаем ${NC}ttyd"
if ! opkg install ttyd >/dev/null 2>&1; then echo -e "\n${RED}Ошибка при установке ttyd!${NC}\n"; read -p "Нажмите Enter..." dummy; return; fi
echo -e "${CYAN}Устанавливаем ${NC}luci-app-ttyd"; if ! opkg install luci-app-ttyd >/dev/null 2>&1; then echo -e "\n${RED}Ошибка при установке luci-app-ttyd!${NC}\n"; read -p "Нажмите Enter..." dummy; return; fi
echo -e "${CYAN}Настраиваем ${NC}ttyd"; sed -i 's#/bin/login#-t fontSize=15 sh /usr/bin/zms#' /etc/config/ttyd; /etc/init.d/ttyd restart >/dev/null 2>&1; if pidof ttyd >/dev/null
then echo -e "${GREEN}Служба запущена!${NC}\n\n${YELLOW}Доступ: ${NC}http://192.168.1.1:7681\n"; read -p "Нажмите Enter..." dummy; else echo -e "\n${RED}Ошибка! Служба не запущена!${NC}\n"; read -p "Нажмите Enter..." dummy; fi; fi; }
# ==========================================
# Вкл/Выкл QUIC
# ==========================================
quic_is_blocked(){ uci show firewall | grep -q "name='Block_UDP_80'" && uci show firewall | grep -q "name='Block_UDP_443'"; }
toggle_quic() {	if quic_is_blocked; then echo -e "\n${MAGENTA}Отключаем блокировку QUIC${NC}"; for RULE in Block_UDP_80 Block_UDP_443; do
while true; do IDX=$(uci show firewall | grep "name='$RULE'" | cut -d. -f2 | cut -d= -f1 | head -n1); [ -z "$IDX" ] && break; uci delete firewall.$IDX >/dev/null 2>&1; done; done
uci commit firewall >/dev/null 2>&1; /etc/init.d/firewall restart >/dev/null 2>&1; echo -e "${GREEN}Блокировка ${NC}QUIC ${GREEN}отключена${NC}\n"; read -p "Нажмите Enter..." dummy; else echo -e "\n${MAGENTA}Включаем блокировку QUIC${NC}"
uci add firewall rule >/dev/null 2>&1; uci set firewall.@rule[-1].name='Block_UDP_80' >/dev/null 2>&1; uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1; uci set firewall.@rule[-1].src='lan' >/dev/null 2>&1
uci set firewall.@rule[-1].dest='wan' >/dev/null 2>&1; uci set firewall.@rule[-1].dest_port='80' >/dev/null 2>&1; uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1
uci add firewall rule >/dev/null 2>&1; uci set firewall.@rule[-1].name='Block_UDP_443' >/dev/null 2>&1; uci add_list firewall.@rule[-1].proto='udp' >/dev/null 2>&1; uci set firewall.@rule[-1].src='lan' >/dev/null 2>&1
uci set firewall.@rule[-1].dest='wan' >/dev/null 2>&1; uci set firewall.@rule[-1].dest_port='443' >/dev/null 2>&1; uci set firewall.@rule[-1].target='REJECT' >/dev/null 2>&1
uci commit firewall >/dev/null 2>&1; /etc/init.d/firewall restart >/dev/null 2>&1;	echo -e "${GREEN}Блокировка ${NC}QUIC ${GREEN}включена${NC}\n";	read -p "Нажмите Enter..." dummy; fi; }
# ==========================================
# Системное меню
# ==========================================
sys_menu(){ while true; do web_is_enabled && WEB_TEXT="Удалить доступ к скрипту из браузера" || WEB_TEXT="Активировать доступ к скрипту из браузера"
quic_is_blocked && QUIC_TEXT="${GREEN}Отключить блокировку${NC} QUIC ${GREEN}(80,443)${NC}" || QUIC_TEXT="${GREEN}Включить блокировку${NC} QUIC ${GREEN}(80,443)${NC}"
clear; echo -e "${MAGENTA}Системное меню${NC}\n"; printed=0; if web_is_enabled; then echo -e "${YELLOW}Доступ из браузера:${NC} http://192.168.1.1:7681"; printed=1; fi
if quic_is_blocked; then echo -e "${YELLOW}Блокировка QUIC:${NC}    ${GREEN}включена${NC}"; printed=1; fi
[ "$printed" -eq 1 ] && echo; echo -e "${CYAN}1) ${GREEN}Системная информация${NC}\n${CYAN}2) ${GREEN}$WEB_TEXT${NC}\n${CYAN}3) ${GREEN}$QUIC_TEXT${NC}"
if uci get firewall.@defaults[0].flow_offloading 2>/dev/null | grep -q '^1$' || uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null | grep -q '^1$'
then if ! grep -q 'meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;' /usr/share/firewall4/templates/ruleset.uc; then
echo -e "${CYAN}4) ${GREEN}Применить ${NC}FIX${GREEN} для работы ${NC}Zapret${GREEN} с включённым ${NC}Flow Offloading${NC}"; fi; fi
echo -ne "${CYAN}Enter) ${GREEN}Выход в главное меню${NC}\n\n${YELLOW}Выберите пункт:${NC} " && read -r choiceMN; case "$choiceMN" in
1) wget -q -U "Mozilla/5.0" -O - https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/sys_info.sh | sh; echo; read -p "Нажмите Enter..." dummy ;;
2) toggle_web ;; 3) toggle_quic ;; 4) if uci get firewall.@defaults[0].flow_offloading 2>/dev/null | grep -q '^1$' || uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null | grep -q '^1$'; then
if ! grep -q 'meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;' /usr/share/firewall4/templates/ruleset.uc; then echo -e "\n${MAGENTA}Применяем FIX для Flow Offloading${NC}"
sed -i 's/meta l4proto { tcp, udp } flow offload @ft;/meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;/' /usr/share/firewall4/templates/ruleset.uc; fw4 restart >/dev/null 2>&1
echo -e "FIX ${GREEN}успешно применён!${NC}\n"; read -p "Нажмите Enter..." dummy; fi; else break; fi ;; *) echo; return ;; esac; done; }
# ==========================================
# Главное меню
# ==========================================
show_menu() { get_versions; get_doh_status; clear; echo -e "╔════════════════════════════════════╗\n║     ${BLUE}Zapret on remittor Manager${NC}     ║\n╚════════════════════════════════════╝\n                     ${DGRAY}by StressOzz v$ZAPRET_MANAGER_VERSION${NC}"
for pkg in byedpi youtubeUnblock; do if opkg list-installed | grep -q "^$pkg"; then echo -e "\n${RED}Найден установленный ${NC}$pkg${RED}!${NC}\nZapret${RED} может работать некорректно с ${NC}$pkg${RED}!${NC}"; fi; done
if uci get firewall.@defaults[0].flow_offloading 2>/dev/null | grep -q '^1$' || uci get firewall.@defaults[0].flow_offloading_hw 2>/dev/null | grep -q '^1$'; 
then if ! grep -q 'meta l4proto { tcp, udp } ct original packets ge 30 flow offload @ft;' /usr/share/firewall4/templates/ruleset.uc; then echo -e "\n${RED}Включён ${NC}Flow Offloading${RED}!${NC}\n${NC}Zapret${RED} некорректно работает с включённым ${NC}Flow Offloading${RED}!\nПримените ${NC}FIX${RED} в системном меню!${NC}"
fi; fi; menu_game=$( [ -f "$CONF" ] && grep -q "1024-19293,19345-49999,50101-65535" "$CONF" && echo "Удалить стратегию для игр" || echo "Добавить стратегию для игр" ); pgrep -f "/opt/zapret" >/dev/null 2>&1 && str_stp_zpr="Остановить" || str_stp_zpr="Запустить"
echo -e "\n${YELLOW}Установленная версия:   ${INST_COLOR}$INSTALLED_DISPLAY${NC}"; [ -n "$ZAPRET_STATUS" ] && echo -e "${YELLOW}Статус Zapret:${NC}          $ZAPRET_STATUS"; show_script_50 && [ -n "$name" ] && echo -e "${YELLOW}Установлен скрипт:${NC}      $name"
[ -f "$CONF" ] && grep -q "option NFQWS_PORTS_UDP.*1024-19293,19345-49999,50101-65535" "$CONF" && grep -q -- "--filter-udp=1024-19293,19345-49999,50101-65535" "$CONF" && echo -e "${YELLOW}Стратегия для игр:${NC}      ${GREEN}активирована${NC}"
[ -n "$DOH_STATUS" ] && opkg list-installed | grep -q '^https-dns-proxy ' && echo -e "${YELLOW}DNS over HTTPS:${NC}         $DOH_STATUS"; web_is_enabled && if web_is_enabled; then echo -e "${YELLOW}Доступ из браузера:${NC}     http://192.168.1.1:7681"; fi
quic_is_blocked && if quic_is_blocked; then echo -e "${YELLOW}Блокировка QUIC:${NC}        ${GREEN}включена${NC}"; fi; show_current_strategy && [ -n "$ver" ] && echo -e "${YELLOW}Используется стратегия:${NC} ${CYAN}$ver${NC}"
echo -e "\n${CYAN}1) ${GREEN}Установить${NC} Zapret\n${CYAN}2) ${GREEN}Меню выбора стратегий${NC}\n${CYAN}3) ${GREEN}Вернуть ${NC}настройки по умолчанию\n${CYAN}4) ${GREEN}$str_stp_zpr ${NC}Zapret"
echo -e "${CYAN}5) ${GREEN}Удалить ${NC}Zapret\n${CYAN}6) ${GREEN}$menu_game\n${CYAN}7) ${GREEN}Меню установки скриптов${NC}\n${CYAN}8) ${GREEN}Удалить → установить → настроить${NC} Zapret"
echo -e "${CYAN}9) ${GREEN}Меню ${NC}DNS over HTTPS\n${CYAN}0) ${GREEN}Системное меню${NC}" ; echo -ne "${CYAN}Enter) ${GREEN}Выход${NC}\n\n${YELLOW}Выберите пункт:${NC} " && read choice
case "$choice" in 1) install_Zapret ;; 2) menu_str ;; 3) comeback_def ;; 4) pgrep -f /opt/zapret >/dev/null 2>&1 && stop_zapret || start_zapret ;; 5) uninstall_zapret ;; 6) fix_GAME ;; 7) scrypt_install ;; 8) zapret_key ;;
9) DoH_menu ;; 0) sys_menu ;; *) echo; exit 0 ;; esac; }
# ==========================================
# Старт скрипта
# ==========================================
while true; do show_menu; done
