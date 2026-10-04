#!/usr/bin/env bash
# Usage: ./ws_insert_right.sh
#
# Inserts a new empty workspace immediately to the right of the current one,
# on the current monitor, and switches focus to it. Every workspace already
# at or past that point (within this monitor's block -- see ws_nav.sh for
# the block layout) shifts one position further right to make room; the
# current workspace itself is left untouched.

BLOCK=100
RESCUE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/workspace-rescue.log"

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

base=$(( mon_index * BLOCK ))
insert_id=$(( current_ws + 1 ))

# Shift every workspace at or past the insert point one position further
# right. Process highest id first so no move ever lands on a still-occupied
# slot (the top of the block always lands on a genuinely empty id).
mapfile -t shift_ids < <(hyprctl workspaces -j | jq -r '
    [.[] | select(.id >= '"$insert_id"' and .id <= '"$((base + BLOCK))"')] |
    sort_by(-.id) | .[].id
')

for id in "${shift_ids[@]}"; do
    new_id=$(( id + 1 ))
    addrs=$(hyprctl clients -j | jq -r '.[] | select(.workspace.id == '"$id"') | .address')
    for addr in $addrs; do
        hyprctl dispatch movetoworkspacesilent "$new_id,address:$addr"
        # Keep the rescue log pointing at each window's new workspace,
        # otherwise it no longer matches when a monitor comes back.
        if [ -s "$RESCUE_LOG" ]; then
            awk -F'\t' -v OFS='\t' -v a="$addr" -v old="$id" -v new="$new_id" \
                '$5 == a && $4 == old { $4 = new } 1' "$RESCUE_LOG" > "$RESCUE_LOG.tmp" &&
                mv "$RESCUE_LOG.tmp" "$RESCUE_LOG"
        fi
    done
done

# Same two-step (not --batch) as ws_nav.sh: moveworkspacetomonitor fails
# when $insert_id doesn't exist yet, which would abort a batched switch too.
hyprctl dispatch moveworkspacetomonitor "$insert_id" current 2>/dev/null
hyprctl dispatch workspace "$insert_id"
