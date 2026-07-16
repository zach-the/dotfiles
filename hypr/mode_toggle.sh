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

#   TILE      = stock dwindle layout
#   WIDE-TILE = ultrawide-dwindle-improved plugin layout
#   FLOAT     = everything floating
#
# Keybinds are identical across all three — this only floats/re-tiles
# windows as needed, flips the catch-all float windowrule, switches
# the active tiling algorithm (via a sourced config file, same trick
# as the float rule below), writes the state file waybar's custom/mode
# module reads, and signals waybar to refresh.

STATE_FILE="$HOME/.config/hypr/mode_state"
FLOAT_RULE_FILE="$HOME/.config/hypr/mode_float_rule.conf"
LAYOUT_FILE="$HOME/.config/hypr/mode_layout.conf"
FLOAT_LAYOUT_SCRIPT="$HOME/.config/hypr/float_layout.sh"
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

case "$NEXT" in
    WIDE-TILE)
        # Leaving float mode: snapshot every floating window's position
        # and size before re-tiling, so FLOAT can restore it later.
        if [ "$CURRENT" = "FLOAT" ]; then
            "$FLOAT_LAYOUT_SCRIPT" save
            retile_all
        fi
        echo "# managed by mode_toggle.sh — do not edit by hand" > "$FLOAT_RULE_FILE"
        echo "general:layout = ultrawide-dwindle-improved" > "$LAYOUT_FILE"
        ;;
    TILE)
        if [ "$CURRENT" = "FLOAT" ]; then
            "$FLOAT_LAYOUT_SCRIPT" save
            retile_all
        fi
        echo "# managed by mode_toggle.sh — do not edit by hand" > "$FLOAT_RULE_FILE"
        echo "general:layout = dwindle" > "$LAYOUT_FILE"
        ;;
    FLOAT)
        # Entering float mode: float everything currently tiled, and
        # make all future windows spawn floating too. Written to a
        # sourced file (not just `hyprctl keyword`) so the rule
        # survives any later `hyprctl reload`, not just this script's.
        float_all
        echo 'windowrule = match:class ^(.*)$, float 1' > "$FLOAT_RULE_FILE"
        # Put back whatever position/size each window had the last
        # time we left float mode, where a match (by address) exists.
        "$FLOAT_LAYOUT_SCRIPT" restore
        ;;
esac

echo "$NEXT" > "$STATE_FILE"

hyprctl reload config-only

pkill -RTMIN+8 waybar
