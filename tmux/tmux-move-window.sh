#!/bin/bash
# Move the current window to another session via fzf, or into a brand-new
# session (prompts for a name). Invoked by Prefix+M with the window's own
# "session:index" target as $1.
win="$1"

if [ "$2" = "--create" ]; then
    name="$3"
    [ -n "$name" ] || exit 0
    tmux new-session -d -s "$name"
    tmux move-window -s "$win" -t "$name:"
    tmux kill-window -t "$name:^"
    exit 0
fi

cur_session="${win%%:*}"
sessions=$(tmux list-sessions -F '#{session_name}' | grep -vE '^.+-[0-9]{10}$' | grep -v "^${cur_session}$")
dst=$(printf '%s\n%s' "+ new session" "$sessions" | fzf-tmux -p 60%,40% -- --reverse --prompt="Move window to: ")

if [ "$dst" = "+ new session" ]; then
    tmux command-prompt -p "New session name: " "run-shell \"~/dotfiles/tmux/tmux-move-window.sh '$win' --create '%%'\""
elif [ -n "$dst" ]; then
    tmux move-window -s "$win" -t "$dst:"
fi
