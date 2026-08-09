#!/usr/bin/env python3
"""Snapshot or restore floating-window positions/sizes across a FLOAT <->
WIDE-TILE mode switch, so windows land back where you left them the next
time you return to FLOAT mode.

Matching is by window address, which only lives for the process's
lifetime — closing and reopening an app between snapshot and restore
means it won't match, and will just get whatever default position
Hyprland gives a freshly-floated window.

Usage:
  float_layout.sh save            snapshot every currently-floating
                                   window (except the special/scratchpad
                                   workspace) to the on-disk state file
  float_layout.sh restore         reposition/resize any currently-
                                   floating window that has a snapshot
                                   in the on-disk state file
  float_layout.sh snapshot-tiled  print a JSON snapshot of every
                                   currently-tiled window's geometry to
                                   stdout (used right before floating
                                   them, so the switch into FLOAT can
                                   look seamless)
  float_layout.sh apply           read a JSON snapshot (same shape as
                                   above) from stdin and apply it to any
                                   currently-floating window it matches
"""
import json
import subprocess
import sys
from pathlib import Path

STATE_FILE = Path.home() / ".config/hypr/float_layout.json"
SKIP_WORKSPACE_PREFIX = "special"


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, check=True, text=True).stdout
    return json.loads(out)


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


def save():
    STATE_FILE.write_text(json.dumps(snapshot(floating=True)))


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


def restore():
    if not STATE_FILE.exists():
        return
    try:
        layout = json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return
    apply_layout(layout)


def apply_stdin():
    try:
        layout = json.loads(sys.stdin.read())
    except json.JSONDecodeError:
        return
    apply_layout(layout)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("save", "restore", "snapshot-tiled", "apply"):
        raise SystemExit(__doc__)
    {
        "save": save,
        "restore": restore,
        "snapshot-tiled": snapshot_tiled,
        "apply": apply_stdin,
    }[sys.argv[1]]()


if __name__ == "__main__":
    main()
