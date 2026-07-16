#!/usr/bin/env python3
"""Send the focused window to the back of the z-stack, then focus whichever
window is now topmost on the same workspace.

hyprctl's client list order mirrors Hyprland's internal window stack (the
same vector alterzorder rotates), so the last entry for a workspace is
whatever's now rendered on top once the active window is sent to the back.
"""
import json
import subprocess


def hyprctl_json(*args):
    out = subprocess.run(["hyprctl", "-j", *args], capture_output=True, check=True, text=True).stdout
    return json.loads(out)


def main():
    active = hyprctl_json("activewindow")
    if not active:
        return
    addr = active["address"]
    ws_id = active["workspace"]["id"]

    subprocess.run(["hyprctl", "dispatch", "alterzorder", "bottom"], check=True)

    clients = hyprctl_json("clients")
    candidates = [
        c for c in clients
        if c["workspace"]["id"] == ws_id and c["mapped"] and c["address"] != addr
    ]
    if candidates:
        top_addr = candidates[-1]["address"]
        subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{top_addr}"], check=True)


if __name__ == "__main__":
    main()
