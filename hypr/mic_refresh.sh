#!/bin/bash
# Debounced waybar refresh trigger for custom/mic: call this after every
# mic volume/mute change instead of signaling waybar directly. Same
# debounce reasoning as volume_refresh.sh -- a whole scroll burst costs
# one refresh instead of one per tick.
GEN_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar-mic-refresh.gen"

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
    [ "$current" = "$gen" ] && pkill -RTMIN+16 waybar
) & disown
