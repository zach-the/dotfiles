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
            # Only meaningful for floating windows (tiled windows have no
            # overlapping z-order to fix) — skip the dispatch otherwise so
            # it doesn't add IPC contention on unrelated focus changes,
            # e.g. focusing TigerVNC, which is always tiled.
            floating=$(hyprctl activewindow -j 2>/dev/null | jq -r '.floating // false')
            [[ "$floating" == "true" ]] && hyprctl dispatch bringactivetotop >/dev/null 2>&1
            ;;
    esac
done
