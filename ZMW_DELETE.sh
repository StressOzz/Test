#!/bin/sh
# Version: 1.0

GREEN="\033[1;32m"; CYAN="\033[1;36m"; YELLOW="\033[1;33m"; MAGENTA="\033[1;35m"; NC="\033[0m"

_zu_say() { echo -e "${CYAN}==>${NC} $*"; }
_zu_ok() { echo -e "   ${GREEN}✓${NC} $*"; }
_zu_step() { echo -e "   → $*"; }
_zu_warn() { echo -e "   ${YELLOW}!${NC} $*"; }

ZU_BACKEND="/opt/zapret-manager-luci/backend.sh"
ZU_JOBS="/tmp/zapret-manager-luci"
ZU_CRON="/etc/crontabs/root"
ZU_YES=0
[ "$1" = "-y" ] || [ "$1" = "--yes" ] && ZU_YES=1

ZU_FLASH="/opt/zapret-manager-luci
/usr/libexec/rpcd/zapret-manager
/usr/share/rpcd/acl.d/luci-app-zapret-manager.json
/usr/share/luci/menu.d/luci-app-zapret-manager.json
/www/luci-static/resources/view/zapret-manager
/www/luci-static/resources/zapret-manager
/www/luci-static/resources/bytetube
/www/luci-static/resources/view/bytetube
/www/zm
/www/zm-webui.html
/etc/zm-warp-own.conf
/etc/hosts.zmtmp
/etc/hosts.zmdrop"

ZU_GLOBS="/usr/lib/zapret-manager* /etc/zapret_manager_expert_mode*"

ZU_TMP="/tmp/zapret-manager-luci* /tmp/zm-run.* /tmp/zm-wait.* /tmp/zm-quiet.* /tmp/zm-pkg.* /tmp/zm-rpc.* /tmp/zm-zash /tmp/zm-rpcd-plugin.stamp \
/tmp/zm-fk-pingloop.* /tmp/zm-fk-fallback.* /tmp/zm_update_install.sh /tmp/zm_update_install.log /tmp/zm_uninstall_panel.sh \
/tmp/luci-indexcache* /tmp/luci-modulecache/*"

_zu_kb() {
	[ $# -gt 0 ] || { echo 0; return 0; }
	du -sk "$@" 2>/dev/null | awk '{ s += $1 } END { print s + 0 }'
}

_zu_kill_tree() {
	local c
	for c in $(cat "/proc/$1/task/$1/children" 2>/dev/null); do _zu_kill_tree "$c"; done
	kill -9 "$1" 2>/dev/null
}

_zu_present() {
	local f
	for f in $ZU_FLASH; do [ -e "$f" ] || [ -L "$f" ] && return 0; done
	for f in $ZU_GLOBS; do [ -e "$f" ] || [ -L "$f" ] && return 0; done
	[ -d "$ZU_JOBS" ] && return 0
	grep -q '/opt/zapret-manager-luci/backend.sh' "$ZU_CRON" 2>/dev/null && return 0
	uci -q get uhttpd.zmweb >/dev/null 2>&1 && return 0
	return 1
}

echo -e "\n${MAGENTA}Zapret Manager для LuCI и Web UI — полное удаление${NC}\n"

if [ "$(id -u 2>/dev/null)" != 0 ]; then
	_zu_warn "Запустите скрипт от root"
	exit 1
fi

if ! _zu_present; then
	_zu_ok "Zapret Manager (LuCI и Web UI) на роутере не найден — удалять нечего"
	echo
	exit 0
fi

echo "Будет удалено всё, что относится к панели Zapret Manager: приложение в LuCI, Web UI,"
echo "её служебные файлы, задания в планировщике и временные файлы."
echo "Установленные пакеты (Zapret, Steer, Forkozz, Mixomo и остальные) и их настройки останутся."
echo
if [ "$ZU_YES" != 1 ]; then
	if [ -t 0 ]; then
		printf 'Удалить панель? [y/N]: '
		read -r ZU_ANS
		case "$ZU_ANS" in y|Y|yes|YES|д|Д|да|ДА) ;; *) echo; _zu_warn "Отменено — ничего не изменено"; echo; exit 0 ;; esac
		echo
	else
		_zu_warn "Нет терминала для подтверждения — запустите с ключом -y"
		echo
		exit 1
	fi
fi

ZU_BEFORE_F="$(_zu_kb $ZU_FLASH $ZU_GLOBS)"
ZU_BEFORE_T="$(_zu_kb $ZU_TMP)"

