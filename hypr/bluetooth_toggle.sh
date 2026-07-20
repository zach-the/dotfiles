#!/bin/bash
# Waybar custom/bluetooth on-click-right: toggle Bluetooth power on/off.
if bluetoothctl show | grep -q "Powered: yes"; then
    bluetoothctl power off >/dev/null
else
    bluetoothctl power on >/dev/null
fi
pkill -RTMIN+9 waybar
