#!/usr/bin/env python3
"""Snapshot or restore floating-window positions/sizes across a FLOAT <->
WIDE-TILE mode switch, so windows land back where you left them the next
time you return to FLOAT mode. Tiled modes have no equivalent state to
save — the layout algorithm (dwindle/ultrawide-dwindle-improved) owns
window position/size there, so there's nothing manual to snapshot.

Matching is by window address, which only lives for the process's
lifetime — closing and reopening an app between snapshot and restore
means it won't match, and will just get whatever default position
Hyprland gives a freshly-floated window.

Usage:
  float_layout.sh save     snapshot every currently-floating window
                            (except the special/scratchpad workspace)
  float_layout.sh restore  reposition/resize any currently-floating
                            window that has a saved snapshot
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


def save():
    clients = hyprctl_json("clients")
    layout = {}
    for c in clients:
        if not c.get("floating"):
            continue
        if c.get("workspace", {}).get("name", "").startswith(SKIP_WORKSPACE_PREFIX):
            continue
        x, y = c["at"]
        w, h = c["size"]
        layout[c["address"]] = {"x": x, "y": y, "w": w, "h": h}
    STATE_FILE.write_text(json.dumps(layout))


def restore():
    if not STATE_FILE.exists():
        return
    try:
        layout = json.loads(STATE_FILE.read_text())
    except json.JSONDecodeError:
        return

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


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("save", "restore"):
        raise SystemExit(__doc__)
    if sys.argv[1] == "save":
        save()
    else:
        restore()


if __name__ == "__main__":
    main()
