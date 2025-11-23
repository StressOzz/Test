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

echo -e "\n${GREEN}===== Доступность сайтов =====${NC}"

# Сохраняем все сайты в массив
sites_array=()
while IFS= read -r site; do
    case "$site" in ""|\#*) continue ;; esac
    sites_array+=("$site")
done <<< "$SITES"

# Находим середину массива для второго столбца
len=${#sites_array[@]}
half=$(( (len + 1) / 2 ))

# Выводим в 2 столбца
for i in $(seq 0 $((half - 1))); do
    left="${sites_array[i]}"
    right="${sites_array[i + half]:-}"

    # Проверяем доступность для левого
    if curl -Is --connect-timeout 1 --max-time 2 "https://$left" >/dev/null 2>&1; then
        left_status="[${GREEN}OK${NC}]"
    else
        left_status="[${RED}FAIL${NC}]"
    fi

    # Проверяем доступность для правого (если есть)
    if [ -n "$right" ]; then
        if curl -Is --connect-timeout 1 --max-time 2 "https://$right" >/dev/null 2>&1; then
            right_status="[${GREEN}OK${NC}]"
        else
            right_status="[${RED}FAIL${NC}]"
        fi
        printf "%-30s %-30s\n" "$left_status $left" "$right_status $right"
    else
        printf "%-30s\n" "$left_status $left"
    fi
done

echo ""
read -p "Нажмите Enter для выхода в главное меню..." dummy
echo ""
