#!/bin/sh

BACKUP_DIR="/opt/zapret_backup"
DATE_FILE="$BACKUP_DIR/created.txt"

show_menu() {
    echo "========================"
    echo "  Управление настройками"
    echo "========================"
    # Если есть файл с датой, показываем
    if [ -f "$DATE_FILE" ]; then
        CREATE_DATE=$(cat "$DATE_FILE")
        echo "Резервная копия создана: $CREATE_DATE"
    fi
    echo "------------------------"
    echo "1) Сохранить текущие настройки"
    echo "2) Восстановить из резервной копии"
    echo "3) Удалить резервную копию"
    echo "4) Восстановить настройки по умолчанию"
    echo "0) Выход"
    echo "========================"
    echo -n "Выберите действие: "
}

save_settings() {
    FILES="/etc/config/zapret \
/opt/zapret/ipset/cust1.txt \
/opt/zapret/ipset/cust2.txt \
/opt/zapret/ipset/cust3.txt \
/opt/zapret/ipset/cust4.txt \
/opt/zapret/ipset/zapret-ip-user.txt \
/opt/zapret/ipset/zapret-ip-user-ipban.txt \
/opt/zapret/ipset/zapret-ip-user-exclude.txt \
/opt/zapret/ipset/zapret-ip-exclude.txt \
/opt/zapret/ipset/zapret-hosts-user.txt \
/opt/zapret/ipset/zapret-hosts-user-ipban.txt \
/opt/zapret/ipset/zapret-hosts-user-exclude.txt.default \
/opt/zapret/ipset/zapret-hosts-user-exclude.txt-opkg \
/opt/zapret/ipset/zapret-hosts-user-exclude.txt \
/opt/zapret/ipset/zapret-hosts-google.txt \
/opt/zapret/ipset/zapret-hosts-auto.txt"

    mkdir -p "$BACKUP_DIR"
    for f in $FILES; do
        [ -f "$f" ] && cp -p "$f" "$BACKUP_DIR/"
    done
    # Сохраняем дату создания
    date '+%Y-%m-%d %H:%M:%S' > "$DATE_FILE"
    echo "Настройки сохранены в $BACKUP_DIR"
}

restore_backup() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "Резервная копия не найдена!"
        return
    fi
    for bf in "$BACKUP_DIR"/*; do
        # Пропускаем файл с датой
        [ "$(basename "$bf")" = "created.txt" ] && continue
        case "$(basename "$bf")" in
            zapret) orig="/etc/config/zapret" ;;
            *) orig="/opt/zapret/ipset/$(basename "$bf")" ;;
        esac
        cp -p "$bf" "$orig"
    done
    echo "Настройки восстановлены из резервной копии"
    ZAPRET_RESTART
}

delete_backup() {
    if [ -d "$BACKUP_DIR" ]; then
        rm -rf "$BACKUP_DIR"
        echo "Резервная копия удалена"
    else
        echo "Резервная копия не найдена"
    fi
}

restore_default() {
    echo "Восстановление настроек по умолчанию..."
    /etc/init.d/zapret enable
    /etc/init.d/zapret stop
    rm -f /etc/config/zapret
    cp /rom/etc/config/zapret /etc/config/zapret 2>/dev/null || echo "Файл по умолчанию не найден"
    ZAPRET_RESTART
    echo "Настройки по умолчанию восстановлены"
}

while true; do
    show_menu
    read choice
    case $choice in
        1) save_settings ;;
        2) restore_backup ;;
        3) delete_backup ;;
        4) restore_default ;;
        0) break ;;
        *) echo "Неверный выбор!" ;;
    esac
    echo
done
