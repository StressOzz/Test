#!/bin/sh

STR_FILE="/opt/zapret_temp/str_flow.txt"
ZAPRET_CONF="/etc/config/zapret"

# 1. Собираем список стратегий (названия без #)
STRATEGIES=$(grep '^#' "$STR_FILE" | sed 's/^#//')

# 2. Выводим меню построчно
echo "Список стратегий от Flowseal:"
i=1
echo "$STRATEGIES" | while IFS= read -r line; do
    echo "$i) $line"
    i=$((i+1))
done

# 3. Спрашиваем выбор
echo -n "Выберите стратегию: "
read CHOICE

# Проверка ввода
if ! echo "$CHOICE" | grep -qE '^[0-9]+$'; then
    echo "Ошибка: нужно число"
    exit 1
fi

# 4. Находим выбранное название
SEL_NAME=$(echo "$STRATEGIES" | sed -n "${CHOICE}p")

if [ -z "$SEL_NAME" ]; then
    echo "Ошибка: такой стратегии нет"
    exit 1
fi

# 5. Вытаскиваем блок выбранной стратегии
BLOCK=$(awk -v name="$SEL_NAME" '
    $0=="#"name {flag=1; print; next}
    /^#/ && flag {exit}
    flag {print}' "$STR_FILE")

# 6. Вставляем в /etc/config/zapret
sed -i "/option NFQWS_OPT '/,\$d" "$ZAPRET_CONF"

{
    echo "    option NFQWS_OPT '"
    echo "$BLOCK"
    echo "'"
} >> "$ZAPRET_CONF"

echo "Стратегия '$SEL_NAME' успешно установлена в $ZAPRET_CONF"
