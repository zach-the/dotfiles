#!/bin/bash
# Waybar custom/bluetooth module exec: icon-only (i3blocks-style output:
# text\ntooltip\nclass — the default custom-module format, since no
# return-type is set in config.jsonc). The class picks which of
# bluetooth-icons-generated.css's background-images applies; the former
# "Bluetooth: Off/On/Connected" text now lives in the tooltip instead.
if ! bluetoothctl show | grep -q "Powered: yes"; then
    tooltip="Bluetooth: Off"; class="off"
elif bluetoothctl devices Connected | grep -q .; then
    tooltip="Bluetooth: Connected"; class="connected"
else
    tooltip="Bluetooth: On"; class="on"
fi
# A single space, not "" -- waybar hides a custom module outright if its
# text is truly empty.
printf ' \n%s\n%s\n' "$tooltip" "$class"
