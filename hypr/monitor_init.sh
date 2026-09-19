#!/usr/bin/env bash
# Assigns the starting workspace to each monitor when it connects, using
# the SAME numbering scheme as ws_nav.sh: one continuous, uncapped block
# of 100 IDs per monitor (eDP-1 -> 1-99, 1st external -> 101-199, ...).
# Only the block's first workspace is claimed here -- ws_nav.sh (hyper+L/H)
# grows the rest lazily as the user navigates. Claiming a whole fixed-size
# range up front (as this script used to, with a different block size than
# ws_nav.sh) risks grabbing a workspace ID that already legitimately
# belongs to another monitor, since eDP-1's block has no upper cap.
#
# On monitor removal, Hyprland re-homes the unplugged monitor's workspaces
# (e.g. 101-104) onto a remaining monitor, but ws_nav.sh only navigates the
# monitor's own block, so those windows become unreachable. rescue_orphans()
# moves them into fresh workspaces at the top of the remaining monitor's
# block, keeping windows that shared a workspace together.

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

# Move windows stranded on workspaces outside their monitor's block (see
# header) into new workspaces appended to that monitor's block.
rescue_orphans() {
    local mons clients workspaces
    mons=$(hyprctl monitors -j) || return
    clients=$(hyprctl clients -j) || return
    workspaces=$(hyprctl workspaces -j) || return

    # One "<monitor> <base> <old_ws> <address>" line per stranded window,
    # using ws_nav.sh's monitor -> block mapping. Special workspaces
    # (id < 0) are left alone.
    local stranded
    mapfile -t stranded < <(jq -r --argjson mons "$mons" --argjson block "$BLOCK" '
        ($mons | map(select(.name != "eDP-1")) | sort_by(.x, .y) | map(.name)) as $ext
        | ($mons | map({key: (.id | tostring), value: .name}) | from_entries) as $names
        | .[]
        | select(.workspace.id > 0)
        | ($names[.monitor | tostring]) as $mon
        | select($mon != null)
        | (if $mon == "eDP-1" then 0 else (($ext | index($mon)) + 1) end * $block) as $base
        | select(.workspace.id <= $base or .workspace.id > $base + $block)
        | "\($mon) \($base) \(.workspace.id) \(.address)"
    ' <<< "$clients" | sort -k3,3n)

    local -A remap next
    local entry mon base old addr
    for entry in "${stranded[@]}"; do
        read -r mon base old addr <<< "$entry"
        if [ -z "${remap[$old]}" ]; then
            if [ -z "${next[$base]}" ]; then
                next[$base]=$(jq -r --argjson b "$base" --argjson block "$BLOCK" \
                    '[.[] | select(.id > $b and .id <= $b + $block) | .id] | max // $b' \
                    <<< "$workspaces")
            fi
            next[$base]=$(( next[$base] + 1 ))
            remap[$old]=${next[$base]}
            hyprctl dispatch movetoworkspacesilent "${remap[$old]},address:$addr"
            hyprctl dispatch moveworkspacetomonitor "${remap[$old]}" "$mon" 2>/dev/null
        else
            hyprctl dispatch movetoworkspacesilent "${remap[$old]},address:$addr"
        fi
    done
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
    elif [[ "$line" == "monitorremoved>>"* ]]; then
        # lid.sh disables eDP-1 itself and relocates its windows; leave that alone.
        [ "${line#monitorremoved>>}" == "eDP-1" ] && continue
        sleep 0.3  # let Hyprland finish re-homing the removed monitor's workspaces
        rescue_orphans
    fi
done
