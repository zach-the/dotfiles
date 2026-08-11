#!/bin/bash
# Toggle @transparent live (see tmux.conf's transparency section) and
# reload immediately so the change takes effect right away.
#
# Sets the live option directly, then sources tmux.conf as its own
# subsequent command -- tmux's %if directives resolve against option state
# as it stood *before* a source-file call, so the set has to already be
# live when source-file starts, not just earlier in the same file.
cur=$(tmux show-options -gv @transparent 2>/dev/null)
if [ "$cur" = "1" ]; then
    new=0
    state="solid"
else
    new=1
    state="transparent"
fi

tmux set -g @transparent "$new"
tmux source-file ~/dotfiles/tmux/tmux.conf

tmux display-message "$state"
