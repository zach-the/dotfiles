#!/usr/bin/env bash
# Usage: ./ws_insert_move.sh <left|right>
#
# Moves the focused window into a brand-new empty workspace inserted
# immediately to its left or right, on the current monitor, and switches
# focus to follow it. Every workspace already at or past the insertion
# point (within this monitor's block -- see ws_nav.sh for the block
# layout) shifts one position further right to make room; for "left"
# that includes the current workspace's own remaining windows, which
# shift right along with it while the moved window reclaims the
# now-vacant original slot. Companion to ws_insert_right.sh, which does
# the same insert without bringing a window along.

direction=$1
BLOCK=100
RESCUE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/workspace-rescue.log"

active_ws_info=$(hyprctl activeworkspace -j)
current_mon_name=$(echo "$active_ws_info" | jq -r '.monitor')
current_ws=$(echo "$active_ws_info" | jq -r '.id')

active_window_addr=$(hyprctl activewindow -j | jq -r '.address')
if [ -z "$active_window_addr" ] || [ "$active_window_addr" == "null" ]; then
    exit 0
fi

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

if [ "$direction" == "left" ]; then
    insert_id=$current_ws
else
    insert_id=$(( current_ws + 1 ))
fi

# Shift every workspace at or past the insert point one position further
# right. Process highest id first so no move ever lands on a still-occupied
# slot (the top of the block always lands on a genuinely empty id). For
# "left", current_ws itself is in range and gets swept up here too (its
# windows, including the one we're moving, all land one slot over).
#
# movetoworkspacesilent can reshuffle a tiled layout's split tree (windows
# land back in whatever order they're re-inserted, not necessarily the
# order they held before), so every moved window's exact position/size is
# snapshotted beforehand and force-restored with movewindowpixel/
# resizewindowpixel once all the moves are done -- same trick winmove.sh
# uses for pixel-exact placement, just replaying geometry that's already
# known to tile correctly instead of computing it fresh. The window that's
# actually being reclaimed below is skipped here: it's about to end up
# alone on a brand-new workspace, where it should fill the whole thing
# rather than keep the cramped size it had while sharing with neighbors.
clients_snapshot=$(hyprctl clients -j)
mapfile -t shift_ids < <(hyprctl workspaces -j | jq -r '
    [.[] | select(.id >= '"$insert_id"' and .id <= '"$((base + BLOCK))"')] |
    sort_by(-.id) | .[].id
')

restore_specs=()
for id in "${shift_ids[@]}"; do
    new_id=$(( id + 1 ))
    mapfile -t win_specs < <(jq -r --arg skip "$active_window_addr" \
        '.[] | select(.workspace.id == '"$id"') | select(.fullscreen == 0) | select(.address != $skip) | "\(.address)\t\(.at[0])\t\(.at[1])\t\(.size[0])\t\(.size[1])"' <<< "$clients_snapshot")
    addrs=$(jq -r '.[] | select(.workspace.id == '"$id"') | .address' <<< "$clients_snapshot")
    for addr in $addrs; do
        hyprctl dispatch movetoworkspacesilent "$new_id,address:$addr"
        if [ -s "$RESCUE_LOG" ]; then
            awk -F'\t' -v OFS='\t' -v a="$addr" -v old="$id" -v new="$new_id" \
                '$5 == a && $4 == old { $4 = new } 1' "$RESCUE_LOG" > "$RESCUE_LOG.tmp" &&
                mv "$RESCUE_LOG.tmp" "$RESCUE_LOG"
        fi
    done
    restore_specs+=("${win_specs[@]}")
done

# Reclaim the insert slot for the window that's actually moving. For
# "right" this is where it already was (current_ws sat outside the shift
# range above); for "left" it was swept up into the shift and needs
# pulling back down into the now-empty original slot.
hyprctl dispatch movetoworkspacesilent "$insert_id,address:$active_window_addr"
if [ -s "$RESCUE_LOG" ]; then
    awk -F'\t' -v OFS='\t' -v a="$active_window_addr" -v new="$insert_id" \
        '$5 == a { $4 = new } 1' "$RESCUE_LOG" > "$RESCUE_LOG.tmp" &&
        mv "$RESCUE_LOG.tmp" "$RESCUE_LOG"
fi

# Same two-step (not --batch) as ws_nav.sh/ws_insert_right.sh:
# moveworkspacetomonitor fails when $insert_id doesn't exist yet, which
# would abort a batched switch too.
hyprctl dispatch moveworkspacetomonitor "$insert_id" current 2>/dev/null
hyprctl dispatch workspace "$insert_id"

for spec in "${restore_specs[@]}"; do
    IFS=$'\t' read -r addr x y w h <<< "$spec"
    hyprctl dispatch resizewindowpixel "exact $w $h,address:$addr"
    hyprctl dispatch movewindowpixel "exact $x $y,address:$addr"
done
