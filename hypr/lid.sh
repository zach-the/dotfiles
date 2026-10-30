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
          batch+="dispatch hl.dsp.window.move({ window = \"address:$addr\", workspace = $(( base + ws )), follow = false }) ; "
        done
        hyprctl --batch "${batch% ; }"
      fi
      hyprctl keyword monitor "$INTERNAL,disable"
    else
      hyprlock &
      sleep 0.5
      hyprctl dispatch 'hl.dsp.dpms({ action = "disable" })'
      systemctl suspend
    fi
    ;;
  open)
    line=$(grep "^monitor=$INTERNAL," "$MONITORS_CONF")
    hyprctl keyword monitor "${line#monitor=}"
    # hyprlock's PAM thread tried Howdy once at lock time (lid closing, nobody
    # looking), Howdy failed, and the thread is now blocked waiting on the
    # password prompt - it can't loop back to retry Howdy until something is
    # submitted. A synthetic Enter unblocks that stale attempt (which can only
    # fail) so the thread loops back and tries Howdy again, now that a face is
    # actually in view. There's a brief visible "authentication failed" flash
    # from the stale attempt before the fresh one lands - known cosmetic
    # issue, not fixed yet. Do NOT replace this with killing/relaunching
    # hyprlock: that raced badly and crashed the lock client entirely
    # (Hyprland's "oopsie daisy" crashed-lockscreen fallback, 2026-10-26).
    if pgrep -x hyprlock >/dev/null; then
      wtype -k Return
      sleep 2
    fi
    hyprctl dispatch "hl.dsp.dpms({ action = \"enable\", monitor = \"$INTERNAL\" })"
    ;;
esac
