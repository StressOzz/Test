#!/bin/sh

get_arch_and_file() {
    ARCH=""
    CPU_MODEL=""

    # Пробуем определить архитектуру
    ARCH=$(uname -m)

    # Для ARM64 получаем модель CPU
    if [ "$ARCH" = "aarch64" ]; then
        CPU_MODEL=$(awk -F: '/model name|Processor/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//')
        if [ -n "$CPU_MODEL" ]; then
            # Формируем тег как в релизе: lowercase, дефисы, ограничиваем до 3 слов
            CPU_MODEL_TAG=$(echo "$CPU_MODEL" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | cut -d'-' -f1-3)
            ARCH_TAG="aarch64_$CPU_MODEL_TAG"
        else
            ARCH_TAG="aarch64_generic"
        fi
    else
        ARCH_TAG="$ARCH"
    fi

    echo "Архитектура устройства: $ARCH_TAG"

    # Ищем релиз на GitHub
    echo "Ищем файл релиза для '$ARCH_TAG'..."
    curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases/latest \
        | grep "browser_download_url" \
        | grep "$ARCH_TAG" \
        | cut -d'"' -f4
}

get_arch_and_file
