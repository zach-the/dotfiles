#!/bin/bash
# Turn the spacer scrollbars (see tmux.conf's pane-scrollbars section) on for
# a window only when it has side-by-side panes, i.e. at least one vertical
# divider to widen; single-column windows get no extra left-edge column.
#
# Usage: tmux-sync-scrollbars.sh [window_id]  (no argument: every window)
#
# A pane sitting to the right of another has pane_left > 1 whether or not
# scrollbars are currently on (the leftmost pane starts at 0 or 1), so the
# check doesn't depend on the state it's toggling. Only sets the option when
# it would change, since setting it re-lays-out the window and fires
# window-layout-changed (the hook that calls this) again.
sync_window() {
    local w=$1 want cur
    if tmux list-panes -t "$w" -F '#{pane_left}' | awk '$1 > 1 { f = 1 } END { exit !f }'; then
        want=on
    else
        want=off
    fi
    cur=$(tmux display-message -p -t "$w" '#{pane-scrollbars}')
    if [ "$cur" != "$want" ]; then
        tmux set -w -t "$w" pane-scrollbars "$want"
    fi
}

if [ $# -gt 0 ]; then
    sync_window "$1"
else
    for w in $(tmux list-windows -a -F '#{window_id}'); do
        sync_window "$w"
    done
fi
