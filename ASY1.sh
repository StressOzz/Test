#!/bin/sh

########################################
# НАСТРОЙКИ
########################################

ZAPRET_CONF="/etc/config/zapret"
STR_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/ListStrYou"
TMP_LIST="/tmp/zapret_yt_list.txt"

TEST_HOST="https://rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"
TIMEOUT=5
WAIT_AFTER_APPLY=3
RESULT_FILE="/tmp/zapret_strategy_found"

########################################
# ПРОВЕРКИ
########################################

command -v curl >/dev/null || { echo "curl не найден"; exit 1; }
[ -w "$ZAPRET_CONF" ] || { echo "Нет доступа к $ZAPRET_CONF"; exit 1; }

########################################
# ЗАГРУЗКА СПИСКА
########################################

echo "▶ Загружаем список стратегий"
curl -fsSL "$STR_URL" -o "$TMP_LIST" || { echo "Не удалось скачать список"; exit 1; }

########################################
# ФУНКЦИИ
########################################

apply_strategy() {
    NAME="$1"
    BODY="$2"

    echo "▶ Применяем стратегию $NAME"

    # удаляем старую стратегию
    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$ZAPRET_CONF"

    # пишем новую
    {
        echo "  option NFQWS_OPT '"
        echo "#AUTO $NAME"
        printf "%s\n" "$BODY"
        echo "'"
    } >> "$ZAPRET_CONF"

    /etc/init.d/zapret restart >/dev/null 2>&1
}

check_access() {
    curl -I -s --connect-timeout "$TIMEOUT" -m "$TIMEOUT" -o /dev/null -w "%{http_code}" "$TEST_HOST"
}

########################################
# ПАРСИНГ И ПЕРЕБОР
########################################

echo "=== Автоподбор стратегий YouTube ==="
echo "Источник: $STR_URL"
echo

CURRENT_NAME=""
CURRENT_BODY=""

while IFS= read -r LINE || [ -n "$LINE" ]; do
    if echo "$LINE" | grep -q '^YT[0-9]\+'; then
        # если это не первая стратегия — обрабатываем предыдущую
        if [ -n "$CURRENT_NAME" ]; then
            apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"
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
                    echo "🏁 Найдена рабочая стратегия: $CURRENT_NAME"
                    echo "$CURRENT_NAME" > "$RESULT_FILE"
                    exit 0
                fi
            else
                echo "❌ Нет доступа (HTTP $CODE)"
                echo
            fi
        fi

        # начинаем новую стратегию
        CURRENT_NAME="$LINE"
        CURRENT_BODY=""
    else
        # строки стратегии
        [ -n "$LINE" ] && CURRENT_BODY="${CURRENT_BODY}${LINE}\n"
    fi
done < "$TMP_LIST"

########################################
# ПОСЛЕДНЯЯ СТРАТЕГИЯ
########################################

if [ -n "$CURRENT_NAME" ]; then
    apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"
    sleep "$WAIT_AFTER_APPLY"

    CODE="$(check_access)"

    if echo "$CODE" | grep -Eq '^[2-4][0-9]{2}$'; then
        echo "✅ Доступ есть (HTTP $CODE)"
        echo
        echo "Проверьте видео в браузере"
        echo "Enter — видео работает, оставить стратегию"
        echo "N — не работает, выход"
        echo

        read -r ANSWER

        if [ -z "$ANSWER" ]; then
            echo "🏁 Найдена рабочая стратегия: $CURRENT_NAME"
            echo "$CURRENT_NAME" > "$RESULT_FILE"
            exit 0
        fi
    fi
fi

echo "🚫 Рабочая стратегия не найдена"
exit 1
