#!/usr/bin/env bash
# Usage: scroll.sh <start|stop> <down|up>
#
# ctrl+shift+j/k accelerating scroll, mirroring hammerspoon-init.lua's
# startScroll/stopScroll: holding the key ramps scroll speed
# exponentially (handled in scroll_loop.py), a quick re-tap in the same
# direction within TAP_WINDOW uses a faster REPEAT_TAP_SPEED, and
# terminals get a slower speed (TERMINAL_DIVISOR) since they scroll by
# whole lines.
#
# Bound in hyprland.conf as a start/stop pair per direction (bind =
# press -> start, bindr = release -> stop). All state lives in the PID
# of the one running scroll_loop.py: start hard-kills whatever loop is
# currently running (a new gesture always wins immediately, no grace
# period) before launching a fresh one; stop just SIGTERMs the current
# loop, which applies its own MIN_DURATION grace period before actually
# exiting.
set -euo pipefail

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNDIR/hypr_scroll.pid"
TAPFILE="$RUNDIR/hypr_scroll_tap"
LOOP="$(dirname "$(readlink -f "$0")")/scroll_loop.py"

BASE_SPEED=20
REPEAT_TAP_SPEED=100
TAP_WINDOW=0.2
TERMINAL_DIVISOR=2
# Window classes that scroll by whole lines rather than pixels.
TERMINAL_CLASS_RE='wezterm|kitty|alacritty|foot|ghostty|xterm|konsole'

action=$1
dir=$2

echo "$(date +%s.%N) $action $dir" >> /tmp/scroll_debug_invocations.log

case "$dir" in
    down) sign=-1 ;;
    up)   sign=1 ;;
    *) echo "scroll.sh: unknown direction '$dir'" >&2; exit 1 ;;
esac

if [[ "$action" == "stop" ]]; then
    if [[ -f "$PIDFILE" ]]; then
        kill -TERM "$(cat "$PIDFILE")" 2>/dev/null || true
    fi
    exit 0
fi

# action == start ------------------------------------------------------

now=$EPOCHREALTIME
speed=$BASE_SPEED
last_dir=""
last_time=0
if [[ -f "$TAPFILE" ]]; then
    read -r last_dir last_time < "$TAPFILE" || true
fi
if [[ "$last_dir" == "$dir" ]] && awk -v a="$now" -v b="$last_time" -v w="$TAP_WINDOW" 'BEGIN { exit !(a - b < w) }'; then
    speed=$REPEAT_TAP_SPEED
fi
echo "$dir $now" > "$TAPFILE"

divisor=1
class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class? // empty')
if [[ -n "$class" ]] && grep -qiE "$TERMINAL_CLASS_RE" <<< "$class"; then
    divisor=$TERMINAL_DIVISOR
fi

if [[ -f "$PIDFILE" ]]; then
    kill -9 "$(cat "$PIDFILE")" 2>/dev/null || true
fi

python3 "$LOOP" "$sign" "$speed" "$divisor" >/dev/null 2>&1 &
pid=$!
disown
echo "$pid" > "$PIDFILE"
