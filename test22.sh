chose_endpoint() {

    echo -e "${CYAN}Получаем список Endpoint...${NC}"

    EP_LIST="$(curl -fsSL https://raw.githubusercontent.com/STR97/STRUGOV/refs/heads/main/end%20point)" || {
        echo -e "${RED}Не удалось загрузить список Endpoint${NC}"
        exit 1
    }

    echo
    echo -e "${MAGENTA}Выберите страну:${NC}"

    # 1. Сначала находим максимальную длину страны
    MAX_LEN=0
    while IFS='|' read -r name ep; do
        case "$name" in
            *Текущая*) country="Россия" ;;
            *Нидерланд*) country="Нидерланды" ;;
            *Америка*) country="Америка" ;;
            *Сингапур*) country="Сингапур" ;;
            *Латвия*) country="Латвия" ;;
            *Герман*) country="Германия" ;;
            *Литва*) country="Литва" ;;
            *Финлянд*) country="Финляндия" ;;
            *) country="$name" ;;
        esac
        len=${#country}
        [ "$len" -gt "$MAX_LEN" ] && MAX_LEN=$len
    done <<EOF
$EP_LIST
EOF

    # 2. Выводим меню с ровными колонками и ping
    i=1
    while IFS='|' read -r name ep; do
        case "$name" in
            *Текущая*) country="Россия" ;;
            *Нидерланд*) country="Нидерланды" ;;
            *Америка*) country="Америка" ;;
            *Сингапур*) country="Сингапур" ;;
            *Латвия*) country="Латвия" ;;
            *Герман*) country="Германия" ;;
            *Литва*) country="Литва" ;;
            *Финлянд*) country="Финляндия" ;;
            *) country="$name" ;;
        esac

        host="${ep%%:*}"
        ping_ms="$(ping -c1 -W1 "$host" 2>/dev/null | awk -F'/' 'END{print $5}')"
        [ -z "$ping_ms" ] && ping_ms="TimeOut"

        # Выравниваем страну по MAX_LEN, номера по 2 знака
        printf "%2s) %-*s | %s ms\n" "$i" "$MAX_LEN" "$country" "$ping_ms"

        i=$((i+1))
    done <<EOF
$EP_LIST
EOF

    echo
    printf "${CYAN}Введите номер:${NC} "
    read num

    ENDPOINT="$(echo "$EP_LIST" | sed -n "${num}p" | cut -d'|' -f2)"

    if [ -z "$ENDPOINT" ]; then
        ENDPOINT="engage.cloudflareclient.com:4500"
    fi

    echo
}
