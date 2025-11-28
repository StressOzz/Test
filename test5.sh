#!/bin/sh

##############################################
# 1-й набор URL → первый итоговый файл
##############################################

URLS_1="
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

TARGET_1="/opt/zapret/ipset/zapret-hosts-user.txt"
TMP_1="$(mktemp)"

##############################################
# 2-й набор URL → второй итоговый файл
##############################################

URLS_2="
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/Twitter.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudflare.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudfront.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/digitalocean.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/discord.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/hetzner.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/meta.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/ovh.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/telegram.lst
https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/twitter.lst
"

TARGET_2="/opt/zapret/ipset/zapret-ip-user.txt"
TMP_2="$(mktemp)"

##############################################
# Функция скачивания и обработки списков
##############################################
process_list() {
    URLS="$1"
    TMP="$2"
    TARGET="$3"

    for url in $URLS; do
        NAME=$(basename "$url")
        echo "Скачиваю $NAME …"
        curl -fsSL "$url" >> "$TMP" || echo "Ошибка: $NAME"
        echo "" >> "$TMP"
    done

    # Фильтрация (убираем пустые, точки, дубли)
    sed 's/^[ \t]*//; s/[ \t]*$//' "$TMP" \
        | grep -v '^$' \
        | grep -v '^\.' \
        | sort -u > "$TARGET"

    echo "Готово → $TARGET"
}

##############################################
# Запуск генерации
##############################################
process_list "$URLS_1" "$TMP_1" "$TARGET_1"
process_list "$URLS_2" "$TMP_2" "$TARGET_2"

rm "$TMP_1" "$TMP_2"
