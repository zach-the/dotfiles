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
#
# Every rescued window is logged to $RESCUE_LOG (tab-separated: time, origin
# monitor, original ws, rescue ws, window address, class). When that monitor
# comes back, restore_rescued() sends each window that is still sitting on
# its rescue workspace back to its original one. Windows that have since
# been closed or moved elsewhere by hand are dropped from the log, not
# restored. Note ws_nav.sh's compaction can renumber a rescue workspace, in
# which case its windows no longer match the log and stay where they are.

BLOCK=100
RESCUE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/workspace-rescue.log"
DEBUG_LOG="${RESCUE_LOG%.log}.debug.log"
mkdir -p "$(dirname "$RESCUE_LOG")"

dbg() { printf '%s %s\n' "$(date +%T.%N | cut -c1-12)" "$*" >> "$DEBUG_LOG"; }

# Prints the monitor's block index (eDP-1 = 0, externals by X then Y from 1).
monitor_index() {
    local monitor="$1"

    if [ "$monitor" == "eDP-1" ]; then
        echo 0
    else
        hyprctl monitors -j | jq -r '
            [.[] | select(.name != "eDP-1")] |
            sort_by(.x, .y) |
            to_entries[] |
            select(.value.name == "'"$monitor"'") |
            (.key + 1)
        '
    fi
}

assign_workspace() {
    local monitor="$1"
    local index
    index=$(monitor_index "$monitor")

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
# header) into new workspaces appended to that monitor's block. $1 is the
# monitor that was just removed; it's recorded as the origin in $RESCUE_LOG.
rescue_orphans() {
    local origin="$1"
    local mons clients workspaces
    mons=$(hyprctl monitors -j) || return
    clients=$(hyprctl clients -j) || return
    workspaces=$(hyprctl workspaces -j) || return

    # One "<monitor> <base> <old_ws> <address> <class>" line per stranded window,
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
        | "\($mon) \($base) \(.workspace.id) \(.address) \(.class)"
    ' <<< "$clients" | sort -k3,3n)

    local -A remap next
    local entry mon base old addr class
    for entry in "${stranded[@]}"; do
        read -r mon base old addr class <<< "$entry"
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
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -Is)" "$origin" "$old" "${remap[$old]}" "$addr" "$class" >> "$RESCUE_LOG"
    done
}

# Sends windows rescued from $1 back to their original workspaces, if they
# are still on the rescue workspace they were moved to. See header.
restore_rescued() {
    local monitor="$1"
    dbg "restore_rescued($monitor): log lines=$(wc -l < "$RESCUE_LOG" 2>/dev/null)"
    [ -s "$RESCUE_LOG" ] || return

    local index base clients
    index=$(monitor_index "$monitor")
    dbg "restore_rescued($monitor): index='$index'"
    [[ -z "$index" || "$index" == "null" ]] && return
    base=$(( index * BLOCK ))
    clients=$(hyprctl clients -j) || return

    local -A placed
    local -a keep=()
    local line ts origin old new addr class cur
    while IFS= read -r line; do
        IFS=$'\t' read -r ts origin old new addr class <<< "$line"
        if [ "$origin" != "$monitor" ]; then
            keep+=("$line")
            continue
        fi
        cur=$(jq -r --arg a "$addr" --arg c "$class" \
            '.[] | select(.address == $a and .class == $c) | .workspace.id' <<< "$clients")
        dbg "restore: $addr old=$old new=$new cur=${cur:-<gone>} base=$base"
        # Window closed, or moved somewhere else by hand: nothing to restore.
        [ "$cur" == "$new" ] || continue
        if (( old <= base || old > base + BLOCK )); then
            # Monitor came back at a different position; original ws isn't its
            # to own. Leave the entry for a later reconnect.
            keep+=("$line")
            continue
        fi
        hyprctl dispatch movetoworkspacesilent "$old,address:$addr"
        if [ -z "${placed[$old]}" ]; then
            placed[$old]=1
            hyprctl dispatch moveworkspacetomonitor "$old" "$monitor" 2>/dev/null
        fi
    done < "$RESCUE_LOG"

    if [ "${#keep[@]}" -gt 0 ]; then
        printf '%s\n' "${keep[@]}" > "$RESCUE_LOG"
    else
        : > "$RESCUE_LOG"
    fi
}

# Drops log entries whose window no longer exists (e.g. left over from a
# previous session, where window addresses mean something else).
prune_rescue_log() {
    [ -s "$RESCUE_LOG" ] || return
    local clients line ts origin old new addr class
    clients=$(hyprctl clients -j) || return
    local -a keep=()
    while IFS= read -r line; do
        IFS=$'\t' read -r ts origin old new addr class <<< "$line"
        if jq -e --arg a "$addr" --arg c "$class" \
            'any(.[]; .address == $a and .class == $c)' <<< "$clients" > /dev/null; then
            keep+=("$line")
        fi
    done < "$RESCUE_LOG"
    if [ "${#keep[@]}" -gt 0 ]; then
        printf '%s\n' "${keep[@]}" > "$RESCUE_LOG"
    else
        : > "$RESCUE_LOG"
    fi
}

prune_rescue_log

# Assign starting workspace for all monitors already connected at startup
hyprctl monitors -j | jq -r '.[].name' | while read -r mon; do
    assign_workspace "$mon"
done

# Listen for new monitor connections and assign on the fly
socket="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat - "UNIX-CONNECT:$socket" | while IFS= read -r line; do
    [[ "$line" == monitor* ]] && dbg "event: $line"
    if [[ "$line" == monitoradded* ]]; then
        monitor="${line#monitoradded>>}"
        sleep 0.3  # let Hyprland finish initializing the new monitor
        assign_workspace "$monitor"
        restore_rescued "$monitor"
    elif [[ "$line" == "monitorremoved>>"* ]]; then
        # lid.sh disables eDP-1 itself and relocates its windows; leave that alone.
        monitor="${line#monitorremoved>>}"
        [ "$monitor" == "eDP-1" ] && continue
        sleep 0.3  # let Hyprland finish re-homing the removed monitor's workspaces
        rescue_orphans "$monitor"
    fi
done
