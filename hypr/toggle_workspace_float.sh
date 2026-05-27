#!/bin/bash
# Float all tiled windows on the current workspace, or tile all if all are already floating.

ws=$(hyprctl activeworkspace -j | jq -r '.id')
windows=$(hyprctl clients -j | jq --argjson ws "$ws" '[.[] | select(.workspace.id == $ws)]')

any_tiled=$(echo "$windows" | jq '[.[] | select(.floating == false)] | length > 0')

if [ "$any_tiled" = "true" ]; then
    echo "$windows" | jq -r '.[] | select(.floating == false) | .address' | while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done
else
    echo "$windows" | jq -r '.[].address' | while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done
fi
