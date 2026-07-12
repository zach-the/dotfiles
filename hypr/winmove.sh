#!/usr/bin/env python3
"""Move/resize the focused floating window to a fractional region of its
monitor, mirroring the mac halves/corners/thirds binds from
hammerspoon-init.lua's move()/third()/twoThirds() functions.

Usage:
  winmove.sh X Y W H        fractions 0..1 of monitor width/height
  winmove.sh third N        aspect-aware thirds (N=1,2,3)
  winmove.sh twothirds N    aspect-aware two-thirds (N=1,2)
"""
import json
import subprocess
import sys

GAP_OUT = 10  # matches gaps_out in hyprland.conf
GAP_IN = 5    # matches gaps_in in hyprland.conf


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, check=True, text=True).stdout
    return json.loads(out)


def active_monitor():
    ws = hyprctl_json("activeworkspace")
    mon_name = ws["monitor"]
    for m in hyprctl_json("monitors"):
        if m["name"] == mon_name:
            return m
    raise SystemExit(f"monitor {mon_name} not found")


def thirds_rect(mode, n, portrait):
    if mode == "third":
        size = 1 / 3
        off = (n - 1) / 3
    else:
        size = 2 / 3
        off = 0.0 if n == 1 else 1 / 3
    if portrait:
        return 0.0, off, 1.0, size
    return off, 0.0, size, 1.0


def main():
    args = sys.argv[1:]
    if not args:
        raise SystemExit(__doc__)

    mon = active_monitor()
    mw = mon["width"] / mon["scale"]
    mh = mon["height"] / mon["scale"]
    mx, my = mon["x"], mon["y"]

    # Shrink the usable area by whatever layer-shell surfaces (waybar)
    # have reserved, so windows never sit under the bar.
    res_l, res_t, res_r, res_b = mon["reserved"]
    mx += res_l
    my += res_t
    mw -= res_l + res_r
    mh -= res_t + res_b

    if args[0] in ("third", "twothirds"):
        n = int(args[1])
        portrait = mh > mw
        x, y, w, h = thirds_rect(args[0], n, portrait)
    else:
        x, y, w, h = (float(a) for a in args[:4])

    fx = mx + mw * x
    fy = my + mh * y
    fw = mw * w
    fh = mh * h

    # Smart gaps, matching dwindle: outer screen edges get the full
    # gaps_out; shared inner edges get the full gaps_in on EACH side
    # (so two adjacent windows end up 2*gaps_in apart, same as tiled).
    if x <= 0.0:
        fx += GAP_OUT
        fw -= GAP_OUT
    else:
        fx += GAP_IN
        fw -= GAP_IN
    if x + w >= 0.999:
        fw -= GAP_OUT
    else:
        fw -= GAP_IN

    if y <= 0.0:
        fy += GAP_OUT
        fh -= GAP_OUT
    else:
        fy += GAP_IN
        fh -= GAP_IN
    if y + h >= 0.999:
        fh -= GAP_OUT
    else:
        fh -= GAP_IN

    # hyprctl dispatch takes each dispatcher's args as a single string,
    # not separate argv items; moveresizeactive doesn't exist on this
    # Hyprland version (0.55.2), so use moveactive + resizeactive.
    # Resize first: `resizeactive exact` anchors the resize at the
    # window's CURRENT center, so doing it before the move means the
    # subsequent moveactive (an absolute top-left, independent of size)
    # lands exactly where we want regardless of where the resize
    # center happened to be.
    subprocess.run(
        ["hyprctl", "dispatch", "resizeactive", f"exact {int(fw)} {int(fh)}"],
        check=True,
    )
    subprocess.run(
        ["hyprctl", "dispatch", "moveactive", f"exact {int(fx)} {int(fy)}"],
        check=True,
    )


if __name__ == "__main__":
    main()
