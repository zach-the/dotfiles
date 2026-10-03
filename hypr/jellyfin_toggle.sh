#!/bin/bash
# Waybar custom/jellyfin on-click: toggle the jellyfin.service unit on/off.
# No sudo/pkexec needed -- /etc/polkit-1/rules.d/49-jellyfin-waybar.rules
# grants this user passwordless start/stop of exactly this unit.
if systemctl is-active --quiet jellyfin; then
    systemctl stop jellyfin
else
    systemctl start jellyfin
fi

pkill -RTMIN+14 waybar # refresh custom/jellyfin's icon immediately
