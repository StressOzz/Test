#!/bin/sh
GREEN="\033[1;32m"
RED="\033[1;31m"
CYAN="\033[1;36m"
MAGENTA="\033[1;35m"
NC="\033[0m"

# ФАЙЛЫ
ZAPRET_CFG="/etc/config/zapret"
EXCLUDE_FILE="/opt/zapret/ipset/zapret-hosts-user-exclude.txt"
EXCLUDE_URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/refs/heads/main/zapret-hosts-user-exclude.txt"

# --- МЕНЮ ---
echo -e "${MAGENTA}Выберите стратегию:${NC}"
echo "1) v1"
echo "2) v2"
echo "3) v3"
echo "4) v4"
echo
read -p "Ваш выбор: " choice

case "$choice" in
    1) version="v1" ;;
    2) version="v2" ;;
    3) version="v3" ;;
    4) version="v4" ;;
    *) echo -e "${RED}Неверный выбор.${NC}"; exit 1 ;;
esac

echo -e "${MAGENTA}Устанавливаем стратегию ${version}${NC}"
echo -e "${CYAN}Меняем стратегию...${NC}"

# --- ОЧИСТКА NFQWS_OPT ---
sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$ZAPRET_CFG"

# --- ФУНКЦИИ СТРАТЕГИЙ ---
strategy_v1() {
cat <<EOF
--filter-tcp=443
--hostlist-exclude=${EXCLUDE_FILE}
--dpi-desync=fake,multidisorder
--dpi-desync-split-seqovl=681
--dpi-desync-split-pos=1
--dpi-desync-fooling=badseq
--dpi-desync-badseq-increment=10000000
--dpi-desync-repeats=2
--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--dpi-desync-fake-tls-mod=rnd,dupsid,sni=fonts.google.com
--new
--filter-udp=443
--hostlist-exclude=${EXCLUDE_FILE}
--dpi-desync=fake
--dpi-desync-repeats=4
--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
EOF
}

strategy_v2() {
cat <<EOF
--filter-tcp=443
--hostlist-exclude=${EXCLUDE_FILE}
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
EOF
}

strategy_v3() {
cat <<EOF
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--ip-id=zero
--dpi-desync=multisplit
--dpi-desync-split-seqovl=681
--dpi-desync-split-pos=1
--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--new
--filter-tcp=443
--hostlist-exclude=${EXCLUDE_FILE}
--dpi-desync=fake,fakeddisorder
--dpi-desync-split-pos=10,midsld
--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_t2_ru.bin
--dpi-desync-fake-tls-mod=rnd,dupsid,sni=m.ok.ru
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
EOF
}

strategy_v4() {
cat <<EOF
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=fake,multisplit
--dpi-desync-split-pos=2,sld
--dpi-desync-fake-tls=0x0F0F0F0F
--dpi-desync-fake-tls=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--dpi-desync-fake-tls-mod=rnd,dupsid,sni=google.com
--dpi-desync-split-seqovl=2108
--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/tls_clienthello_www_google_com.bin
--dpi-desync-fooling=badseq
--new
--filter-tcp=443
--hostlist-exclude=${EXCLUDE_FILE}
--dpi-desync-any-protocol=1
--dpi-desync-cutoff=n5
--dpi-desync=multisplit
--dpi-desync-split-seqovl=582
--dpi-desync-split-pos=1
--dpi-desync-split-seqovl-pattern=/opt/zapret/files/fake/4pda.bin
--new
--filter-udp=443
--hostlist-exclude=${EXCLUDE_FILE}
--dpi-desync=fake
--dpi-desync-repeats=4
--dpi-desync-fake-quic=/opt/zapret/files/fake/quic_initial_www_google_com.bin
EOF
}

# --- ЗАПИСЬ В КОНФИГ ---
{
echo "  option NFQWS_OPT '"
echo "#${version} УДАЛИТЕ ЭТУ СТРОЧКУ, ЕСЛИ ИЗМЕНЯЕТЕ СТРАТЕГИЮ !!!"
strategy_${version}
echo "'"
} >> "$ZAPRET_CFG"

# --- ОБНОВЛЕНИЕ ИСКЛЮЧЕНИЙ ---
echo -e "${CYAN}Обновляем исключения...${NC}"
rm -f "$EXCLUDE_FILE"
curl -fsSL "$EXCLUDE_URL" -o "$EXCLUDE_FILE" || echo -e "${RED}Не удалось загрузить exclude файл${NC}"

# --- ДОГРУЗКА BIN (если нужны) ---
if [ "$version" = "v3" ]; then
  curl -sLo /opt/zapret/files/fake/tls_clienthello_t2_ru.bin https://github.com/StressOzz/Zapret-Manager/raw/refs/heads/main/tls_clienthello_t2_ru.bin
fi

if [ "$version" = "v4" ]; then
  curl -sLo /opt/zapret/files/fake/4pda.bin https://github.com/StressOzz/Zapret-Manager/raw/refs/heads/main/4pda.bin
fi

# --- HOSTS ---
echo -e "${CYAN}Обновляем /etc/hosts${NC}"
cat <<EOF | grep -Fxv -f /etc/hosts 2>/dev/null >> /etc/hosts
130.255.77.28 ntc.party
57.144.222.34 instagram.com www.instagram.com
173.245.58.219 rutor.info d.rutor.info
193.46.255.29 rutor.info
157.240.9.174 instagram.com www.instagram.com
EOF

/etc/init.d/dnsmasq restart >/dev/null 2>&1

# --- ПРИМЕНЕНИЕ ---
echo -e "${CYAN}Применяем конфигурацию...${NC}"
chmod +x /opt/zapret/sync_config.sh
/opt/zapret/sync_config.sh
/etc/init.d/zapret restart >/dev/null 2>&1

echo -e "${GREEN}Стратегия ${version} успешно установлена!${NC}"
