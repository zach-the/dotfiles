#!/bin/bash
# Debounced waybar refresh trigger for custom/volume: call this after every
# volume/mute change instead of signaling waybar directly. A full refresh
# means waybar re-execs volume_color.py (python startup + a `wpctl
# get-volume` subprocess, ~40ms) — cheap once, but signaling on every
# single scroll-wheel tick let rapid scrolling queue up enough of these to
# visibly lag. Rapid repeated calls here instead collapse into a single
# signal sent shortly after the last one, so a whole scroll burst costs
# one refresh instead of one per tick. The actual volume change (the wpctl
# call before this script runs) is never delayed by this — only the
# on-screen label catches up a beat late.
GEN_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar-volume-refresh.gen"

# flock-guarded so truly concurrent ticks (a fast scroll burst can fire
# several within the same few ms) can't race the read-modify-write and
# both land on the same "next" generation, which would let more than one
# through and defeat the debounce.
exec 9>"$GEN_FILE.lock"
flock 9
gen=$(( $(cat "$GEN_FILE" 2>/dev/null || echo 0) + 1 ))
echo "$gen" > "$GEN_FILE"
flock -u 9

(
    sleep 0.15
    exec 9>"$GEN_FILE.lock"
    flock 9
    current=$(cat "$GEN_FILE" 2>/dev/null)
    flock -u 9
    [ "$current" = "$gen" ] && pkill -RTMIN+10 waybar
) & disown
