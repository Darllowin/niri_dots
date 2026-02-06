#!/bin/bash

while true; do
    # 1. Формируем список устройств со статусами
    mapfile -t devices_raw < <(bluetoothctl devices)
    display_list=""
    
    # Статус адаптера
    power_status=$(bluetoothctl show | grep "Powered: yes" > /dev/null && echo "ON" || echo "OFF")
    display_list="[Питание: $power_status]\nСканировать\n---"

    for line in "${devices_raw[@]}"; do
        mac=$(echo "$line" | cut -d ' ' -f 2)
        name=$(echo "$line" | cut -d ' ' -f 3-)
        
        # Проверяем, подключено ли устройство
        if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
            display_list+="\n● $name (Подключено)"
        else
            display_list+="\n○ $name"
        fi
    done

    # 2. Вызываем fuzzel
    chosen=$(echo -e "$display_list" | fuzzel -d -p "Bluetooth > " --width 40)

    # Выход, если нажали Escape
    [ -z "$chosen" ] && exit 0

    # 3. Обработка действий
    case "$chosen" in
        "[Питание: ON]")  bluetoothctl power off ;;
        "[Питание: OFF]") bluetoothctl power on ;;
        "Сканировать")    
            # Запускаем сканирование в фоне на 5 секунд
            timeout 5s bluetoothctl scan on &
            notify-send "Bluetooth" "Сканирование запущено..."
            sleep 1 
            ;;
        *)
            # Очищаем имя от иконок и статусов для поиска MAC
            clean_name=$(echo "$chosen" | sed 's/^[●○] //' | sed 's/ (Подключено)//')
            mac=$(bluetoothctl devices | grep "$clean_name" | cut -d ' ' -f 2)
            
            if [ -n "$mac" ]; then
                if bluetoothctl info "$mac" | grep -q "Connected: yes"; then
                    bluetoothctl disconnect "$mac"
                else
                    bluetoothctl connect "$mac"
                fi
            fi
            ;;
    esac
    # Скрипт не заканчивается, а идет на новый круг while true
done
