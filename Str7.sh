#!/bin/sh

GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
BLUE="\033[0;34m"
NC="\033[0m"

version="v4"

echo -e "${MAGENTA}Устанавливаем стратегию ${version}${NC}\n"

##############################################
# 1. Формируем списки из URL
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
https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/mylist.lst
"

TARGET_1="/opt/zapret/ipset/zapret-hosts-user.txt"
TMP_1="$(mktemp)"

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

    sed 's/^[ \t]*//; s/[ \t]*$//' "$TMP" \
        | grep -v '^$' \
        | grep -v '^\.' \
        | sort -u > "$TARGET"

    echo "Готово → $TARGET"
}

echo -e "${GREEN}🔴 ${CYAN}Генерируем списки${NC}"
process_list "$URLS_1" "$TMP_1" "$TARGET_1"
process_list "$URLS_2" "$TMP_2" "$TARGET_2"

rm -f "$TMP_1" "$TMP_2"

##############################################
# 2. Установка стратегии
##############################################

echo -e "${GREEN}🔴 ${CYAN}Меняем стратегию${NC}"

sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" /etc/config/zapret

cat <<EOF >> /etc/config/zapret
  option NFQWS_OPT '
#${version} УДАЛИТЕ ЭТУ СТРОЧКУ, ЕСЛИ ВНОСИТЕ ИЗМЕНЕНИЯ В СТРАТЕГИЮ !!!

--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--hostlist=/opt/zapret/ipset/zapret-hosts-user.txt
--dpi-desync=fake,fakeddisorder
--dpi-desync-split-pos=10,midsld
--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com
--dpi-desync-fake-tls=0x0F0F0F0F
--dpi-desync-fake-tls-mod=none
--dpi-desync-fakedsplit-pattern=/opt/zapret/files/fake/tls_clienthello_vk_com.bin
--dpi-desync-split-seqovl=336
--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_gosuslugi_ru.bin
--dpi-desync-fooling=badseq,badsum
--dpi-desync-badseq-increment=0
--new
--filter-udp=443
--dpi-desync=fake
--dpi-desync-repeats=4
--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
'
EOF

##############################################
# 3. Файлы исключений и служебные файлы
##############################################

echo -e "${GREEN}🔴 ${CYAN}Обновляем exclude-list${NC}"
exclude_file="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
remote_url="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"

rm -f "$exclude_file"
curl -fsSL "$remote_url" -o "$exclude_file" || echo -e "${RED}Не удалось загрузить exclude-list${NC}"

echo -e "${GREEN}🔴 ${CYAN}Копируем 4pda.bin${NC}"
curl -sLo /opt/zapret/files/fake/4pda.bin https://github.com/StressOzz/Zapret-Manager/raw/refs/heads/main/4pda.bin

##############################################
# 4. /etc/hosts
##############################################

echo -e "${GREEN}🔴 ${CYAN}Обновляем /etc/hosts${NC}"

file="/etc/hosts"
cat <<'EOF' | grep -Fxv -f "$file" 2>/dev/null >> "$file"
130.255.77.28 ntc.party
57.144.222.34 instagram.com www.instagram.com
173.245.58.219 rutor.info d.rutor.info
193.46.255.29 rutor.info
157.240.9.174 instagram.com www.instagram.com
EOF

/etc/init.d/dnsmasq restart >/dev/null 2>&1

##############################################
# 5. Применяем стратегию
##############################################

echo -e "${GREEN}🔴 ${CYAN}Применяем новую стратегию${NC}\n"

/opt/zapret/sync_config.sh 2>/dev/null
/etc/init.d/zapret restart >/dev/null 2>&1

echo -e "${BLUE}🔴 ${GREEN}Стратегия ${version} установлена!${NC}\n"
