#!/bin/bash
# Toggle "sticky resize-on-focus" mode, bound to Prefix+W/A/Z/F (one mode
# per size: two-thirds/third/half/full -- see tmux.conf's Alt+w/a/z/f sizes).
# While a mode is active, tmux-focus-pane.sh re-resizes the pane you land on
# every time you switch focus with Alt+h/j/k/l.
#
# Modes are mutually exclusive and only reachable via their own toggle: if
# another mode is already active, this refuses instead of switching --
# you must turn the current one off (its own Prefix+key) before turning a
# different one on. This keeps a single accidental keypress from silently
# swapping which size is being enforced.
mode="$1"   # w, a, z, or f
cur=$(tmux show-options -gqv @resize_mode)

if [ -z "$cur" ]; then
    tmux set-option -g @resize_mode "$mode"
    tmux display-message "resize-on-focus: $mode"
elif [ "$cur" = "$mode" ]; then
    tmux set-option -gu @resize_mode
    tmux display-message "resize-on-focus: off"
else
    tmux display-message "resize-on-focus: '$cur' is active -- turn it off first"
fi
