#!/bin/sh

TOTAL=30
FOUND_IPS=""
printf "\033[36m=== Обновление IP Instagram ===\033[0m\n"
printf "\033[32mЖдите, выполняется проверка %d раз…\033[0m\n\n" "$TOTAL"

# Очистка старых записей
sed -i '/instagram\.com/d' /etc/hosts
/etc/init.d/dnsmasq restart >/dev/null 2>&1

# Прогресс-бар пустой
PROGRESS=""
for i in $(seq 1 $TOTAL); do
    PROGRESS="${PROGRESS}□"
done
printf "%s\n" "$PROGRESS"

# Проверка
for i in $(seq 1 $TOTAL); do
    # Получаем IP
    IPs=$(dig @1.1.1.1 +https +short www.instagram.com | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
    NEW_FOUND=0
    for ip in $IPs; do
        echo "$FOUND_IPS" | grep -qx "$ip" && continue
        FOUND_IPS="$FOUND_IPS $ip"
        echo "$ip instagram.com www.instagram.com" >> /etc/hosts
        printf "\033[32mНовый IP найден: %s instagram.com www.instagram.com\033[0m\n" "$ip"
        NEW_FOUND=1
    done
    # Обновляем прогресс-бар
    PROGRESS=$(echo "$PROGRESS" | sed "s/□/■/$i")
    printf "\r%s" "$PROGRESS"
    sleep 0.1
done

# Финальный вывод
printf "\n"
/etc/init.d/dnsmasq restart >/dev/null 2>&1
printf "\n\033[36m=== Готово! ===\033[0m\n"
printf "\033[32mПерезапустите приложение и браузер и проверьте Instagram\033[0m\n"
