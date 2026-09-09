#!/usr/bin/env bash
# Assigns the starting workspace to each monitor when it connects, using
# the SAME numbering scheme as ws_nav.sh: one continuous, uncapped block
# of 100 IDs per monitor (eDP-1 -> 1-99, 1st external -> 101-199, ...).
# Only the block's first workspace is claimed here -- ws_nav.sh (hyper+L/H)
# grows the rest lazily as the user navigates. Claiming a whole fixed-size
# range up front (as this script used to, with a different block size than
# ws_nav.sh) risks grabbing a workspace ID that already legitimately
# belongs to another monitor, since eDP-1's block has no upper cap.

BLOCK=100

assign_workspace() {
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

    local ws=$(( index * BLOCK + 1 ))

    if hyprctl workspaces -j | jq -e --argjson ws "$ws" 'any(.[]; .id == $ws)' > /dev/null; then
        # Workspace already exists somewhere -- just reassign it.
        hyprctl dispatch moveworkspacetomonitor "$ws" "$monitor" 2>/dev/null
    else
        # Workspace doesn't exist yet, so moveworkspacetomonitor is a no-op.
        # dispatch workspace creates it, but always on the CURRENTLY
        # focused monitor -- so hop over to the target monitor, create it
        # there, then hop back to avoid stealing focus.
        local prev_mon
        prev_mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
        hyprctl --batch "dispatch focusmonitor $monitor ; dispatch workspace $ws ; dispatch focusmonitor $prev_mon"
    fi
}

# Assign starting workspace for all monitors already connected at startup
hyprctl monitors -j | jq -r '.[].name' | while read -r mon; do
    assign_workspace "$mon"
done

# Listen for new monitor connections and assign on the fly
socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    if [[ "$line" == monitoradded* ]]; then
        monitor="${line#monitoradded>>}"
        sleep 0.3  # let Hyprland finish initializing the new monitor
        assign_workspace "$monitor"
    fi
done
