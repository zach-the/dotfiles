#!/bin/bash
# Toggle between normal (tiled) and manual (floating) mode.
# Floats/re-tiles windows, flips the catch-all float windowrule, writes
# the state file waybar's custom/mode module reads, signals waybar to
# refresh, and switches the `manual` submap. The submap switch is
# dispatched here (last, after the reload) rather than via a separate
# stacked `bind = ..., submap, ...` line, so there's no race between
# this script's own reload and an independently-triggered submap
# dispatcher on the same keypress.

STATE_FILE="$HOME/.config/hypr/mode_state"
FLOAT_RULE_FILE="$HOME/.config/hypr/mode_float_rule.conf"
SKIP_WORKSPACE_PREFIX="special"

if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "FLOAT" ]; then
    # Leaving manual mode: re-tile everything except windows parked in
    # the special workspace, which stay floating.
    echo "TILE" > "$STATE_FILE"

    hyprctl clients -j | jq -r --arg ws "$SKIP_WORKSPACE_PREFIX" \
        '.[] | select(.floating == true) | select(.workspace.name | startswith($ws) | not) | .address' |
    while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done

    echo "# managed by mode_toggle.sh — do not edit by hand" > "$FLOAT_RULE_FILE"
    TARGET_SUBMAP="reset"
else
    # Entering manual mode: float everything currently tiled, and make
    # all future windows spawn floating too. Written to a sourced file
    # (not just `hyprctl keyword`) so the rule survives any later
    # `hyprctl reload`, not just this script's own reload.
    echo "FLOAT" > "$STATE_FILE"

    hyprctl clients -j | jq -r '.[] | select(.floating == false) | .address' |
    while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done

    echo 'windowrule = match:class ^(.*)$, float 1' > "$FLOAT_RULE_FILE"
    TARGET_SUBMAP="manual"
fi

hyprctl reload config-only
hyprctl dispatch submap "$TARGET_SUBMAP"

pkill -RTMIN+8 waybar
