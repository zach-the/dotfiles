#!/bin/bash
# Cycle through the modes listed in MODES, in order, wrapping back to
# the front. Currently a straight two-way toggle: WIDE-TILE <-> FLOAT.
#
# To bring back the three-way cycle (stock dwindle + WIDE-TILE +
# floating), just change the line below to:
#   MODES=(TILE WIDE-TILE FLOAT)
# The TILE case further down already does the right thing — it's just
# unreachable while MODES omits it.
MODES=(WIDE-TILE FLOAT)

#   TILE      = stock dwindle layout, normal binds
#   WIDE-TILE = ultrawide-dwindle-improved plugin layout, normal binds
#   FLOAT     = everything floating, manual-mode submap
#
# Floats/re-tiles windows as needed, flips the catch-all float
# windowrule, switches the active tiling algorithm (via a sourced
# config file, same trick as the float rule below), writes the state
# file waybar's custom/mode module reads, signals waybar to refresh,
# and switches the `manual` submap. The submap switch is dispatched
# here (last, after the reload) rather than via a separate stacked
# `bind = ..., submap, ...` line, so there's no race between this
# script's own reload and an independently-triggered submap
# dispatcher on the same keypress.

STATE_FILE="$HOME/.config/hypr/mode_state"
FLOAT_RULE_FILE="$HOME/.config/hypr/mode_float_rule.conf"
LAYOUT_FILE="$HOME/.config/hypr/mode_layout.conf"
SKIP_WORKSPACE_PREFIX="special"

CURRENT="$(cat "$STATE_FILE" 2>/dev/null)"
NEXT=""
for i in "${!MODES[@]}"; do
    if [ "${MODES[$i]}" = "$CURRENT" ]; then
        NEXT="${MODES[$(( (i + 1) % ${#MODES[@]} ))]}"
        break
    fi
done
[ -z "$NEXT" ] && NEXT="${MODES[0]}"

# Re-tile every floating window except ones parked in the special
# workspace, which stay floating.
retile_all() {
    hyprctl clients -j | jq -r --arg ws "$SKIP_WORKSPACE_PREFIX" \
        '.[] | select(.floating == true) | select(.workspace.name | startswith($ws) | not) | .address' |
    while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done
}

float_all() {
    hyprctl clients -j | jq -r '.[] | select(.floating == false) | .address' |
    while read -r addr; do
        hyprctl dispatch togglefloating "address:$addr"
    done
}

TARGET_SUBMAP="reset"

case "$NEXT" in
    WIDE-TILE)
        [ "$CURRENT" = "FLOAT" ] && retile_all
        echo "# managed by mode_toggle.sh — do not edit by hand" > "$FLOAT_RULE_FILE"
        echo "general:layout = ultrawide-dwindle-improved" > "$LAYOUT_FILE"
        ;;
    TILE)
        [ "$CURRENT" = "FLOAT" ] && retile_all
        echo "# managed by mode_toggle.sh — do not edit by hand" > "$FLOAT_RULE_FILE"
        echo "general:layout = dwindle" > "$LAYOUT_FILE"
        ;;
    FLOAT)
        # Entering manual mode: float everything currently tiled, and
        # make all future windows spawn floating too. Written to a
        # sourced file (not just `hyprctl keyword`) so the rule
        # survives any later `hyprctl reload`, not just this script's.
        float_all
        echo 'windowrule = match:class ^(.*)$, float 1' > "$FLOAT_RULE_FILE"
        TARGET_SUBMAP="manual"
        ;;
esac

echo "$NEXT" > "$STATE_FILE"

hyprctl reload config-only
hyprctl dispatch submap "$TARGET_SUBMAP"

pkill -RTMIN+8 waybar
