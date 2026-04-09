#!/usr/bin/env bash
# Usage: ./ws_nav.sh [next|prev|1|2|3|4|5] [move]
#
# Workspace layout: 5 workspaces per monitor
#   eDP-1 (always index 0): workspaces  1-5
#   1st external (by X,Y):  workspaces  6-10
#   2nd external:           workspaces 11-15
#   3rd external:           workspaces 16-20
#   ...and so on

action=$1
move=$2

active_ws_info=$(hyprctl activeworkspace -j)
current_mon_name=$(echo "$active_ws_info" | jq -r '.monitor')
current_ws=$(echo "$active_ws_info" | jq -r '.id')

# eDP-1 is always index 0; external monitors ordered by X then Y position
if [ "$current_mon_name" == "eDP-1" ]; then
    mon_index=0
else
    mon_index=$(hyprctl monitors -j | jq -r '
        [.[] | select(.name != "eDP-1")] |
        sort_by(.x, .y) |
        to_entries[] |
        select(.value.name == "'"$current_mon_name"'") |
        (.key + 1)
    ')
fi

base=$(( mon_index * 5 ))

# Position within this monitor's 5-workspace group (1-5)
sub=$(( current_ws - base ))
if (( sub < 1 || sub > 5 )); then
    sub=1
fi

if [ "$action" == "next" ]; then
    sub=$(( (sub % 5) + 1 ))
elif [ "$action" == "prev" ]; then
    sub=$(( sub - 1 ))
    if (( sub < 1 )); then sub=5; fi
elif [[ "$action" =~ ^[1-5]$ ]]; then
    sub=$action
fi

target=$(( base + sub ))

if [ "$move" == "move" ]; then
    hyprctl dispatch movetoworkspace "$target"
else
    hyprctl --batch "dispatch moveworkspacetomonitor $target current ; dispatch workspace $target"
fi
