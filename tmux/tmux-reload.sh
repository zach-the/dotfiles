#!/bin/bash
err=$(tmux source-file ~/dotfiles/tmux/tmux.conf 2>&1)
if [ -n "$err" ]; then
    tmux display-message "tmux.conf error: $err"
else
    tmux display-message "tmux.conf reloaded"
fi
