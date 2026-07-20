#!/bin/bash
# Waybar custom/bluetooth module exec: prints "Bluetooth: Off/On/Connected"
# plus a CSS class (i3blocks-style output: text\ntooltip\nclass — the
# default custom-module format, since no return-type is set in
# config.jsonc) so style.css can grey out the "off" state.
if ! bluetoothctl show | grep -q "Powered: yes"; then
    text="Bluetooth: Off"; class="off"
elif bluetoothctl devices Connected | grep -q .; then
    text="Bluetooth: Connected"; class="connected"
else
    text="Bluetooth: On"; class="on"
fi
printf '%s\n\n%s\n' "$text" "$class"
