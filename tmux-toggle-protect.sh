#!/bin/bash
# Toggle the @protected flag on the current session (checked by the Ctrl+W
# kill-pane confirm and shown in the status-right indicator), and show a
# brief popup confirming the new state.
cur=$(tmux show-options -v @protected 2>/dev/null)
if [ "$cur" = "1" ]; then
    tmux set-option @protected 0
    state="off"
else
    tmux set-option @protected 1
    state="on"
fi

tmux display-popup -x C -y C -w 30 -h 3 -s "bg=colour1,fg=colour0" -S "bg=colour1,fg=colour0" \
    -E "tput civis; echo \"  protected: $state  \"; sleep 1.5"
