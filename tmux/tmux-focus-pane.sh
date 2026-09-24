#!/bin/bash
# Move focus one pane in the given direction (L/D/U/R, matching tmux's own
# select-pane flags), then, if a sticky resize-on-focus mode is toggled on
# (Prefix+W/A/Z/F -- see tmux-toggle-resize-mode.sh), resize the newly
# focused pane to that mode's size via tmux-resize-pane.sh.
dir="$1"
tmux select-pane "-$dir"

mode=$(tmux show-options -gqv @resize_mode)
[ -z "$mode" ] && exit 0

case "$mode" in
    w) width=67; height=71 ;;
    a) width=33; height=71 ;;
    z) width=50; height=71 ;;
    f) width=90; height=90 ;;
    *) exit 0 ;;
esac

pane_id=$(tmux display-message -p '#{pane_id}')
~/dotfiles/tmux/tmux-resize-pane.sh "$width" "$pane_id" "$height"
