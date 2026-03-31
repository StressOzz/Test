#!/bin/sh

msg() {
    echo "$1"
}

check_dns_ok() {
    # Проверка peerdns (использование DNS провайдера)
    if [ "$(uci get network.wan.peerdns 2>/dev/null)" = "1" ]; then
        msg "❌ Используется DNS провайдера (peerdns=1)"
        return 1
    fi

    # Получаем список DNS
    DNS_LIST="$(grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' /tmp/resolv.conf.d/resolv.conf.auto 2>/dev/null)"
    [ -z "$DNS_LIST" ] && DNS_LIST="$(uci get network.wan.dns 2>/dev/null)"

    if [ -z "$DNS_LIST" ]; then
        msg "❌ DNS сервера не найдены"
        return 1
    fi

    # Проверка на нормальные DNS
    for dns in $DNS_LIST; do
        case "$dns" in
            1.1.1.1|1.0.0.1|8.8.8.8|8.8.4.4|9.9.9.9|149.112.112.112)
                msg "✅ Используется нормальный DNS: $dns"
                # Живой тест DNS через nslookup
                if nslookup google.com >/dev/null 2>&1; then
                    return 0
                else
                    msg "❌ DNS не отвечает (nslookup не прошёл)"
                    return 1
                fi
            ;;
        esac
    done

    # Если сюда дошли — нормального DNS нет
    msg "❌ Не найден нормальный DNS (1.1.1.1, 8.8.8.8 и т.д.)"
    return 1
}

# Запуск
if check_dns_ok; then
    msg "✅ DNS нормальный, можно запускать стратегии YouTube"
    exit 0
else
    msg "⚠️ Сначала поменяй DNS на 1.1.1.1, 8.8.8.8 или другой нормальный"
    exit 1
fi
