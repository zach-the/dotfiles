#!/bin/bash
err=$(tmux source-file ~/dotfiles/tmux.conf 2>&1)
if [ -n "$err" ]; then
    printf "%s\n" "$err" > /tmp/_tmux_reload_err
    tmux display-popup -x C -y C -w 70 -h 8 -s "bg=colour1,fg=colour15" -S "bg=colour1,fg=colour15" \
        -E "tput civis; cat /tmp/_tmux_reload_err; sleep 5; rm -f /tmp/_tmux_reload_err"
else
    tmux display-popup -x C -y C -w 30 -h 3 -s "bg=colour2,fg=colour0" -S "bg=colour2,fg=colour0" \
        -E "tput civis; echo \"  tmux.conf reloaded  \"; sleep 1.5"
fi
