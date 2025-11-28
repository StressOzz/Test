#!/bin/sh

BASE_DOMAINS="https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main"
BASE_SUBNETS="https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4"

##############################################
# 1. Доменные списки → /etc/domains.list
##############################################

FILES_DOMAINS="
inside-kvas.lst
anime.lst
block.lst
geoblock.lst
hodca.lst
news.lst
porn.lst
cloudflare.lst
cloudfront.lst
digitalocean.lst
discord.lst
google_ai.lst
google_play.lst
hdrezka.lst
hetzner.lst
meta.lst
ovh.lst
telegram.lst
tiktok.lst
twitter.lst
youtube.lst
"

TARGET_DOMAINS="/etc/zapret-hosts-user.txt"
TMP_DOMAINS="$(mktemp)"

##############################################
# 2. IPv4 подсети → /etc/subnets.list
##############################################

FILES_SUBNETS="
Discord.lst
Meta.lst
Twitter.lst
cloudflare.lst
cloudfront.lst
digitalocean.lst
discord.lst
hetzner.lst
meta.lst
ovh.lst
telegram.lst
twitter.lst
"

TARGET_SUBNETS="/etc/zapret-ip-user.txt"
TMP_SUBNETS="$(mktemp)"

##############################################
# Функция скачивания и обработки файлов
##############################################
process_group() {
    BASE="$1"
    LIST="$2"
    TMP="$3"
    TARGET="$4"

    for f in $LIST; do
        echo "Скачиваю $f …"
        curl -fsSL "$BASE/$f" >> "$TMP" || echo "Ошибка: $f"
        echo "" >> "$TMP"
    done

    # Фильтрация
    sed 's/^[ \t]*//; s/[ \t]*$//' "$TMP" \
        | grep -v '^$' \
        | grep -v '^\.' \
        | sort -u > "$TARGET"

    echo "Готово → $TARGET"
}

##############################################
# Запуск
##############################################

process_group "$BASE_DOMAINS" "$FILES_DOMAINS" "$TMP_DOMAINS" "$TARGET_DOMAINS"
process_group "$BASE_SUBNETS" "$FILES_SUBNETS" "$TMP_SUBNETS" "$TARGET_SUBNETS"

rm "$TMP_DOMAINS" "$TMP_SUBNETS"
