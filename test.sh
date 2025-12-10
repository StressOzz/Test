    clear
    echo -e "\n===== Меню DNS over HTTPS =====\n"

    # Проверяем установлен ли пакет
    if opkg list-installed | grep -q '^https-dns-proxy '; then
        doh_status="установлен"
    else
        doh_status="не установлен"
    fi

    # Проверяем, используется ли Comss
    if [ -f /etc/config/https-dns-proxy ] && grep -q 'dns.comss.one' /etc/config/https-dns-proxy; then
        doh_comss="Comss DNS"
    else
        doh_comss="другой / нет"
    fi

    echo "DNS over HTTPS: $doh_status | $doh_comss"
    echo
    echo "1) Установить / Удалить DNS over HTTPS"
    echo "2) Настроить Comss DNS"
    echo "3) Вернуть настройки по умолчанию"
    echo "Enter) Выход в главное меню"
    echo
    read -p 'Выберите пункт: ' choice

    case "$choice" in
        1)
            if opkg list-installed | grep -q '^https-dns-proxy '; then
                echo -e "\nУдаляем DNS over HTTPS..."
                /etc/init.d/https-dns-proxy stop >/dev/null 2>&1
                /etc/init.d/https-dns-proxy disable >/dev/null 2>&1
                opkg remove https-dns-proxy luci-app-https-dns-proxy --force-removal-of-dependent-packages >/dev/null 2>&1
                rm -f /etc/config/https-dns-proxy /etc/init.d/https-dns-proxy
                echo -e "Удалено.\n"
            else
                echo -e "\nУстанавливаем DNS over HTTPS..."
                opkg update >/dev/null 2>&1
                opkg install https-dns-proxy luci-app-https-dns-proxy >/dev/null 2>&1
                echo "Установлено.\n"
            fi
            read -p "Enter для возврата..." ;;
        2)
            echo -e "\nНастраиваем Comss DNS..."
            fileDoH="/etc/config/https-dns-proxy"
            rm -f "$fileDoH"
            printf '%s\n' \
                "config main 'config'" \
                "	option canary_domains_icloud '1'" \
                "	option canary_domains_mozilla '1'" \
                "	option dnsmasq_config_update '*'" \
                "	option force_dns '1'" \
                "	list force_dns_port '53'" \
                "	list force_dns_port '853'" \
                "	list force_dns_src_interface 'lan'" \
                "	option procd_trigger_wan6 '0'" \
                "	option heartbeat_domain 'heartbeat.melmac.ca'" \
                "	option heartbeat_sleep_timeout '10'" \
                "	option heartbeat_wait_timeout '10'" \
                "	option user 'nobody'" \
                "	option group 'nogroup'" \
                "	option listen_addr '127.0.0.1'" \
                "" \
                "config https-dns-proxy" \
                "	option resolver_url 'https://dns.comss.one/dns-query'" \
                > "$fileDoH"

            /etc/init.d/https-dns-proxy enable >/dev/null 2>&1
            /etc/init.d/https-dns-proxy restart >/dev/null 2>&1
            echo -e "Comss DNS настроен.\n"
            read -p "Enter для возврата..." ;;
        3)
            echo -e "\nВозвращаем настройки по умолчанию..."
            rm -f /etc/config/https-dns-proxy
            /etc/init.d/https-dns-proxy restart >/dev/null 2>&1 || true
            echo -e "Вернул.\n"
            read -p "Enter для возврата..." ;;
        *)
            return ;;
    esac
