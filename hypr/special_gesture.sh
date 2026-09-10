#!/bin/bash
# Exit the special workspace (scratchpad), driven by the 3-finger
# swipe-down gesture. Only togglespecialworkspace closes it, and it's
# a pure toggle with no notion of direction — calling it unconditionally
# would open special on a stray down-swipe while already out. Gate on
# the current state so down is a no-op once you're already out.
#
# Entering has no such problem: it's handled directly in hyprland.conf
# via `gesture = 3, up, dispatcher, workspace, special:special`, which
# is idempotent (repeat calls are a no-op) so it needs no script.

NAME="special"

# The special workspace is an overlay, not "the" active workspace —
# `hyprctl activeworkspace` never reports it even while it's showing.
# The focused monitor's specialWorkspace field is what actually
# reflects whether it's currently open.
special_ws="$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .specialWorkspace.name')"

[[ "$special_ws" == "special:$NAME" ]] && hyprctl dispatch togglespecialworkspace "$NAME"
