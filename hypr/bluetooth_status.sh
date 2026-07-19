#!/bin/bash
# Waybar custom/bluetooth module exec: prints "Bluetooth: Off/On/Connected".
if ! bluetoothctl show | grep -q "Powered: yes"; then
    echo "Bluetooth: Off"
elif bluetoothctl devices Connected | grep -q .; then
    echo "Bluetooth: Connected"
else
    echo "Bluetooth: On"
fi
