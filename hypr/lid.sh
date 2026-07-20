#!/usr/bin/env bash
# Lid switch handler.
# If another display is connected, move any windows sitting on eDP-1's
# workspaces (1-5) over to the corresponding workspace on the primary
# external monitor (eDP-1 ws 4 -> external ws 9, matching the 5-wide
# per-monitor groups assign_workspaces() in monitor_init.sh hands out), then
# disable the internal panel entirely and leave the system running (logind's
# HandleLidSwitchDocked=ignore already keeps it awake). Windows are moved
# because a disabled eDP-1 keeps its workspaces assigned to it, so anything
# left there becomes inaccessible until the lid reopens. Windows on a
# special (scratchpad) workspace are left alone. The panel is disabled
# (rather than just dpms'd off) because dpms only blanks the backlight -
# eDP-1 stays part of the active layout and the cursor can still wander onto
# it; disabling removes it from the layout entirely.
# If the laptop panel is the only display, lock and suspend as before.

INTERNAL="eDP-1"
MONITORS_CONF="$(dirname -- "$0")/monitors.conf"

case "$1" in
  close)
    # First external monitor sorted by (x, y) - same ordering monitor_init.sh
    # uses, so its workspace group is always eDP-1's base (0) + 5.
    primary=$(hyprctl monitors -j | jq -r --arg int "$INTERNAL" \
      '[.[] | select(.name != $int and .disabled == false)] | sort_by(.x, .y) | .[0].name // empty')
    if [ -n "$primary" ]; then
      base=5
      edp_id=$(hyprctl monitors -j | jq --arg int "$INTERNAL" '[.[] | select(.name == $int)][0].id')
      mapfile -t moves < <(hyprctl clients -j | jq -r --argjson id "$edp_id" \
        '.[] | select(.monitor == $id and .workspace.id > 0) | "\(.workspace.id) \(.address)"')
      if [ "${#moves[@]}" -gt 0 ]; then
        batch=""
        for entry in "${moves[@]}"; do
          ws="${entry%% *}"
          addr="${entry#* }"
          batch+="dispatch movetoworkspacesilent $(( base + ws )),address:$addr ; "
        done
        hyprctl --batch "${batch% ; }"
      fi
      hyprctl keyword monitor "$INTERNAL,disable"
    else
      hyprlock &
      sleep 0.5
      hyprctl dispatch dpms off
      systemctl suspend
    fi
    ;;
  open)
    line=$(grep "^monitor=$INTERNAL," "$MONITORS_CONF")
    hyprctl keyword monitor "${line#monitor=}"
    ;;
esac
