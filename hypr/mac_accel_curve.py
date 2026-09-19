#!/usr/bin/env python3
"""
Print a Hyprland `accel_profile = custom ...` line approximating macOS pointer
acceleration: an S-shaped (logistic) gain that is ~G_MIN at slow speeds and
rises toward G_MAX for fast flicks.

NOT measured from macOS -- Apple doesn't publish the curve. Tune the knobs
below by feel.

libinput custom profile: points are output speed f(x) at input speeds
x = 0, STEP, 2*STEP, ... (device units/ms; NOT normalized to 1000dpi, so the
right values depend on the device's DPI). Gain is f(x)/x; f(x)=x is "no accel".

Usage:
  ./mac_accel_curve.py            # print the hyprland.conf line + a gain table
  ./mac_accel_curve.py --apply    # also apply live via hyprctl (until reload)
"""
import math
import subprocess
import sys

DEVICE = "ps/2-generic-mouse"

G_MIN = 0.0    # gain at very slow speeds (fine positioning)
G_MAX = 4.0    # gain cap for fast flicks
V_MID = 5.5    # input speed (units/ms) where gain is halfway between min and max
WIDTH = 1.8    # curve steepness; smaller = sharper knee
STEP = 0.4     # spacing of points along the x axis (units/ms)
N = 40         # number of points (libinput allows up to 64)


def gain(v):
    return G_MIN + (G_MAX - G_MIN) / (1 + math.exp(-(v - V_MID) / WIDTH))


def points():
    return [(i * STEP) * gain(i * STEP) for i in range(N)]


def main():
    pts = points()
    profile = f"custom {STEP} " + " ".join(f"{p:.3f}" for p in pts)
    print(f"accel_profile = {profile}\n")
    print("speed(units/ms)  gain")
    for i in range(0, N, 4):
        x = i * STEP
        print(f"{x:14.1f}  {gain(x):5.2f}")
    if "--apply" in sys.argv:
        subprocess.run(
            ["hyprctl", "keyword", f"device[{DEVICE}]:accel_profile", profile],
            check=True,
        )


if __name__ == "__main__":
    main()