_zu_say "Останавливаем операции панели"
ZU_N=0
if [ -d "$ZU_JOBS" ]; then
	for ZU_P in "$ZU_JOBS"/*.pid; do
		[ -f "$ZU_P" ] || continue
		ZU_PID="$(cat "$ZU_P" 2>/dev/null)"
		case "$ZU_PID" in ''|*[!0-9]*) continue ;; esac
		kill -0 "$ZU_PID" 2>/dev/null || continue
		_zu_kill_tree "$ZU_PID"
		ZU_N=$((ZU_N + 1))
	done
fi
for ZU_PID in $(ps w 2>/dev/null | grep -e '[z]apret-manager-luci/backend.sh' -e '[z]m_update_install.sh' -e '[z]m_uninstall_panel.sh' -e '[l]ibexec/rpcd/zapret-manager' | awk '{ print $1 }'); do
	[ "$ZU_PID" = "$$" ] && continue
	kill -9 "$ZU_PID" 2>/dev/null && ZU_N=$((ZU_N + 1))
done
nft delete table inet zm_rb_ztest >/dev/null 2>&1
if [ "$ZU_N" -gt 0 ]; then _zu_ok "Остановлено процессов: $ZU_N"; else _zu_ok "Активных операций нет"; fi

_zu_say "Отключаем служебные задачи панели"
if [ -x "$ZU_BACKEND" ]; then
	"$ZU_BACKEND" redbtn_panel_gone >/dev/null 2>&1
	_zu_ok "Служебные правила панели сняты"
else
	if [ -x /etc/init.d/zm-geodns ]; then
		/etc/init.d/zm-geodns stop >/dev/null 2>&1
		/etc/init.d/zm-geodns disable >/dev/null 2>&1
	fi
	rm -f /etc/init.d/zm-geodns /etc/rc.d/*zm-geodns 2>/dev/null
	ZU_DNS=0
	for ZU_F in /tmp/dnsmasq.d/zm-geo.conf /tmp/dnsmasq.cfg*.d/zm-geo.conf; do
		[ -f "$ZU_F" ] && { rm -f "$ZU_F"; ZU_DNS=1; }
	done
	[ "$ZU_DNS" = 1 ] && /etc/init.d/dnsmasq restart >/dev/null 2>&1
	_zu_ok "Основной файл панели уже отсутствует — служебные остатки убраны вручную"
fi
ZU_CRON_N=0
if [ -f "$ZU_CRON" ]; then
	ZU_CRON_N="$(grep -c -e '/opt/zapret-manager-luci/backend.sh' -e '# zm-rpcd-watch$' "$ZU_CRON" 2>/dev/null)"
	ZU_CRON_N="${ZU_CRON_N:-0}"
	if [ "$ZU_CRON_N" -gt 0 ]; then
		sed -i -e '\#/opt/zapret-manager-luci/backend.sh#d' -e '/# zm-rpcd-watch$/d' "$ZU_CRON"
		[ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1
	fi
fi
_zu_ok "Заданий убрано из планировщика: $ZU_CRON_N"

_zu_say "Выключаем Web UI"
if uci -q get uhttpd.zmweb >/dev/null 2>&1; then
	uci -q delete uhttpd.zmweb
	uci -q commit uhttpd
	ZU_WEB=1
	_zu_ok "Порт Web UI закрыт"
else
	ZU_WEB=0
	_zu_ok "Web UI уже выключен"
fi

_zu_say "Удаляем файлы панели"
ZU_TRY=0
while :; do
	for ZU_F in $ZU_FLASH; do rm -rf "$ZU_F" 2>/dev/null; done
	rm -rf $ZU_GLOBS 2>/dev/null
	ZU_LEFT=""
	for ZU_F in $ZU_FLASH $ZU_GLOBS; do
		[ -e "$ZU_F" ] || [ -L "$ZU_F" ] && ZU_LEFT="$ZU_LEFT $ZU_F"
	done
	[ -z "$ZU_LEFT" ] && break
	[ "$ZU_TRY" -ge 4 ] && break
	ZU_TRY=$((ZU_TRY + 1))
	sleep 1
done
if [ -s /etc/zm-steer/owned ]; then
	_zu_step "Steer установлен — его список сервисов /usr/share/zm-redbtn оставлен"
else
	rm -rf /usr/share/zm-redbtn 2>/dev/null
fi
if [ -z "$ZU_LEFT" ]; then _zu_ok "Файлы LuCI и Web UI удалены"
else _zu_warn "Не удалось удалить:$ZU_LEFT"; fi

_zu_say "Чистим временные файлы"
rm -rf $ZU_TMP 2>/dev/null
_zu_ok "Временные файлы и кэш LuCI убраны"

_zu_say "Перезапускаем службы"
if [ -x /etc/init.d/rpcd ]; then
	/etc/init.d/rpcd restart >/dev/null 2>&1
	_zu_ok "rpcd перезапущен — LuCI больше не видит панель"
fi
if [ "$ZU_WEB" = 1 ] && [ -x /etc/init.d/uhttpd ]; then
	/etc/init.d/uhttpd restart >/dev/null 2>&1
	_zu_ok "uhttpd перезапущен"
fi

_zu_say "Проверяем, что ничего не осталось"
ZU_BAD=0
for ZU_F in $ZU_FLASH $ZU_GLOBS /tmp/zapret-manager-luci; do
	if [ -e "$ZU_F" ] || [ -L "$ZU_F" ]; then _zu_warn "Остался файл: $ZU_F"; ZU_BAD=1; fi
done
if grep -q '/opt/zapret-manager-luci/backend.sh' "$ZU_CRON" 2>/dev/null; then _zu_warn "В планировщике остались задания панели"; ZU_BAD=1; fi
if uci -q get uhttpd.zmweb >/dev/null 2>&1; then _zu_warn "Настройка Web UI в uhttpd осталась"; ZU_BAD=1; fi
if command -v ubus >/dev/null 2>&1; then
	ZU_I=0
	while ubus list zapret-manager >/dev/null 2>&1; do
		[ "$ZU_I" -ge 8 ] && break
		ZU_I=$((ZU_I + 1))
		sleep 1
	done
	if ubus list zapret-manager >/dev/null 2>&1; then _zu_warn "rpcd ещё держит панель — выполните: /etc/init.d/rpcd restart"; ZU_BAD=1; fi
fi
[ "$ZU_BAD" = 0 ] && _zu_ok "Остатков нет"

echo
if [ "$ZU_BAD" = 0 ]; then echo -e "${GREEN}Готово: Zapret Manager (LuCI и Web UI) полностью удалён${NC}"
else echo -e "${YELLOW}Удаление завершено с замечаниями — смотрите строки выше${NC}"; fi
echo -e "${CYAN}Освобождено:${NC} флеш ${ZU_BEFORE_F:-0} КБ, /tmp ${ZU_BEFORE_T:-0} КБ"
echo -e "${CYAN}Не тронуто:${NC} установленные пакеты, их настройки и команда zms"
echo
