#!/bin/sh

FILES=$(find /root -maxdepth 1 -type f -name "*.apk" | sort)

[ -z "$FILES" ] && {
    echo "APK-файлы не найдены."
    exit 1
}

i=1
for f in $FILES; do
    eval "APK_$i=\"$f\""
    echo "$i - $(basename "$f")"
    i=$((i + 1))
done

echo
printf "Введите порядок установки (например: 2 1 3): "
read ORDER

echo "Обновляем список пакетов..."
apk update || exit 1

echo
for n in $ORDER; do
    eval "APK=\$APK_$n"

    if [ -f "$APK" ]; then
        echo "Устанавливаем $(basename "$APK")..."
        apk add --allow-untrusted "$APK" || {
            echo "Ошибка установки $(basename "$APK")"
            exit 1
        }
    else
        echo "Неверный номер: $n"
    fi
done

echo
echo "Установка завершена."
