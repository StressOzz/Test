#!/bin/sh
# ==========================================
# Zapret on remittor Manager by StressOzz
# ==========================================
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"
DGRAY="\033[38;5;236m"
WORKDIR="/tmp/zapret-update"
CONF="/etc/config/zapret"
CUSTOM_DIR="/opt/zapret/init.d/openwrt/custom.d/"

clear
echo -e "${GREEN}===== Model =====${NC}"; cat /tmp/sysinfo/model;
echo -e "\n${GREEN}===== OpenWrt =====${NC}"; awk -F= '/DISTRIB_DESCRIPTION/ {gsub(/'\''/, ""); print "Версия OpenWrt: "$2} /DISTRIB_ARCH/ {gsub(/'\''/, ""); print "Процессор: "$2} /DISTRIB_TARGET/ {gsub(/'\''/, ""); print "Платформа: "$2}' /etc/openwrt_release;
echo -e "\n${GREEN}===== User Packages =====${NC}"; awk '/^Package:/ {p=$2} /^Status: install user/ {print p}' /usr/lib/opkg/status;
echo -e "\n${GREEN}===== Flow Offloading =====${NC}"; sw=$(uci -q get firewall.@defaults[0].flow_offloading); hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw); echo -e "SW: ${sw:+on}${sw:-off} | HW: ${hw:+on}${hw:-off}";
echo -e "\n${GREEN}===== GitHub API Rate Limit =====${NC}"; echo -e "Core remaining: $(curl -s https://api.github.com/rate_limit | sed -n 's/.*\"remaining\": \([0-9]*\).*/\1/p' | head -1)\n"

#!/bin/sh
# simple_check_sites.sh — список встроен прямо в скрипт

SITES=$(cat <<'EOF'

youtube.com
instagram.com
rutor.info
ntc.party
rutracker.org
epidemz.net.co
nnmclub.to
openwrt.org
pornhub.com
discord.com
genderize.io
x.com
filmix.my
# Можно добавлять комментарии
# Пустые строки тоже ок
EOF
)

echo "Проверяю доступность сайтов:"
echo "--------------------------------------"

echo "$SITES" | while IFS= read -r site; do
    case "$site" in
        ""|\#*) continue ;;
    esac

    if curl -Is --connect-timeout 3 --max-time 5 "https://$site" >/dev/null 2>&1; then
        echo "[OK]   $site"
    else
        echo "[FAIL] $site"
    fi
done

echo "--------------------------------------"
echo "Готово."



read -p "Нажмите Enter для выхода в главное меню..." dummy

