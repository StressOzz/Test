#!/bin/sh
# mihomo-all-groups-generator.sh - АБСОЛЮТНО НОВЫЙ список ВСЕХ групп
# Сохраняет в /root/mihomo-new-groups.mtrickle
# НЕТ дублирования, НЕТ пропусков, НИЧЕГО не применяет!

OUTPUT_FILE="/root/mihomo-new-groups.mtrickle"
GEN_DIR="/tmp/mihomo-gen"
mkdir -p "$GEN_DIR"
cd "$GEN_DIR"

# Очищаем
> "$OUTPUT_FILE"
echo "🆕 Создание АБСОЛЮТНО НОВОГО списка... $(date)" > "$OUTPUT_FILE"

# Генератор ID
gen_id() {
    openssl rand -hex 4 2>/dev/null | tr -d '\n' || echo $(date +%s | md5sum | cut -c1-8)
}

# Создание группы (ВСЕ правила)
create_group() {
    local name="$1"
    local domains_url="$2"
    local ips_url="$3"
    local color="$4"
    
    echo "Создание группы: $name"
    local group_id=$(gen_id)
    
    # Заголовок группы
    cat >> "$OUTPUT_FILE" << EOF
groupsid${group_id},name${name},color${color},interfaceMihomo,enabletrue,rulesenabletrue,
EOF
    
    # ДОМЕНЫ
    if [ -n "$domains_url" ]; then
        echo "  └─ Домены ($domains_url)"
        wget -T 5 -q -O - "$domains_url" 2>/dev/null | \
        grep -E '^[a-zA-Z0-9]' | \
        sed 's/#.*$//; s/[[:space:]]*$//' | \
        while read -r domain; do
            [ -n "$domain" ] || continue
            rule_id=$(gen_id)
            echo "name,rule${domain},typedomain,enabletrue," >> "$OUTPUT_FILE"
        done
    fi
    
    # IP ПОДСЕТИ  
    if [ -n "$ips_url" ]; then
        echo "  └─ IP ($ips_url)"
        wget -T 5 -q -O - "$ips_url" 2>/dev/null | \
        grep -E '^[0-9]' | \
        sed 's/#.*$//; s/[[:space:]]*$//' | \
        while read -r ipcidr; do
            [ -n "$ipcidr" ] || continue
            rule_id=$(gen_id)
            echo "name,rule${ipcidr},typesubnet,enabletrue," >> "$OUTPUT_FILE"
        done
    fi
    
    echo "" >> "$OUTPUT_FILE"
}

# ❌ ВСЕ ГРУППЫ БЕЗ ПРОПУСКОВ ❌
create_group "Russia_kvas" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Russia/inside-kvas.lst" "" "ffcc00"
create_group "Anime" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/anime.lst" "" "ff69b4" 
create_group "Block" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/block.lst" "" "ff0000"
create_group "GeoBlock" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/geoblock.lst" "" "cc0000"
create_group "Hodca" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/hodca.lst" "" "ff1493"
create_group "News" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/news.lst" "" "4169e1"
create_group "Porn" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Categories/porn.lst" "" "ff1493"

create_group "Cloudflare" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudflare.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudflare.lst" "d58b4d"
create_group "Cloudfront" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/cloudfront.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/cloudfront.lst" "00bfff"
create_group "DigitalOcean" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/digitalocean.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/digitalocean.lst" "32cd32"
create_group "Discord" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/discord.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/discord.lst" "5865f2"
create_group "GoogleAI" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_ai.lst" "" "ff00ff"
create_group "GooglePlay" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/google_play.lst" "" "00ff00"
create_group "HDRezka" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hdrezka.lst" "" "ff4500"
create_group "Hetzner" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/hetzner.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/hetzner.lst" "8b4513"
create_group "Meta" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/meta.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/meta.lst" "0cc042"
create_group "OVH" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/ovh.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/ovh.lst" "8b0000"
create_group "Telegram" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/telegram.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/telegram.lst" "2a9ed6"
create_group "TikTok" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/tiktok.lst" "" "ff00ff"
create_group "TwitterX" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/twitter.lst" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Subnets/IPv4/twitter.lst" "1da1f2"
create_group "YouTube" "https://raw.githubusercontent.com/itdoginfo/allow-domains/refs/heads/main/Services/youtube.lst" "" "ff0033"

echo "✅ ✅ ✅ АБСОЛЮТНО НОВЫЙ СПИСОК ГОТОВ!"
echo "📁 Файл сохранен: $OUTPUT_FILE"
echo "📊 Статистика:"
echo "  Групп: $(grep -c '^groupsid' "$OUTPUT_FILE")"
echo "  Правил: $(grep -c '^name,rule' "$OUTPUT_FILE")"
echo "  Размер: $(du -h "$OUTPUT_FILE" | cut -f1)"
echo ""
echo "🔍 Первые 20 строк:"
head -20 "$OUTPUT_FILE"
echo ""
echo "📋 Полный список:"
wc -l "$OUTPUT_FILE"
echo ""
echo "❌ НИЧЕГО НЕ ПРИМЕНЕНО!"
echo "➡️ Чтобы применить: cp $OUTPUT_FILE /etc/config_from_internet_helper.mtrickle && /etc/init.d/mihomo restart"
