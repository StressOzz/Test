#!/bin/sh
# ==========================================
#   Zapret on remittor Manager by StressOzz
# ==========================================

# ---- Цвета ----
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
DGRAY="\033[38;5;236m"

clear

# ---- Блок: Модель и архитектура ----
echo -e "${GREEN}===== Модель и архитектура роутера =====${NC}"
cat /tmp/sysinfo/model
awk -F= '
  /DISTRIB_ARCH/   { gsub(/'\''/, ""); print $2 }
  /DISTRIB_TARGET/ { gsub(/'\''/, ""); print $2 }
' /etc/openwrt_release

# ---- Блок: Версия OpenWrt ----
echo -e "\n${GREEN}===== Версия OpenWrt =====${NC}"
awk -F= '
  /DISTRIB_DESCRIPTION/ {
    gsub(/'\''|OpenWrt /, "")
    print $2
  }
' /etc/openwrt_release

# ---- Блок: Пользовательские пакеты ----
echo -e "\n${GREEN}===== Пользовательские пакеты =====${NC}"
awk '
  /^Package:/ { p=$2 }
  /^Status: install user/ { print p }
' /usr/lib/opkg/status

# ---- Блок: Flow Offloading + DPI ----
echo -e "\n${GREEN}===== Flow Offloading =====${NC}"
sw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)

if grep -q "ct original packets ge 30" /usr/share/firewall4/templates/ruleset.uc; then
    dpi="yes"
else
    dpi="no"
fi

# ---- Вывод в одну строку ----
echo -e "SW:${sw:+on}${sw:-off} | HW:${hw:+on}${hw:-off} | FIX: ${dpi}"



# ==========================================
#            Проверка сайтов
# ==========================================

SITES=$(cat <<'EOF'
gosuslugi.ru
esia.gosuslugi.ru/login
rutube.ru
youtube.com
instagram.com
rutor.info
ntc.party
rutracker.org
epidemz.net.co
nnmclub.to
openwrt.org
sxyprn.net
pornhub.com
discord.com
x.com
filmix.my
flightradar24.com
genderize.io
# Можно добавлять комментарии
# Пустые строки тоже ок
EOF
)

echo -e "\n===== Доступность сайтов ====="

# Создаём массив сайтов
sites_array=""
i=0
for site in $SITES; do
    case "$site" in ""|\#*) continue ;; esac
    sites_array="$sites_array $site"
    i=$((i+1))
done

# Разделяем на левый и правый
len=$i
half=$(( (len + 1) / 2 ))

# Цикл по индексам
for idx in $(seq 1 $half); do
    # левый
    left=$(echo $sites_array | cut -d' ' -f$idx)
    if curl -Is --connect-timeout 1 --max-time 2 "https://$left" >/dev/null 2>&1; then
        left_status="${GREEN}OK${NC}"
    else
        left_status="${RED}FAIL${NC}"
    fi

    # правый
    right_idx=$((idx + half))
    right=$(echo $sites_array | cut -d' ' -f$right_idx)
    if [ -n "$right" ]; then
        if curl -Is --connect-timeout 1 --max-time 2 "https://$right" >/dev/null 2>&1; then
            right_status="${GREEN}OK${NC}"
        else
            right_status="${RED}FAIL${NC}"
        fi
        # Вывод через printf, цвета отображаются корректно
        printf "\033[0m%-35s %-35s\n" "[$left_status] $left" "[$right_status] $right"
    else
        printf "\033[0m%-35s\n" "[$left_status] $left"
    fi
done
echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
