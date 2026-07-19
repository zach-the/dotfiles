#!/usr/bin/env python3
"""Shared launcher: opens a script in a floating wezterm popup, positioned
just under the cursor (i.e. wherever the waybar module actually is on
screen right now — using the click location sidesteps having to know
waybar's module layout/widths) on whichever monitor the cursor is on.

Positioned from its very first frame via Hyprland's inline `exec
[rules]` syntax (dispatching through hyprctl rather than spawning the
process ourselves directly), rather than spawning at Hyprland's default
placement and moving it after the fact — the latter visibly popped in
at the center of the screen and then jumped to its real spot. This
means we need an estimate of the popup's pixel size before it exists to
compute where its edges will land; PX_PER_COL/PX_PER_ROW below are
measured empirically from this font/DPI setup (JetBrainsMono Nerd Font
Mono, wezterm's default cell metrics on this monitor) — if you change
the terminal font or hit a monitor with very different DPI, re-measure.

For a popup that doesn't know its real size until after an async query
resolves (e.g. wifi_menu.py's network scan), resizing the live window
in place proved unreliable — hyprctl would report the resize/reposition
as having landed correctly, but it would render overlapping the bar
regardless. respawn() sidesteps that: close the placeholder-sized popup
and open a fresh one at the right size, through the same frame-1
positioning path that's never shown that problem.

Disables focus-follows-mouse for the popup's lifetime: the popup closes
itself when a different window becomes active (see popup_common.py),
and with follow_mouse on, merely hovering off it (not clicking) would
trigger that. Acquired/released through popup_common's refcounted
lock rather than a plain read-modify-restore here, since two of these
popups can be open at once (see popup_common.acquire_follow_mouse for
why that matters). Since dispatching through `exec` doesn't inherit
our own Python process's environment the way subprocess.Popen(env=...)
would, the value to restore on close (and anything else the popup
needs from us) is passed as a CLI argument instead — see
popup_common.parse_restore_arg().
"""
import json
import shlex
import subprocess
import time

import popup_common

COLS = 40
PX_PER_COL = 9
PX_PER_ROW = 20


def hyprctl(*args):
    subprocess.run(["hyprctl", *args], capture_output=True, check=True)


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, check=True, text=True).stdout
    return json.loads(out)


def logical_size(mon):
    # hyprctl monitors reports width/height in physical pixels but x/y
    # (and everything window-related: "at", "size", cursorpos) in
    # logical, scale-divided pixels — mixing the two silently inflates
    # the monitor's apparent bounds and lets popups render off-screen.
    return mon["width"] / mon["scale"], mon["height"] / mon["scale"]


def find_monitor(x, y, monitors):
    for m in monitors:
        w, h = logical_size(m)
        if m["x"] <= x < m["x"] + w and m["y"] <= y < m["y"] + h:
            return m
    return monitors[0]


def clamp_to_monitor(mon, x, y, w, h):
    mon_w, mon_h = logical_size(mon)
    res_l, res_t, res_r, res_b = mon["reserved"]
    x = min(x, mon["x"] + mon_w - res_r - w - 8)
    x = max(x, mon["x"] + res_l + 8)
    y = min(y, mon["y"] + mon_h - res_b - h - 8)
    y = max(y, mon["y"] + res_t + 4)
    return x, y


def _spawn_positioned(class_name, cmd_tail, rel_x, rel_y, rows, cols=COLS):
    """Spawn `cmd_tail` (argv after wezterm's own options) via `hyprctl
    dispatch exec` with an inline float+move rule so it's positioned
    from its first frame, wait for the resulting window to appear, and
    focus it (dispatch-exec-spawned windows don't reliably auto-focus
    the way a directly-Popen'd process's window does). Returns the new
    window's address, or None if it never appeared."""
    existing = {c["address"] for c in hyprctl_json("clients") if c.get("class") == class_name}

    cmd = [
        "wezterm",
        "--config", f"initial_cols={cols}",
        "--config", f"initial_rows={rows}",
        "start", "--class", class_name,
        "--", *cmd_tail,
    ]
    exec_str = f"[float;move {rel_x} {rel_y}] " + shlex.join(cmd)
    subprocess.run(["hyprctl", "dispatch", "exec", exec_str], capture_output=True, check=True)

    addr = None
    for _ in range(50):
        time.sleep(0.1)
        clients = hyprctl_json("clients")
        found = next((c for c in clients if c.get("class") == class_name and c["address"] not in existing), None)
        if found:
            addr = found["address"]
            break
    if addr:
        hyprctl("dispatch", "focuswindow", f"address:{addr}")
    return addr


def launch(class_name, script_path, rows):
    original_follow_mouse = popup_common.acquire_follow_mouse()

    cx, cy = (
        int(v)
        for v in subprocess.run(["hyprctl", "cursorpos"], capture_output=True, check=True, text=True)
        .stdout.strip()
        .split(",")
    )
    monitors = hyprctl_json("monitors")
    mon = find_monitor(cx, cy, monitors)
    base_y = mon["y"] + mon["reserved"][1] + 4

    est_w, est_h = COLS * PX_PER_COL, rows * PX_PER_ROW
    # Center the popup on the click point rather than anchoring its left
    # edge there — otherwise the whole popup falls to the right of
    # wherever you clicked in the module instead of looking centered
    # under it.
    target_x, target_y = clamp_to_monitor(mon, cx - est_w / 2, base_y, est_w, est_h)
    # windowrule `move` (used via the inline exec rule) is
    # monitor-relative, unlike movewindowpixel's absolute coordinates.
    rel_x, rel_y = round(target_x - mon["x"]), round(target_y - mon["y"])

    cmd_tail = ["python3", script_path, "--restore-follow-mouse", original_follow_mouse]
    addr = _spawn_positioned(class_name, cmd_tail, rel_x, rel_y, rows)
    if not addr:
        # Nothing will be around to release our acquire_follow_mouse()
        # call above, so do it here.
        popup_common.restore_follow_mouse(original_follow_mouse)


def respawn(class_name, script_path, extra_args, rows, anchor_x, anchor_y):
    """Open a fresh popup of the same class at (anchor_x, anchor_y) — the
    exact position an existing instance of it is already sitting at —
    sized for `rows`, then focus it. Used when a popup needs to grow
    once it learns its real content size (see module docstring for why
    this replaces resizing the live window). Does NOT touch
    follow_mouse or query the live cursor position — the caller is
    responsible for passing its own --restore-follow-mouse value
    through `extra_args` so the replacement inherits it, and the cursor
    may well have moved since the original click, so anchor_x/y (the
    existing popup's own current position) is the more correct
    reference point here. Returns the new window's address."""
    monitors = hyprctl_json("monitors")
    mon = find_monitor(anchor_x, anchor_y, monitors)
    est_h = rows * PX_PER_ROW
    _, target_y = clamp_to_monitor(mon, anchor_x, anchor_y, COLS * PX_PER_COL, est_h)
    rel_x, rel_y = round(anchor_x - mon["x"]), round(target_y - mon["y"])

    cmd_tail = ["python3", script_path, *extra_args]
    return _spawn_positioned(class_name, cmd_tail, rel_x, rel_y, rows)
