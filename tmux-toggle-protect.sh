#!/bin/bash
# Toggle the @protected flag for the current session (checked by the Ctrl+W
# kill-pane confirm and shown in the status-right indicator), and show a
# brief popup confirming the new state.
#
# tm() spawns grouped "duplicate" sessions (same session_group, separate
# @protected storage per session) so multiple terminals can view a session
# without conflict. Protection is a property of the underlying work, not of
# which terminal is looking at it, so a toggle here is applied to every
# session in the group -- parent and all duplicates -- not just this one.
cur_session=$(tmux display-message -p '#{session_name}')
group=$(tmux display-message -p '#{session_group}')

if [ -n "$group" ]; then
    family=$(tmux list-sessions -F '#{session_name} #{session_group}' | awk -v g="$group" '$2 == g {print $1}')
else
    family="$cur_session"
fi

cur=$(tmux show-options -t "$cur_session" -v @protected 2>/dev/null)
if [ "$cur" = "1" ]; then
    new=0
    state="off"
else
    new=1
    state="on"
fi

while IFS= read -r s; do
    [ -n "$s" ] && tmux set-option -t "$s" @protected "$new"
done <<< "$family"

tmux display-popup -x C -y C -w 30 -h 3 -s "bg=colour1,fg=colour0" -S "bg=colour1,fg=colour0" \
    -E "tput civis; echo \"  protected: $state  \"; sleep 1.5"
