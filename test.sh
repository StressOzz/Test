#!/bin/sh

get_arch_and_file() {
    # Определяем архитектуру устройства
    ARCH=""
    CPU_MODEL=""

    # Пробуем lscpu, если есть
    if command -v lscpu >/dev/null 2>&1; then
        ARCH=$(lscpu | grep '^Architecture:' | awk '{print $2}')
        CPU_MODEL=$(lscpu | grep 'Model name:' | sed 's/Model name:[ \t]*//')
    fi

    # Если lscpu нет, читаем /proc/cpuinfo
    if [ -z "$ARCH" ]; then
        ARCH=$(uname -m)
        CPU_MODEL=$(awk -F: '/model name|Processor/ {print $2; exit}' /proc/cpuinfo | sed 's/^[ \t]*//')
    fi

    # Составляем тег архитектуры как в скрипте Zapret
    case "$ARCH" in
        x86_64) ARCH_TAG="x86_64" ;;
        i*86) ARCH_TAG="i386" ;;
        armv7*) ARCH_TAG="armv7" ;;
        aarch64) 
            # добавляем модель CPU, если есть
            if [ -n "$CPU_MODEL" ]; then
                CPU_MODEL_TAG=$(echo "$CPU_MODEL" | tr '[:upper:]' '[:lower:]' | sed 's/ /-/g' | cut -d'-' -f1-3)
                ARCH_TAG="aarch64_$CPU_MODEL_TAG"
            else
                ARCH_TAG="aarch64"
            fi
            ;;
        *) ARCH_TAG="unknown" ;;
    esac

    echo "Архитектура устройства: $ARCH_TAG"

    # Ищем файл релиза, который содержит ARCH_TAG
    echo "Ищем файл релиза, содержащий '$ARCH_TAG'..."
    curl -s https://api.github.com/repos/remittor/zapret-openwrt/releases/latest \
        | grep "browser_download_url" \
        | grep "$ARCH_TAG" \
        | cut -d'"' -f4
}

# Запускаем
get_arch_and_file
