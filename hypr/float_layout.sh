#!/usr/bin/env python3
"""Snapshot or restore floating-window positions/sizes across a FLOAT <->
WIDE-TILE mode switch, so windows land back where you left them the next
time you return to FLOAT mode.

A window's WIDE-TILE geometry always wins when entering FLOAT for the
*first* time (or any time since it's had a saved float geometry that
still matches what was last applied to it). But once a window has been
manually moved/resized while in FLOAT, that customization is flagged
and its saved float geometry takes precedence over WIDE-TILE from then
on, on every future switch into FLOAT.

Matching is by window address, which only lives for the process's
lifetime — closing and reopening an app between snapshot and restore
means it won't match, and will just get whatever default position
Hyprland gives a freshly-floated window (and drops any "customized"
flag it had).

Usage:
  float_layout.sh save            snapshot every currently-floating
                                   window (except the special/scratchpad
                                   workspace) to the on-disk state file;
                                   flag any window whose geometry has
                                   drifted from what was applied on the
                                   last "enter" as customized, so its
                                   float geometry sticks from now on
  float_layout.sh snapshot-tiled  print a JSON snapshot of every
                                   currently-tiled window's geometry to
                                   stdout (used right before floating
                                   them, so the switch into FLOAT can
                                   look seamless)
  float_layout.sh enter           read a WIDE-TILE JSON snapshot (same
                                   shape as snapshot-tiled's output)
                                   from stdin. For each newly-floated
                                   window: apply its saved float
                                   geometry if it's been customized
                                   before, otherwise apply its WIDE-TILE
                                   geometry from stdin.
"""
import json
import subprocess
import sys
from pathlib import Path

STATE_FILE = Path.home() / ".config/hypr/float_layout.json"
APPLIED_FILE = Path.home() / ".config/hypr/float_layout_applied.json"
CUSTOMIZED_FILE = Path.home() / ".config/hypr/float_layout_customized.json"
SKIP_WORKSPACE_PREFIX = "special"
# Tolerance (px) for deciding a window's geometry has actually changed,
# vs. e.g. an app rounding the exact size/position we asked for.
DRIFT_TOLERANCE = 2


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, check=True, text=True).stdout
    return json.loads(out)


def load_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return default


def snapshot(floating):
    clients = hyprctl_json("clients")
    layout = {}
    for c in clients:
        if c.get("floating") != floating:
            continue
        if c.get("workspace", {}).get("name", "").startswith(SKIP_WORKSPACE_PREFIX):
            continue
        x, y = c["at"]
        w, h = c["size"]
        layout[c["address"]] = {"x": x, "y": y, "w": w, "h": h}
    return layout


def geo_matches(a, b):
    return all(abs(a[k] - b[k]) <= DRIFT_TOLERANCE for k in ("x", "y", "w", "h"))


def save():
    current = snapshot(floating=True)
    applied = load_json(APPLIED_FILE, {})
    customized = load_json(CUSTOMIZED_FILE, {})
    for addr, geo in current.items():
        baseline = applied.get(addr)
        if baseline is None or not geo_matches(geo, baseline):
            customized[addr] = True
    STATE_FILE.write_text(json.dumps(current))
    CUSTOMIZED_FILE.write_text(json.dumps(customized))


def snapshot_tiled():
    print(json.dumps(snapshot(floating=False)))


def apply_layout(layout):
    clients = hyprctl_json("clients")
    for c in clients:
        geo = layout.get(c["address"])
        if not geo or not c.get("floating"):
            continue
        addr = c["address"]
        subprocess.run(
            ["hyprctl", "dispatch", "resizewindowpixel", f"exact {geo['w']} {geo['h']},address:{addr}"],
            check=True,
        )
        subprocess.run(
            ["hyprctl", "dispatch", "movewindowpixel", f"exact {geo['x']} {geo['y']},address:{addr}"],
            check=True,
        )


def enter():
    try:
        tile_snapshot = json.loads(sys.stdin.read())
    except json.JSONDecodeError:
        tile_snapshot = {}
    saved = load_json(STATE_FILE, {})
    customized = load_json(CUSTOMIZED_FILE, {})

    layout = {}
    for addr, geo in tile_snapshot.items():
        if customized.get(addr) and addr in saved:
            layout[addr] = saved[addr]
        else:
            layout[addr] = geo
    # Windows with no WIDE-TILE geometry this round (e.g. spawned
    # directly into FLOAT) still get their customized float geometry
    # restored if they have one.
    for addr, geo in saved.items():
        if customized.get(addr) and addr not in layout:
            layout[addr] = geo

    apply_layout(layout)
    APPLIED_FILE.write_text(json.dumps(layout))


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("save", "snapshot-tiled", "enter"):
        raise SystemExit(__doc__)
    {
        "save": save,
        "snapshot-tiled": snapshot_tiled,
        "enter": enter,
    }[sys.argv[1]]()


if __name__ == "__main__":
    main()
