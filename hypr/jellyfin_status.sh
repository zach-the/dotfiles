#!/bin/bash
# Waybar custom/jellyfin module exec: icon-only (i3blocks-style output:
# text\ntooltip\nclass — the default custom-module format, since no
# return-type is set in config.jsonc). The class picks which of
# jellyfin-icons-generated.css's background-images applies.
if systemctl is-active --quiet jellyfin; then
    tooltip="Jellyfin: Running (click to stop)"; class="on"
else
    tooltip="Jellyfin: Stopped (click to start)"; class="off"
fi
# A single space, not "" -- waybar hides a custom module outright if its
# text is truly empty.
printf ' \n%s\n%s\n' "$tooltip" "$class"
