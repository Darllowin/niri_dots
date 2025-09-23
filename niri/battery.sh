#!/bin/bash
# Low battery notifier — notify only at 20% and 5%

iDIR="$HOME/.config/mako/icons"

# Kill already running instances
already_running="$(ps -fC 'grep' -N | grep 'battery.sh' | wc -l)"
if [[ $already_running -gt 1 ]]; then
    pkill -f --older 1 'battery.sh'
fi

# Переменные для отслеживания, чтобы не дублировать уведомления
notified_20=false
notified_5=false

while true; do
    battery_status="$(cat /sys/class/power_supply/BAT0/status 2>/dev/null)"
    battery_charge="$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null)"

    # Выход, если данные не получены
    if [[ -z "$battery_status" || -z "$battery_charge" ]]; then
        echo "Battery info not available"
        exit 1
    fi

    if [[ $battery_status == 'Discharging' ]]; then
        if [[ $battery_charge -eq 20 && $notified_20 == false ]]; then
            notify-send --icon="$iDIR/battery-low.png" --urgency=critical "Battery Low" "Charge is at 20%"
            notified_20=true
        elif [[ $battery_charge -eq 5 && $notified_5 == false ]]; then
            notify-send --icon="$iDIR/battery-low.png" --urgency=critical "‼️ Battery Danger!" "Connect to power IMMEDIATELY (5%)"
            notified_5=true
        fi
    else
        # Сброс уведомлений, если батарея заряжается
        notified_20=false
        notified_5=false
    fi

    sleep 60
done
