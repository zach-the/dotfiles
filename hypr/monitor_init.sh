#!/usr/bin/env bash
# Assigns the correct 5-workspace group to each monitor when it connects.
# eDP-1 always gets 1-5; external monitors get sequential groups (6-10,
# 11-15, ...) ordered by X then Y position.

assign_workspaces() {
    local monitor="$1"
    local index

    if [ "$monitor" == "eDP-1" ]; then
        index=0
    else
        index=$(hyprctl monitors -j | jq -r '
            [.[] | select(.name != "eDP-1")] |
            sort_by(.x, .y) |
            to_entries[] |
            select(.value.name == "'"$monitor"'") |
            (.key + 1)
        ')
    fi

    [[ -z "$index" || "$index" == "null" ]] && return

    local base=$(( index * 5 ))
    local batch=""
    for i in 1 2 3 4 5; do
        local ws=$(( base + i ))
        batch+="dispatch moveworkspacetomonitor $ws $monitor ; "
    done
    # Strip trailing separator and send as one atomic batch
    hyprctl --batch "${batch% ; }"
}

# Assign workspaces for all monitors already connected at startup
hyprctl monitors -j | jq -r '.[].name' | while read -r mon; do
    assign_workspaces "$mon"
done

# Listen for new monitor connections and assign on the fly
socket="/tmp/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    if [[ "$line" == monitoradded* ]]; then
        monitor="${line#monitoradded>>}"
        sleep 0.3  # let Hyprland finish initializing the new monitor
        assign_workspaces "$monitor"
    fi
done
