#!/bin/sh

ZAPRET_CONF="/etc/config/zapret"
STR_URL="https://raw.githubusercontent.com/StressOzz/Test/refs/heads/main/ListStrYou"
TMP_LIST="/tmp/zapret_yt_list.txt"
SAVED_STR="/opt/StrYou"

TEST_HOST="https://rr1---sn-gvnuxaxjvh-jx3z.googlevideo.com"
TIMEOUT=5
WAIT_AFTER_APPLY=3

# Проверяем, есть ли сохранённая стратегия
if [ -f "$SAVED_STR" ]; then
    STRATEGY_NAME=$(head -n1 "$SAVED_STR")
    echo "[ZAPRET] Используем сохранённую стратегию: $STRATEGY_NAME"
    exit 0  # или можно сразу применить, если нужно
fi

# Скачать список стратегий
curl -fsSL "$STR_URL" -o "$TMP_LIST" || { echo "Не удалось скачать список"; exit 1; }

TOTAL=$(grep -c '^YT[0-9]\+' "$TMP_LIST")
echo "[ZAPRET] Найдено стратегий: $TOTAL"
echo

CURRENT_NAME=""
CURRENT_BODY=""
COUNT=0

progress_bar() {
    done="$1"
    total="$2"
    BAR_LEN=15
    FILLED=$(( BAR_LEN * done / total ))
    EMPTY=$(( BAR_LEN - FILLED ))
    BAR=$(printf '■%.0s' $(seq 1 $FILLED))
    BAR="$BAR$(printf '□%.0s' $(seq 1 $EMPTY))"
    echo "[$BAR] $done/$total"
}

apply_strategy() {
    NAME="$1"
    BODY="$2"
    sed -i "/^[[:space:]]*option NFQWS_OPT '/,\$d" "$ZAPRET_CONF"
    {
        echo "  option NFQWS_OPT '"
        echo "#AUTO $NAME"
        printf "%b\n" "$BODY"
        echo "'"
    } >> "$ZAPRET_CONF"
    /etc/init.d/zapret restart >/dev/null 2>&1
}

check_access() {
    curl -I -s --connect-timeout "$TIMEOUT" -m "$TIMEOUT" -o /dev/null -w "%{http_code}" "$TEST_HOST"
}

while IFS= read -r LINE || [ -n "$LINE" ]; do
    if echo "$LINE" | grep -q '^YT[0-9]\+'; then
        if [ -n "$CURRENT_NAME" ]; then
            COUNT=$((COUNT + 1))
            echo "[ZAPRET] ▶ Применяем стратегию: $CURRENT_NAME ($COUNT/$TOTAL)"
            progress_bar "$COUNT" "$TOTAL"
            apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"
            sleep "$WAIT_AFTER_APPLY"

            CODE=$(check_access)
            if echo "$CODE" | grep -Eq '^[2-4][0-9]{2}$'; then
                echo "✅ Доступ есть (HTTP $CODE)"
                echo "Проверьте видео в браузере"
                echo "Enter — оставить стратегию, N — продолжить перебор"
                read -r ANSWER </dev/tty
                if [ -z "$ANSWER" ]; then
                    echo "$CURRENT_NAME" > "$SAVED_STR"
                    echo "🏁 Рабочая стратегия: $CURRENT_NAME сохранена в $SAVED_STR"
                    exit 0
                fi
            else
                echo "❌ Нет доступа (HTTP $CODE)"
            fi
        fi
        CURRENT_NAME="$LINE"
        CURRENT_BODY=""
    else
        [ -n "$LINE" ] && CURRENT_BODY="${CURRENT_BODY}${LINE}\n"
    fi
done < "$TMP_LIST"

# Последняя стратегия
if [ -n "$CURRENT_NAME" ]; then
    COUNT=$((COUNT + 1))
    echo "[ZAPRET] ▶ Применяем стратегию: $CURRENT_NAME ($COUNT/$TOTAL)"
    progress_bar "$COUNT" "$TOTAL"
    apply_strategy "$CURRENT_NAME" "$CURRENT_BODY"
    sleep "$WAIT_AFTER_APPLY"

    CODE=$(check_access)
    if echo "$CODE" | grep -Eq '^[2-4][0-9]{2}$'; then
        echo "✅ Доступ есть (HTTP $CODE)"
        echo "Проверьте видео в браузере"
        echo "Enter — оставить стратегию, N — продолжить перебор"
        read -r ANSWER </dev/tty
        if [ -z "$ANSWER" ]; then
            echo "$CURRENT_NAME" > "$SAVED_STR"
            echo "🏁 Рабочая стратегия: $CURRENT_NAME сохранена в $SAVED_STR"
            exit 0
        fi
    else
        echo "❌ Нет доступа (HTTP $CODE)"
    fi
fi

echo "🚫 Рабочая стратегия не найдена"
exit 1
