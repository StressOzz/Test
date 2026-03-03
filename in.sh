#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
DGRAY="\033[38;5;244m"
PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }



show_menu() {
clear
echo -e "╔═══════════════════════════════════════════╗"
echo -e "║ mixomo-openwrt on Internet-Helper Manager ║"
echo -e "╚═══════════════════════════════════════════╝"
echo -e "                                 by StressOzz"
echo
echo -e "1) Уставновить mixomo-openwrt"
echo -e "2) Удалить mixomo-openwrt"
echo -e "3) Сменить список MagiTrickle"
echo -e "4) Сгененрировать WARP"
echo -e "5) Интегрировать WARP в mixomo-openwrt"
echo -e "6) Удалить → установить → настроить mixomo-openwrt"
echo -e "Enter) Выход"
echo -ne "Выберите пункт: " && read choice

case "$choice" in
1) $Z_ACTION_FUNC;;
2) start_zapret;;
3) menu_str;;
4) DoH_menu;;
5) Discord_menu;;
0) sys_menu;;
*) echo; exit 0;;
}
while true; do menu; done
