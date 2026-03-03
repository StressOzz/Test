#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
DGRAY="\033[38;5;244m"
CONFIGPATH="/etc/magitrickle/state/config.yaml"
URL_DEFAULT="https://raw.githubusercontent.com/StressOzz/Use_WARP_on_OpenWRT/refs/heads/main/files/MagiTrickle/config.yaml"
URL_ITDOG="https://raw.githubusercontent.com/StressOzz/Use_WARP_on_OpenWRT/refs/heads/main/files/MagiTrickle/configAD.yaml"

PAUSE() { echo -ne "Нажмите Enter..."; read dummy; }

magitrickle_config() {
echo
echo -e "Выбор списка для MagiTrickle"
echo -e "1) ITDog Allow Domains"
echo -e "2) Internet Helper"
echo -e "3) Oставить текущий список"
echo

  while true; do
    echo -en "Введите номер: "
    read -r choice
    choice="${choice:-2}"

    case "$choice" in
      1) MAGITRICKLE_CONFIG_URL="$URL_ITDOG"; return 0 ;;
      2) MAGITRICKLE_CONFIG_URL="$URL_DEFAULT"; return 0 ;;
      3) MAGITRICKLE_CONFIG_URL=""; return 0 ;;
      *) echo "Неверный выбор. Введите 1, 2 или 3." ;;
    esac
  done

if [ -n "$MAGITRICKLE_CONFIG_URL" ]; then
  wget -q -O "$CONFIGPATH" "$MAGITRICKLE_CONFIG_URL" || {
    echo "Ошибка: не удалось скачать список!"
    echo "URL: $MAGITRICKLE_CONFIG_URL"
    return 1
  }

  if [ ! -s "$CONFIGPATH" ]; then
  echo; echo "Ошибка: config пустой/не создан: $CONFIGPATH"; echo
  fi
fi
}

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
echo -ne "Выберите пункт: " && read choiceM

case "$choiceM" in
1) sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/mixomo_openwrt_install.sh); PAUSE;;
2) sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/mixomo_openwrt_delete.sh); PAUSE;;
3) magitrickle_config; PAUSE;;
4) sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/gen_WARP.sh); PAUSE;;
5) sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/WARP_to_conf.sh); PAUSE;;
0) sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/mixomo_openwrt_install.sh)
   sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/gen_WARP.sh)
   sh <(wget -O - https://raw.githubusercontent.com/StressOzz/WARP_on_OpenWRT/main/WARP_to_conf.sh); PAUSE;;
*) echo; exit 0;;
}
while true; do menu; done
