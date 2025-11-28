#!/bin/sh

# URL-списки
URLS="
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/anime.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/block.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/geoblock.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/hodca.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/news.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/porn.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_ai.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_play.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hdrezka.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/tiktok.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/youtube.lst
"

TARGET="/opt/zapret-hosts-user.txt"   # куда собрать итог
TMP="$(mktemp)"

for url in $URLS; do
    echo "Скачиваю $url …"
    # используем curl, можно wget — если есть
    curl -fsSL "$url" >> "$TMP" || {
        echo "Ошибка при скачивании $url"
    }
    echo "" >> "$TMP"
done

# Фильтрация:
#  - убираем пробелы по краям
#  - убираем пустые строки
#  - удаляем строки, начинающиеся с .
#  - удаляем дубли
sed 's/^[ \t]*//; s/[ \t]*$//' "$TMP" \
    | grep -v '^$' \
    | grep -v '^\.' \
    | sort -u > "$TARGET"

rm "$TMP"

echo "Готово — результат в $TARGET"
