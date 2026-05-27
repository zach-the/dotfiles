#!/bin/bash
# Toggle global float mode: float/tile all windows across all workspaces.
# While active, all newly opened windows also spawn floating.

STATE_FILE="$HOME/.cache/hypr/global_float_mode"
mkdir -p "$HOME/.cache/hypr"

windows=$(hyprctl clients -j)

if [ -f "$STATE_FILE" ]; then
    # Leaving float mode: tile all floating windows, remove catch-all rule
    rm "$STATE_FILE"

    echo "$windows" | jq -r '.[] | select(.floating == true) | .address' | while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done

    # config-only avoids re-probing monitors
    hyprctl reload config-only
else
    # Entering float mode: float all tiled windows, add catch-all rule
    touch "$STATE_FILE"

    echo "$windows" | jq -r '.[] | select(.floating == false) | .address' | while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done

    hyprctl keyword windowrule "match:class ^(.*)$, float 1"
fi
