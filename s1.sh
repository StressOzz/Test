#!/bin/sh
# mihomo-groups-generator.sh - ТОЧНЫЙ формат твоего mtrickle!
# Сохраняет ВСЕ группы из itdoginfo в /root/mihomo-new-groups.mtrickle
# Формат: groupsidXXXX,nameГруппа,colordefault,interfaceMihomo,... + ruleXXXX,...

OUTPUT_FILE="/root/mihomo-new-groups.mtrickle"
TMP_DIR="/tmp/mihomo-tmp"
mkdir -p "$TMP_DIR"

# Генератор ID (8 hex символов как в оригинале)
gen_id() {
    openssl rand -hex 4 2>/dev/null | cut -c1-8 || printf "%08x" $((RANDOM % 0x100000000))
}

# Очистка
> "$OUTPUT_FILE"

echo "🎯 Генерация ТОЧНОГО формата mtrickle... $(date)"

# Функция создания группы (ТОЧНО как оригинал)
create_group() {
    local group_name="$1"
    local domains_url="$2"
    local ips_url="$3"
    local color="$4"
    
    # Заголовок группы (ТОЧНО формат!)
    local group_id=$(gen_id)
    echo "groupsid${group_id},name${group_name},color${color},interfaceMihomo,enabletrue,rulesenabletrue," >> "$OUTPUT_FILE"
    
    # Домены (typenamespace как в твоих YouTube/Telegram)
    if [ -n "$domains_url" ]; then
        wget -T 10 -q -O - "$domains_url" 2>/dev/null | \
        grep -v '^$' | grep -v '^#' | sed 's/[[:space:]]*$//' | \
        while read domain; do
            [ -n "$domain" ] || continue
            local rule_id=$(gen_id)
            echo "id${rule_id},name,rule${domain},typenamespace,enabletrue," >> "$OUTPUT_FILE"
        done
    fi
    
    # IP (typesubnet как в Cloudflare)
    if [ -n "$ips_url" ]; then
        wget -T 10 -q -O - "$ips_url" 2>/dev/null | \
        grep -E '^[0-9]' | grep -v '^$' | sed 's/[[:space:]]*$//' | \
        while read ipcidr; do
            [ -n "$ipcid
