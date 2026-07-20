#!/bin/bash
# Waybar network on-click-right: toggle the Wi-Fi radio on/off. Waybar's
# native network module watches NetworkManager directly, so it picks up
# the resulting state change (and applies format-disabled/#network.disabled)
# without needing a manual refresh signal.
if [ "$(nmcli radio wifi)" = "enabled" ]; then
    nmcli radio wifi off
else
    nmcli radio wifi on
fi
