#!/bin/sh

HOST="raw.githubusercontent.com"
URL="https://raw.githubusercontent.com/StressOzz/Zapret-Manager/main/Zapret-Manager.sh"
LOG="/tmp/github_test.log"

echo "=== GitHub Raw Test ===" | tee $LOG
echo "Дата: $(date)" | tee -a $LOG
echo | tee -a $LOG

test_access() {
    NAME="$1"

    echo "===== $NAME =====" | tee -a $LOG

    IP=$(nslookup $HOST 2>/dev/null | awk '/Address: /{print $2}' | head -1)
    echo "DNS IP: $IP" | tee -a $LOG

    START=$(date +%s)

    if wget -4 -q --timeout=10 --spider "$URL"; then
        RESULT="OK"
    else
        RESULT="FAIL"
    fi

    END=$(date +%s)
    TIME=$((END-START))

    echo "IPv4 HTTPS: $RESULT (${TIME}s)" | tee -a $LOG

    if curl -4 -k -I --connect-timeout 5 "$URL" >/dev/null 2>&1; then
        echo "curl IPv4: OK" | tee -a $LOG
    else
        echo "curl IPv4: FAIL" | tee -a $LOG
    fi

    echo | tee -a $LOG
}


echo "1) Проверка без изменений"
test_access "ORIGINAL"


echo "2) Добавление hosts записи"

git="githubusercontent.com"
grep -q "raw.$git" /etc/hosts || {
printf "#$git\n185.199.109.133 raw.$git release-assets.$git\n185.199.108.133 private-user-images.$git gist.$git avatars.$git\n" >> /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null
}

sleep 2

test_access "WITH HOSTS"


echo "3) Удаление hosts записи"

sed -i '/#githubusercontent.com/,+2d' /etc/hosts
/etc/init.d/dnsmasq restart 2>/dev/null

sleep 2

test_access "AFTER REMOVE"


echo "=== ИТОГ ==="

grep "IPv4 HTTPS" $LOG

echo

ORIG=$(grep -A3 "ORIGINAL" $LOG | grep "IPv4 HTTPS")
HOST=$(grep -A3 "WITH HOSTS" $LOG | grep "IPv4 HTTPS")

if echo "$ORIG" | grep -q OK && echo "$HOST" | grep -q OK; then
    echo "Вывод: hosts не нужен, доступ к GitHub работает."
elif echo "$ORIG" | grep -q FAIL && echo "$HOST" | grep -q OK; then
    echo "Вывод: запись /etc/hosts помогает."
elif echo "$ORIG" | grep -q FAIL && echo "$HOST" | grep -q FAIL; then
    echo "Вывод: проблема не в DNS, GitHub недоступен по HTTPS."
else
    echo "Вывод: требуется дополнительная проверка."
fi

echo
echo "Лог сохранён: $LOG"

EOF
