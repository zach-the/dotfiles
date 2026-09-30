#!/bin/bash
# Rename the current session -- or, if this is one of tm()'s grouped "mirror"
# sessions (named "<parent>-<10-digit epoch>"), rename its parent instead.
# Mirrors in the group are renamed to "<new>-<epoch>" so they stay in sync
# (and so tm() / tmux-move-window.sh still recognize them as mirrors).
#
# Usage: tmux-rename-session.sh              (prompt for a new name)
#        tmux-rename-session.sh apply OLD NEW (called back by the prompt)
mirror_re='^.+-[0-9]{10}$'

if [ "$1" = "apply" ]; then
    old="$2"
    new="$3"
    [ -z "$new" ] || [ "$new" = "$old" ] && exit 0
    group=$(tmux display-message -p -t "=$old:" '#{session_group}')
    tmux rename-session -t "=$old" -- "$new" || exit 1
    if [ -n "$group" ]; then
        tmux list-sessions -F '#{session_name} #{session_group}' \
            | awk -v g="$group" '$2 == g {print $1}' \
            | grep -E "$mirror_re" \
            | while IFS= read -r m; do
                nm="${new}-${m##*-}"
                tmux rename-session -t "=$m" -- "$nm"
                # tm()'s cleanup hook hardcodes the mirror's name; repoint it
                tmux set-hook -t "=$nm:" client-detached "kill-session -t \"=$nm\""
            done
    fi
    exit 0
fi

cur=$(tmux display-message -p '#{session_name}')
group=$(tmux display-message -p '#{session_group}')
parent=""

if [ -n "$group" ]; then
    parent=$(tmux list-sessions -F '#{session_name} #{session_group}' \
        | awk -v g="$group" '$2 == g {print $1}' \
        | grep -vE "$mirror_re" | head -1)
fi
[ -z "$parent" ] && parent="$cur"

tmux command-prompt -I "$parent" -p "rename session:" \
    "run-shell \"~/dotfiles/tmux/tmux-rename-session.sh apply '$parent' '%%'\""
