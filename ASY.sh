#!/bin/sh

########################################
# НАСТРОЙКИ (ТОЛЬКО ДЛЯ ЭТОГО СКРИПТА)
########################################

ZAPRET_CONF="/etc/config/zapret"
TEST_HOST="https://rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"
TIMEOUT=5
WAIT_AFTER_APPLY=3
RESULT_FILE="/tmp/zapret_strategy_autofind"

########################################
# СТРАТЕГИИ (ВСЕ ЗДЕСЬ, СКОЛЬКО УГОДНО)
########################################

STRATEGY_v1='
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=multisplit
--dpi-desync-split-pos=1,sniext+1
--dpi-desync-split-seqovl=1
'

STRATEGY_v2='
--filter-tcp=443
--hostlist=/opt/zapret/ipset/zapret-hosts-google.txt
--dpi-desync=multisplit
--dpi-desync-split-pos=1,sniext+1
--dpi-desync-split-seqovl=1
'

########################################
# ВНУТРЕННИЙ СПИСОК
########################################

STRATEGIES="
STRATEGY_v1
STRATEGY_v2
"

########################################
# ФУНКЦИИ
########################################

apply_strategy() {
    STR_NAME="$1"
    STR_VALUE="$(eval echo \"\$$STR_NAME\")"

    echo "▶ Применяем $STR_NAME"

    # чистим старую стратегию
    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$ZAPRET_CONF"

    # записываем новую
    {
        echo "  option NFQWS_OPT '"
        echo "#AUTO $STR_NAME"
        echo "$STR_VALUE"
        echo "'"
    } >> "$ZAPRET_CONF"

    /etc/init.d/zapret restart >/dev/null 2>&1
}

check_access() {
    curl -I -s --connect-timeout "$TIMEOUT" -m "$TIMEOUT" -o /dev/null -w "%{http_code}" "$TEST_HOST"
}

########################################
# ОСНОВНОЙ ЦИКЛ
########################################

echo "=== Автоподбор стратегии zapret (автономный) ==="
echo "Тест: $TEST_HOST"
echo

for STR in $STRATEGIES; do
    apply_strategy "$STR"
    sleep "$WAIT_AFTER_APPLY"

    CODE="$(check_access)"

    if echo "$CODE" | grep -Eq '^[2-4][0-9]{2}$'; then
        echo "✅ Доступ есть (HTTP $CODE)"
        echo
        echo "Проверьте видео в браузере"
        echo "Enter — видео работает, оставить стратегию"
        echo "N — не работает, продолжить перебор"
        echo

        read -r ANSWER

        if [ -z "$ANSWER" ]; then
            echo "🏁 Готово. Рабочая стратегия: $STR"
            echo "$STR" > "$RESULT_FILE"
            exit 0
        fi

        if echo "$ANSWER" | grep -qi '^n$'; then
            echo "↩ Продолжаем перебор"
            echo
            continue
        fi
    else
        echo "❌ Нет доступа (HTTP $CODE)"
        echo
    fi
done

echo "🚫 Рабочая стратегия не найдена"
exit 1
