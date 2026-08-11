#!/bin/bash
# Session/window picker for Prefix+w, replacing tmux's built-in choose-tree.
# tmux's tree-mode keys are hardcoded in C and can't be rebound via
# `bind-key -T tree-mode`, so this exists purely to give J/K a distinct
# meaning: jump to the first window of the next/previous session, while
# j/k (or the arrow keys) still move one window at a time.
list_file=$(mktemp)
trap 'rm -f "$list_file"' EXIT

# Exclude session-group duplicates: tmux names these <session>-<10-digit
# timestamp> when a session gets reattached/relinked into a group, and they
# carry the same windows as the canonical session. Then insert an
# unselectable divider row (empty target field) before each new session's
# first window.
tmux list-windows -a -F '#{session_name}	#{session_name}:#{window_index}	#{window_index}: #{window_name}#{?window_active, *,}' \
    | grep -vE '^[^	]+-[0-9]{10}	' \
    | awk -F'\t' '$1 != prev { print $1 "\t\t── " $1 " ──" } { print; prev = $1 }' > "$list_file"

sel=$(fzf-tmux -p 70%,60% -- \
    --reverse --delimiter=$'\t' --with-nth=3 \
    --header 'enter: switch    J/K: jump session    j/k: window' \
    --prompt 'window> ' \
    --bind 'start:pos(2)' \
    --bind 'j:down,k:up' \
    --bind "J:transform(~/dotfiles/tmux-choose-tree-jump.sh next \$FZF_POS $list_file)" \
    --bind "K:transform(~/dotfiles/tmux-choose-tree-jump.sh prev \$FZF_POS $list_file)" \
    < "$list_file")

if [ -n "$sel" ]; then
    target=$(printf '%s' "$sel" | cut -f2)
    [ -n "$target" ] && tmux switch-client -t "$target"
fi
exit 0
