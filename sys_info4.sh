#!/bin/sh
# ==========================================
#   Zapret Diagnostic Suite v2 by StressOzz
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

# ==========================================
#               ОСНОВНАЯ ИНФА
# ==========================================

echo -e "${GREEN}===== Модель и архитектура =====${NC}"
cat /tmp/sysinfo/model
awk -F= '
  /DISTRIB_ARCH/   { gsub(/'\''/, ""); print "ARCH: "$2 }
  /DISTRIB_TARGET/ { gsub(/'\''/, ""); print "TARGET: "$2 }
' /etc/openwrt_release
echo ""

echo -e "${GREEN}===== Версия OpenWrt =====${NC}"
awk -F= '/DISTRIB_DESCRIPTION/ {
  gsub(/'\''|OpenWrt /,"");
  print $2
}' /etc/openwrt_release
echo ""

echo -e "${GREEN}===== Flow Offloading =====${NC}"
sw=$(uci -q get firewall.@defaults[0].flow_offloading)
hw=$(uci -q get firewall.@defaults[0].flow_offloading_hw)
echo -e "SW: ${sw:+on}${sw:-off}   |   HW: ${hw:+on}${hw:-off}"
echo ""

echo -e "${GREEN}===== Пользовательские пакеты =====${NC}"
awk '
  /^Package:/ { p=$2 }
  /^Status: install user/ { print p }
' /usr/lib/opkg/status
echo ""


# ==========================================
#                  DNS
# ==========================================

echo -e "${MAGENTA}===== DNS =====${NC}"

DNS_IP=$(nslookup google.com 2>/dev/null | awk '/Server:/ {print $2}')
echo "Resolver: ${DNS_IP:-не удалось определить}"

DNS_TIME=$( ( time -p nslookup youtube.com >/dev/null 2>&1 ) 2>&1 | awk '/real/ {print $2}' )
echo "Время ответа: ${DNS_TIME}s"

if nslookup yandex.ru >/dev/null 2>&1; then
  echo -e "DNS доступность: ${GREEN}OK${NC}"
else
  echo -e "DNS доступность: ${RED}FAIL${NC}"
fi

echo ""


# ==========================================
#                SNI БЛОКИРОВКИ
# ==========================================

echo -e "${MAGENTA}===== Проверка SNI (TCP-connect) =====${NC}"

check_sni() {
  host="$1"
  if nc -z -w2 "$host" 443 >/dev/null 2>&1; then
    echo -e "  [$GREEN OK $NC] $host (TCP доступен)"
  else
    echo -e "  [$RED FAIL $NC] $host (TCP блокируется)"
  fi
}

check_sni youtube.com
check_sni instagram.com
check_sni rutor.info
check_sni rutracker.org
check_sni discord.com
echo ""


# ==========================================
#                 QUIC / UDP
# ==========================================

echo -e "${MAGENTA}===== Проверка QUIC (UDP/443) =====${NC}"

if nc -u -z -w2 google.com 443 >/dev/null 2>&1; then
  echo -e "UDP/443: ${GREEN}OK${NC}"
else
  echo -e "UDP/443: ${RED}FAIL${NC}"
fi
echo ""


# ==========================================
#                IPv6
# ==========================================

echo -e "${MAGENTA}===== IPv6 =====${NC}"

if curl -6 -Is --max-time 3 https://google.com >/dev/null 2>&1; then
  echo -e "IPv6: ${GREEN}OK${NC}"
else
  echo -e "IPv6: ${RED}Нет IPv6 или блокируется${NC}"
fi
echo ""


# ==========================================
#                 MTU
# ==========================================

echo -e "${MAGENTA}===== MTU =====${NC}"
MTU_TEST=$(ping -4 -M do -s 1472 8.8.8.8 -c1 2>/dev/null | grep '0% packet loss')
if [ -n "$MTU_TEST" ]; then
  echo -e "MTU 1500: ${GREEN}OK${NC}"
else
  echo -e "MTU 1500: ${YELLOW}Фрагментация / возможные проблемы${NC}"
fi
echo ""


# ==========================================
#           Проверка Offload-правил
# ==========================================

echo -e "${MAGENTA}===== Проверка правил Offload =====${NC}"

if grep -q "ct original packets ge 30" /usr/share/firewall4/templates/ruleset.uc; then
  echo -e "Правка DPI-offload: ${GREEN}OK${NC}"
else
  echo -e "Правка DPI-offload: ${RED}НЕ НАЙДЕНА${NC}"
fi
echo ""


# ==========================================
#              Мини тест скорости
# ==========================================

echo -e "${MAGENTA}===== Скорость (мини-тест) =====${NC}"
START=$(date +%s)
curl -o /dev/null -s https://speed.cloudflare.com/__down?bytes=5000000
END=$(date +%s)
TIME=$((END-START))

if [ "$TIME" -gt 0 ]; then
  SPEED=$((5 / TIME))
  echo "~≈ ${SPEED} МБ/с (приблизительно)"
else
  echo "Не удалось измерить"
fi
echo ""


# ==========================================
#              Проверка сайтов
# ==========================================

echo -e "${GREEN}===== Доступность сайтов =====${NC}"

SITES="
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
x.com
filmix.my
"

echo "$SITES" | while IFS= read -r site; do
    case "$site" in ""|\#*) continue ;; esac
    if curl -Is --connect-timeout 2 --max-time 3 "https://$site" >/dev/null 2>&1; then
        echo -e "  [${GREEN}OK${NC}]   $site"
    else
        echo -e "  [${RED}FAIL${NC}] $site"
    fi
done

echo -e "--------------------------------------"
echo -e "${CYAN}Готово.${NC}"
echo ""

read -p "Нажмите Enter для выхода..." dummy
