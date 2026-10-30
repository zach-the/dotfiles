#!/usr/bin/env bash
# Usage: ./ws_nav.sh [next|prev|<N>] [move]
#
# Workspace layout: one continuous, uncapped block of 100 IDs per monitor
#   eDP-1 (always index 0): workspaces   1-99
#   1st external (by X,Y):  workspaces 101-199
#   2nd external:           workspaces 201-299
#   ...and so on
#
# Each monitor starts on position 1 (its lowest workspace) and "next" just
# increments by 1 forever -- no fixed-size block that spills over into a
# separate overflow range, so a monitor grows exactly as many workspaces as
# you actually create.

action=$1
move=$2

BLOCK=100
# See monitor_init.sh: windows rescued from an unplugged monitor are logged
# here so they can be sent back when it returns.
RESCUE_LOG="${XDG_STATE_HOME:-$HOME/.local/state}/hypr/workspace-rescue.log"

active_ws_info=$(hyprctl activeworkspace -j)
current_mon_name=$(echo "$active_ws_info" | jq -r '.monitor')

# Defensive self-heal: fold anything on this monitor that's outside its
# block back into it before computing pos/target below -- see
# claim_block.sh for why a stray can exist here at all even with
# monitor_init.sh's own proactive sweep on connect. Cheap no-op when
# nothing's wrong (single hyprctl read, no dispatches), so this runs
# unconditionally rather than only in response to a symptom.
"$(dirname "$0")/claim_block.sh" "$current_mon_name"

# Re-read after claim_block.sh: if current_ws itself was the stray, it
# followed its relabel to a new id and switched focus there, so this has
# to reflect that rather than the (now gone) id we started with.
active_ws_info=$(hyprctl activeworkspace -j)
current_ws=$(echo "$active_ws_info" | jq -r '.id')
current_ws_windows=$(echo "$active_ws_info" | jq -r '.windows')

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

# Map current_ws to a position within this monitor's block. Anything out
# of range (shouldn't normally happen) falls back to 1.
if (( current_ws > base && current_ws <= base + BLOCK )); then
    pos=$(( current_ws - base ))
else
    pos=1
fi

if [ "$action" == "next" ]; then
    pos=$(( pos + 1 ))
elif [ "$action" == "prev" ]; then
    if (( pos > 1 )); then pos=$(( pos - 1 )); fi
elif [[ "$action" =~ ^[0-9]+$ ]]; then
    pos=$action
fi

target=$(( base + pos ))

# "next" past the rightmost workspace on this monitor would create a brand
# new one -- skip that if the workspace we're currently on is empty, since
# there's no point spawning another blank workspace.
if [ "$action" == "next" ] && (( current_ws_windows == 0 )); then
    target_exists=$(hyprctl workspaces -j | jq -r '[.[] | select(.id == '"$target"')] | length')
    if (( target_exists == 0 )); then
        exit 0
    fi
fi

if [ "$move" == "move" ]; then
    hyprctl dispatch "hl.dsp.window.move({ workspace = $target, follow = true })"
else
    # Separate calls, not --batch: when $target doesn't exist yet (growing
    # past this monitor's current top), moveworkspacetomonitor fails --
    # and inside a --batch string, hyprctl aborts the rest of the batch on
    # that first failure, so the workspace switch right after it would
    # never actually run. Run standalone, moveworkspacetomonitor's failure
    # can't block the switch that follows it.
    hyprctl dispatch "hl.dsp.workspace.move({ workspace = $target, monitor = \"current\" })" 2>/dev/null
    hyprctl dispatch "hl.dsp.focus({ workspace = $target })"
fi

# Compact numbering on this monitor. Hyprland destroys an empty,
# non-persistent workspace as soon as you leave it, which can leave a gap
# in the sequence (e.g. 1, 3 after 2 empties out and you move away). Close
# any such gaps by shifting every workspace above one down by however many
# empty slots preceded it, so the block stays a dense 1, 2, 3, ... run.
# If the workspace we just switched to is itself renumbered in the
# process, refocus its new id so the view doesn't end up pointing at the
# now-empty old id.
mapfile -t existing_ids < <(hyprctl workspaces -j | jq -r '
    [.[] | select(.id > '"$base"' and .id <= '"$((base + BLOCK))"')] |
    sort_by(.id) | .[].id
')

refocus=""
expected=1
for id in "${existing_ids[@]}"; do
    want=$(( base + expected ))
    if [ "$id" != "$want" ]; then
        addrs=$(hyprctl clients -j | jq -r '.[] | select(.workspace.id == '"$id"') | .address')
        for addr in $addrs; do
            hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = $want, follow = false })"
            # Keep the rescue log pointing at the window's new workspace,
            # otherwise it no longer matches when the monitor comes back.
            if [ -s "$RESCUE_LOG" ]; then
                awk -F'\t' -v OFS='\t' -v a="$addr" -v old="$id" -v new="$want" \
                    '$5 == a && $4 == old { $4 = new } 1' "$RESCUE_LOG" > "$RESCUE_LOG.tmp" &&
                    mv "$RESCUE_LOG.tmp" "$RESCUE_LOG"
            fi
        done
        if [ "$id" == "$target" ]; then
            refocus=$want
        fi
    fi
    expected=$(( expected + 1 ))
done

if [ -n "$refocus" ]; then
    hyprctl dispatch "hl.dsp.focus({ workspace = $refocus })"
fi
