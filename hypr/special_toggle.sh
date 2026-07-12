#!/bin/bash
# Send the active window to/from the special workspace (scratchpad).
#
# Windows sent TO special always float (special should only ever hold
# floating windows). Windows sent back FROM special are un-floated if
# we're currently in normal/tile mode, so they rejoin the tiled layout
# instead of landing as a stray floating window.

MODE_STATE_FILE="$HOME/.config/hypr/mode_state"

win=$(hyprctl activewindow -j)
ws=$(echo "$win" | jq -r ".workspace.name")
addr=$(echo "$win" | jq -r ".address")
floating=$(echo "$win" | jq -r ".floating")
mode=$(cat "$MODE_STATE_FILE" 2>/dev/null)

if [[ "$ws" == special* ]]; then
    hyprctl dispatch movetoworkspacesilent e+0
    if [[ "$mode" != "FLOAT" && "$floating" == "true" ]]; then
        hyprctl dispatch togglefloating "address:$addr"
    fi
else
    hyprctl dispatch movetoworkspacesilent special
    if [[ "$floating" == "false" ]]; then
        hyprctl dispatch togglefloating "address:$addr"
    fi
fi
