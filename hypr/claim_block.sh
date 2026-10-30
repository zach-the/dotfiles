#!/usr/bin/env bash
# Usage: claim_block.sh <monitor>
#
# Ensures every workspace currently sitting on <monitor> falls inside its
# own block (ws_nav.sh's one-block-per-monitor numbering scheme -- see its
# header comment). Anything outside the block gets relabeled into a fresh
# slot at the top of it, windows and all; if the stray was <monitor>'s
# actively displayed workspace, the view follows it to the new id, so
# nothing jumps or goes blank.
#
# Shared by monitor_init.sh (proactively, whenever a monitor connects) and
# ws_nav.sh (defensively, on every hyper+H/L) so this invariant holds no
# matter which of the two notices a violation first. The connect-time
# sweep can lose a race it has no way to win outright: Hyprland hands a
# newly-connected monitor its own default workspace (the lowest free ID)
# the moment it connects, before any userspace script gets a chance to
# react, and anything opened in that instant -- an app restoring its own
# session on login, etc. -- can land there first. Rather than chase that
# race with more timing (sleeps, retries), ws_nav.sh closes it from the
# other direction: by re-checking this invariant right as the user
# actually presses hyper+H/L, which is the one moment it has to be correct
# for the symptom (wrong prev/next) to never be visible, independent of
# how or when the stray appeared.
set -euo pipefail
BLOCK=100
monitor="$1"

monitor_index() {
    local m="$1"
    if [ "$m" == "eDP-1" ]; then
        echo 0
    else
        hyprctl monitors -j | jq -r '
            [.[] | select(.name != "eDP-1")] |
            sort_by(.x, .y) |
            to_entries[] |
            select(.value.name == "'"$m"'") |
            (.key + 1)
        '
    fi
}

index=$(monitor_index "$monitor")
[[ -z "$index" || "$index" == "null" ]] && exit 0
base=$(( index * BLOCK ))

workspaces=$(hyprctl workspaces -j) || exit 0
mapfile -t stray < <(jq -r --arg mon "$monitor" --argjson base "$base" --argjson block "$BLOCK" '
    [.[] | select(.monitor == $mon and .id > 0 and (.id <= $base or .id > $base + $block))] |
    sort_by(.id) | .[].id
' <<< "$workspaces")

(( ${#stray[@]} == 0 )) && exit 0

active_ws=$(hyprctl monitors -j | jq -r --arg mon "$monitor" \
    '.[] | select(.name == $mon) | .activeWorkspace.id')

next=$(jq -r --argjson b "$base" --argjson block "$BLOCK" \
    '[.[] | select(.id > $b and .id <= $b + $block) | .id] | max // $b' \
    <<< "$workspaces")

for old in "${stray[@]}"; do
    next=$(( next + 1 ))
    want=$next
    addrs=$(hyprctl clients -j | jq -r '.[] | select(.workspace.id == '"$old"') | .address')
    if [ -n "$addrs" ]; then
        # movetoworkspacesilent creates $want on demand -- it doesn't exist
        # yet (it's one past whatever the block's current top is), so this
        # has to run before moveworkspacetomonitor, which otherwise has
        # nothing to claim and fails with "Workspace not found".
        for addr in $addrs; do
            hyprctl dispatch "hl.dsp.window.move({ window = \"address:$addr\", workspace = $want, follow = false })"
        done
        hyprctl dispatch "hl.dsp.workspace.move({ workspace = $want, monitor = \"$monitor\" })" 2>/dev/null
    fi
    if [ "$old" == "$active_ws" ]; then
        # The stray was what the monitor was actually displaying. If it had
        # windows, $want now exists and just needs the view switched to
        # it; if it didn't, nothing above created $want at all. The same
        # focus-hop assign_workspace() uses for a monitor's very first
        # workspace covers both: it creates $want if needed and leaves
        # $monitor looking at it either way, without assuming $monitor is
        # the one currently focused (it usually isn't, when this runs from
        # monitor_init.sh for a monitor the user isn't looking at).
        prev_mon=$(hyprctl activeworkspace -j | jq -r '.monitor')
        hyprctl --batch "dispatch hl.dsp.focus({ monitor = \"$monitor\" }) ; dispatch hl.dsp.focus({ workspace = $want }) ; dispatch hl.dsp.focus({ monitor = \"$prev_mon\" })"
    fi
done
