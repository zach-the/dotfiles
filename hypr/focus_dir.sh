#!/usr/bin/env bash
# Usage: focus_dir.sh <l|r|u|d>
#
# win+hjkl / arrow-key focus movement. Plain `hyprctl dispatch movefocus`
# doesn't reliably cross monitor boundaries (hyprwm/Hyprland#3567), does
# nothing on a blank monitor, and never moves the mouse -- so with
# follow_mouse=1 the cursor is left hovering the old monitor after a
# cross-monitor jump, ready to steal focus back on the next mouse move.
#
# This wrapper checks for itself whether there's another window further
# in the requested direction on the CURRENT monitor. If so, it just
# defers to movefocus as normal. Otherwise -- edge of the monitor, only
# window on it, or no windows on it at all -- it treats the monitor
# itself as exhausted and jumps to the adjacent monitor in that
# direction, picked by actual geometry (so this works for left/right,
# above/below, or grid layouts, and regardless of whether the source or
# destination monitor has any windows), warping the cursor to its
# center.
set -euo pipefail

dir=$1

mon_json=$(hyprctl monitors -j)
cur_name=$(jq -r '.[] | select(.focused == true) | .name' <<< "$mon_json")
cur_mon_idx=$(jq -r '.[] | select(.focused == true) | .id' <<< "$mon_json")

active=$(hyprctl activewindow -j)

has_neighbor=false
if [ "$active" != "null" ]; then
    cur_ws=$(jq -r '.workspace.id' <<< "$active")
    cur_cx=$(jq -r '.at[0] + .size[0]/2' <<< "$active")
    cur_cy=$(jq -r '.at[1] + .size[1]/2' <<< "$active")

    has_neighbor=$(hyprctl clients -j | jq --arg dir "$dir" --argjson ws "$cur_ws" \
      --argjson mon "$cur_mon_idx" --argjson cx "$cur_cx" --argjson cy "$cur_cy" '
      [ .[] | select(.workspace.id == $ws and .monitor == $mon) |
        (.at[0] + .size[0]/2) as $ocx |
        (.at[1] + .size[1]/2) as $ocy |
        select(
          if $dir == "l" then $ocx < $cx
          elif $dir == "r" then $ocx > $cx
          elif $dir == "u" then $ocy < $cy
          else $ocy > $cy
          end
        )
      ] | length > 0
    ')
fi

if [ "$has_neighbor" == "true" ]; then
    exec hyprctl dispatch movefocus "$dir"
fi

# Current monitor is exhausted in this direction (blank, edge, or only
# window): jump to the adjacent monitor, if one exists.
# A monitor only counts as "in that direction" if it actually overlaps
# the current monitor on the perpendicular axis (like sway/i3's output
# focus) -- otherwise e.g. a monitor that's purely to the left but,
# due to differing scale/height, has its vertical CENTER below the
# current monitor's would wrongly count as "down".
target=$(jq -r --arg cur "$cur_name" --arg dir "$dir" '
  map({name, x0: .x, x1: (.x + .width/.scale), y0: .y, y1: (.y + .height/.scale),
       cx: (.x + .width/.scale/2), cy: (.y + .height/.scale/2)}) as $mons |
  ($mons[] | select(.name == $cur)) as $c |
  [$mons[] | select(.name != $cur)] as $others |
  (
    if $dir == "l" then [$others[] | select(.cx < $c.cx and .y0 < $c.y1 and .y1 > $c.y0)] | sort_by(-.cx)
    elif $dir == "r" then [$others[] | select(.cx > $c.cx and .y0 < $c.y1 and .y1 > $c.y0)] | sort_by(.cx)
    elif $dir == "u" then [$others[] | select(.cy < $c.cy and .x0 < $c.x1 and .x1 > $c.x0)] | sort_by(-.cy)
    else [$others[] | select(.cy > $c.cy and .x0 < $c.x1 and .x1 > $c.x0)] | sort_by(.cy)
    end
  )[0] // empty | if . == null then empty else [.name, (.cx|floor|tostring), (.cy|floor|tostring)] | @tsv end
' <<< "$mon_json")

[ -z "$target" ] && exit 0

IFS=$'\t' read -r target_name target_cx target_cy <<< "$target"

hyprctl --batch "dispatch focusmonitor $target_name ; dispatch movecursor $target_cx $target_cy"
