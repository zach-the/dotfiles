#!/bin/bash
# Float any window that ends up on the special workspace (scratchpad),
# however it got there — manual move, gesture, or a windowrule redirect
# (see the VPN/torrent/gpgui rules in hyprland.conf). A static `windowrule`
# can't do this: matching on `workspace` only sees the window's workspace
# at creation, before any `workspace special` redirect rule has applied,
# so redirected windows never match. This listens on the event socket
# instead and reacts to openwindow and movewindow, which report the
# post-redirect workspace.

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
    case "$line" in
        openwindow\>\>*)
            rest="${line#openwindow>>}"
            addr="0x${rest%%,*}"
            ws="${rest#*,}"
            ws="${ws%%,*}"
            ;;
        movewindow\>\>*)
            rest="${line#movewindow>>}"
            addr="0x${rest%%,*}"
            ws="${rest#*,}"
            ;;
        *)
            continue
            ;;
    esac
    [[ "$ws" == "special:special" ]] || continue
    floating=$(hyprctl clients -j | jq -r --arg a "$addr" '.[] | select(.address == $a) | .floating')
    [[ "$floating" == "false" ]] && hyprctl dispatch setfloating "address:$addr" >/dev/null 2>&1
done
