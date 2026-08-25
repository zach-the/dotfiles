#!/bin/bash
# Signal waybar's custom/window module to refresh on every focus
# change, so the app-name indicator tracks focus instantly instead of
# on a poll. Same activewindow-listener pattern as raise_on_focus.sh,
# kept separate since it drives a different waybar signal.

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
    case "$line" in
        activewindow\>\>*|activewindowv2\>\>*)
            pkill -RTMIN+11 waybar
            ;;
    esac
done
