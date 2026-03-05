#!/bin/sh
echo "Создаем интерфейс AWG"

IF_NAME="AWG"
PROTO="amneziawg"
DEV_NAME="amneziawg0"

# Проверяем существует ли уже интерфейс
if uci show network.$IF_NAME >/dev/null 2>&1; then
    echo "Интерфейс $IF_NAME уже существует"
else
    # Создаем интерфейс
    uci set network.$IF_NAME=interface
    uci set network.$IF_NAME.proto=$PROTO
    uci set network.$IF_NAME.device=$DEV_NAME
    uci commit network
    echo "Интерфейс $IF_NAME создан"
fi

# Перезапускаем сеть
echo "Перезапускаем сеть"
/etc/init.d/network restart
