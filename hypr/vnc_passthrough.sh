#!/bin/bash
# While a remote-desktop viewer (TigerVNC's "Vncviewer", or Remmina's
# "org.remmina.Remmina" — covers both its launcher and session windows) is
# focused, switch to the empty "vnc" submap (defined in hyprland.conf) so
# plain SUPER / SUPER+SHIFT keybinds have no match and fall through
# untouched to the focused window — the viewer then forwards them into the
# remote session — instead of triggering Hyprland's own window-management
# actions. Every other bind ($hyper combos, media keys, screenshots, etc.)
# is flagged submapUniversal in hyprland.conf so it keeps working no matter
# which submap is active.
# Runs as a long-lived listener on Hyprland's event socket, mirroring
# raise_on_focus.sh, so it catches every kind of focus change (click,
# keyboard movefocus, the viewer window closing while focused, etc.).

SOCK="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

set_submap_for_class() {
    case "${1,,}" in
        vncviewer|org.remmina.remmina)
            hyprctl dispatch submap vnc >/dev/null 2>&1
            ;;
        *)
            hyprctl dispatch submap reset >/dev/null 2>&1
            ;;
    esac
}

# Handle whatever's already focused when this script (re)starts.
set_submap_for_class "$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty')"

socat -U - UNIX-CONNECT:"$SOCK" | while read -r line; do
    case "$line" in
        activewindow\>\>*)
            rest="${line#activewindow>>}"
            set_submap_for_class "${rest%%,*}"
            ;;
    esac
done
