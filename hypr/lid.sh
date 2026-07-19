#!/usr/bin/env bash
# Lid switch handler.
# If another display is connected, just power off the internal panel and
# leave the system running (logind's HandleLidSwitchDocked=ignore already
# keeps it awake; this only handles blanking eDP-1).
# If the laptop panel is the only display, lock and suspend as before.

INTERNAL="eDP-1"

case "$1" in
  close)
    external=$(hyprctl monitors -j | jq "[.[] | select(.name != \"$INTERNAL\" and .disabled == false)] | length")
    if [ "$external" -gt 0 ]; then
      hyprctl dispatch dpms off "$INTERNAL"
    else
      hyprlock &
      sleep 0.5
      hyprctl dispatch dpms off
      systemctl suspend
    fi
    ;;
  open)
    hyprctl dispatch dpms on "$INTERNAL"
    ;;
esac
