#!/usr/bin/env bash
# hyprlock is the de facto login screen on this machine (greetd autologins
# straight into Hyprland, no interactive greeter). hyprlock's PAM thread makes
# ONE automatic auth attempt the instant it starts - at boot, before anyone's
# positioned in front of the camera - which fails and then blocks waiting on
# the password prompt. Nothing re-triggers Howdy after that on its own (same
# mechanism as the lid-close/lid-open case in lid.sh). A synthetic Enter
# resubmits the (empty) password field, which unblocks that stale attempt and
# lets hyprlock's retry loop try Howdy again now that someone's actually
# looking.
#
# Unlike the lid-open case, hyprlock's first attempt is actively IN PROGRESS
# when this script starts (not already parked and blocked), and Howdy's
# configured timeout is 6s, so we wait longer than that before sending the
# synthetic Enter - otherwise we'd submit while Howdy's first attempt is
# still running, which does nothing useful.

for i in $(seq 1 50); do
  pgrep -x hyprlock >/dev/null && break
  sleep 0.1
done

sleep 7

wtype -k Return
