#!/bin/bash
# Print the focused window's app name, upper-cased, for waybar's
# custom/window module (shown next to the WIDE-TILE/FLOAT mode
# indicator). Reverse-DNS style class ids (e.g. wezterm's
# org.wezfurlong.wezterm) are trimmed to their last segment so this
# reads as an app name rather than a bundle id.
class="$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')"
echo "${class##*.}" | tr '[:lower:]' '[:upper:]'
