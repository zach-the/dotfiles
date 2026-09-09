#!/bin/bash
# Waybar custom/battery on-click: toggle whether the percentage text shows
# next to the icon. Presence of the state file means "show it".
STATE_FILE="$HOME/.config/hypr/battery_show_pct"

if [ -f "$STATE_FILE" ]; then
    rm -f "$STATE_FILE"
else
    touch "$STATE_FILE"
fi

pkill -RTMIN+14 waybar
