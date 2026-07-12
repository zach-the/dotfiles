#!/bin/bash
# Bring whichever window has focus to the top of the z-order, for every
# kind of focus change: mouse hover (follow_mouse), click, and keyboard
# movefocus. Runs as a long-lived listener on Hyprland's event socket
# rather than being wired into individual binds, so it covers focus
# changes no keybind causes (e.g. hover-focus under follow_mouse=1).

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
    case "$line" in
        activewindow\>\>*|activewindowv2\>\>*)
            hyprctl dispatch bringactivetotop >/dev/null 2>&1
            ;;
    esac
done
