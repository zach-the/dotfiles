#!/usr/bin/env python3
"""Ramped scroll-wheel loop for ctrl+shift+j/k, invoked by scroll.sh.

Mirrors hammerspoon-init.lua's startScroll/stopScroll: emits synthetic
scroll-wheel ticks at ~60Hz whose magnitude ramps exponentially from 1x
to MAX_MULT over RAMP_SECS while the key is held. scroll.sh launches one
of these per keypress and SIGTERMs it on release; SIGTERM is caught here
(rather than left as the default kill) so a quick tap still animates for
at least MIN_DURATION instead of visibly snapping to nothing, while a
fresh keypress (scroll.sh SIGKILLs the previous loop before starting a
new one) cuts off immediately with no such grace period.

Usage: scroll_loop.py <sign:1|-1> <speed> <divisor>
"""
import signal

# Registered before any other import: a SIGTERM landing in the gap between
# process launch and this line would fall back to the default kill action
# and skip the MIN_DURATION grace period below entirely, so this has to be
# the very first thing the interpreter does.
stopping = False


def request_stop(signum, frame):
    global stopping
    stopping = True


signal.signal(signal.SIGTERM, request_stop)

import math
import subprocess
import sys
import time

MAX_MULT = 60
RAMP_SECS = 3.0
TICK = 1 / 60
MIN_DURATION = 0.15

sign, speed, divisor = int(sys.argv[1]), float(sys.argv[2]), float(sys.argv[3])

start = time.monotonic()
tick = 0
while True:
    now = time.monotonic()
    elapsed = now - start
    if stopping and elapsed >= MIN_DURATION:
        break

    mult = MAX_MULT ** (min(elapsed, RAMP_SECS) / RAMP_SECS)
    amount = math.floor(sign * speed * mult / divisor)
    if amount != 0:
        subprocess.run(["wlrctl", "pointer", "scroll", str(amount), "0"])

    tick += 1
    sleep_for = (start + tick * TICK) - time.monotonic()
    if sleep_for > 0:
        time.sleep(sleep_for)
