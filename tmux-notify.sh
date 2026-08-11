#!/bin/bash
# Show a message in the same centered popup style used elsewhere in this
# config (see the broadcast/protected toggles), instead of tmux's default
# status-line message area. Width grows to fit the text so longer messages
# don't get clipped.
msg="$*"
width=$(( ${#msg} + 4 ))
[ "$width" -lt 24 ] && width=24
tmux display-popup -x C -y C -w "$width" -h 3 \
    -s "bg=#10101c,fg=#a9b1d6" -S "bg=#10101c,fg=#ff007f" \
    -E "tput civis; echo \"  $msg  \"; sleep 1.2"
