#!/bin/bash
# Waybar custom/mode module exec: icon-only (i3blocks-style output:
# text\ntooltip\nclass — the default custom-module format, since no
# return-type is set in config.jsonc). The class picks which of
# mode-icons-generated.css's background-images applies.
STATE_FILE="$HOME/.config/hypr/mode_state"
STATE="$(cat "$STATE_FILE" 2>/dev/null)"

case "$STATE" in
    FLOAT) class="float"; tooltip="Floating" ;;
    TILE) class="tile"; tooltip="Tile" ;;
    *) class="wide-tile"; tooltip="Wide Tile" ;;
esac

# A single space, not "" -- waybar hides a custom module outright if its
# text is truly empty.
printf ' \n%s\n%s\n' "$tooltip" "$class"
