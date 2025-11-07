#!/bin/sh
# check_sites_simple.sh — проверка доступности сайтов (OK / FAIL)

# Список сайтов (можно заменить на свой)
sites="
google.com
youtube.com
facebook.com
twitter.com
instagram.com
wikipedia.org
amazon.com
netflix.com
github.com
linkedin.com
"

for site in $sites; do
    # пытаемся подключиться через curl, таймаут 5 секунд
    if curl -Is --connect-timeout 5 --max-time 10 "https://$site" >/dev/null 2>&1; then
        echo "$site: OK"
    else
        echo "$site: FAIL"
    fi
done
