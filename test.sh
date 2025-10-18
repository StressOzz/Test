#!/bin/sh
# =====================================================
# 🧹 OpenWRT Cleaner v3 — умная очистка с отчётом
# Автор: Grok × GPT-5
# Совместимо с OpenWRT 23–24+ (fw4)
# =====================================================

# Цвета
WHITE="\033[1;37m"
CYAN="\033[1;36m"
GREEN="\033[1;32m"
RED="\033[1;31m"
GRAY="\033[0;37m"
RESET="\033[0m"

clear
echo -e "\n${CYAN}▶ Запуск OpenWRT Cleaner v3...${RESET}\n"
sleep 1

# --- Функции измерения свободного места ---
get_free_space_h() {
    if df /overlay >/dev/null 2>&1; then
        df -h /overlay | awk 'NR==2 {print $4}'
    else
        df -h / | awk 'NR==2 {print $4}'
    fi
}

get_free_space_kb() {
    if df /overlay >/dev/null 2>&1; then
        df -k /overlay | awk 'NR==2 {print $4}'
    else
        df -k / | awk 'NR==2 {print $4}'
    fi
}

before_h=$(get_free_space_h)
before_kb=$(get_free_space_kb)

echo -e "${WHITE}Свободно до очистки:${RESET} ${GREEN}${before_h}${RESET}\n"

# --- Резервное копирование ---
echo -e "${WHITE}→ Рекомендуется создать резервную копию перед очисткой.${RESET}"
read -p "Создать резервную копию конфигурации? (y/n): " backup
if [ "$backup" = "y" ]; then
    sysupgrade -b /tmp/backup-$(date +%Y%m%d-%H%M).tar.gz
    echo -e "${GREEN}✔ Резервная копия создана в /tmp.${RESET}\n"
else
    echo -e "${GRAY}ℹ Резервное копирование пропущено.${RESET}\n"
fi

# --- Очистка кеша opkg ---
echo -e "${WHITE}→ Очистка кеша пакетов opkg...${RESET}"
rm -rf /tmp/opkg-lists/* 2>/dev/null
opkg clean 2>/dev/null
echo -e "${GREEN}✔ opkg кеш очищен.${RESET}\n"

# --- Очистка логов ---
echo -e "${WHITE}→ Удаляем старые системные логи...${RESET}"
if [ -d /var/log ]; then
    find /var/log -type f -mtime +3 -size +1k -delete 2>/dev/null
    echo -e "${GREEN}✔ Логи старше 3 дней удалены.${RESET}\n"
else
    echo -e "${GRAY}ℹ Папка /var/log не найдена.${RESET}\n"
fi

# --- Очистка кешей LuCI и dnsmasq ---
echo -e "${WHITE}→ Чистим кеш LuCI и DNS...${RESET}"
if ls /tmp/luci-* >/dev/null 2>&1; then
    rm -rf /tmp/luci-*
    echo -e "${GREEN}✔ Кеш LuCI очищен.${RESET}"
else
    echo -e "${GRAY}ℹ Кеш LuCI не найден.${RESET}"
fi

if [ -d /tmp/dnsmasq.d ]; then
    rm -rf /tmp/dnsmasq.d
    /etc/init.d/dnsmasq restart >/dev/null 2>&1
    echo -e "${GREEN}✔ Кеш DNS очищен.${RESET}\n"
else
    echo -e "${GRAY}ℹ Кеш DNS не найден.${RESET}\n"
fi

# --- Очистка временных файлов ---
echo -e "${WHITE}→ Удаляем временные файлы...${RESET}"
find /tmp -mindepth 1 ! -path "/tmp/opkg-lists*" -delete 2>/dev/null
find /var/tmp -mindepth 1 -delete 2>/dev/null
echo -e "${GREEN}✔ Временные файлы очищены.${RESET}\n"

# --- Очистка логов logread ---
if command -v logread >/dev/null 2>&1 && logread -C >/dev/null 2>&1; then
    echo -e "${WHITE}→ Сброс системного журнала (logread)...${RESET}"
    echo -e "${GREEN}✔ logread очищен.${RESET}\n"
else
    echo -e "${GRAY}ℹ logread не поддерживает очистку или отсутствует.${RESET}\n"
fi

# --- Очистка Docker (если установлен) ---
if command -v docker >/dev/null 2>&1; then
    echo -e "${WHITE}→ Очистка Docker (все контейнеры и образы будут удалены)...${RESET}"
    docker system prune -af --volumes
    echo -e "${GREEN}✔ Docker очищен.${RESET}\n"
else
    echo -e "${GRAY}ℹ Docker не установлен.${RESET}\n"
fi

# --- Проверка топа по размеру ---
echo -e "${WHITE}→ Топ-10 самых “тяжёлых” каталогов:${RESET}"
du -h -d1 / 2>/dev/null | sort -hr | head -10
echo -e ""

# --- Инфо по диску ---
echo -e "${WHITE}→ Использование диска (overlay/root):${RESET}"
df -h | grep -E '/overlay|/$'
echo -e ""

# --- Перезапуск служб ---
echo -e "${WHITE}→ Перезапуск сетевых и веб-служб (может прервать соединения)...${RESET}"
read -p "Перезапустить службы? (y/n): " confirm
if [ "$confirm" = "y" ]; then
    /etc/init.d/network restart >/dev/null 2>&1
    /etc/init.d/uhttpd restart >/dev/null 2>&1
    echo -e "${GREEN}✔ Службы перезапущены.${RESET}\n"
else
    echo -e "${GRAY}ℹ Перезапуск служб пропущен.${RESET}\n"
fi

# --- Итоговый отчёт ---
after_h=$(get_free_space_h)
after_kb=$(get_free_space_kb)
freed_kb=$((after_kb - before_kb))
freed_mb=$(awk "BEGIN {printf \"%.1f\", $freed_kb/1024}")

echo -e "${CYAN}=========================================${RESET}"
echo -e "${WHITE}📊 Итоговый отчёт:${RESET}"
echo -e "${GRAY}Свободно до:${RESET} ${RED}${before_h}${RESET}"
echo -e "${GRAY}Свободно после:${RESET} ${GREEN}${after_h}${RESET}"
echo -e "${GRAY}Освобождено:${RESET} ${GREEN}${freed_mb} MB${RESET}"
echo -e "${CYAN}=========================================${RESET}\n"

echo -e "${GREEN}✅ Очистка завершена. Система готова к работе.${RESET}\n"
