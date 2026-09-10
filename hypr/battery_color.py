#!/usr/bin/env python3
"""Waybar custom/battery module: reports capacity via upower.

Icon-only -- the percent and charge state select a "level-N-<state>" class,
which waybar/battery-icons-generated.css maps to the matching pre-rendered
gauge in waybar/icons/battery/ (see generate_battery_icons.py). No
percentage digit is baked into the icon; hover the module for the exact
number plus time-to-empty/full via the tooltip.
"""
import json
import re
import subprocess


def upower_info():
    devices = subprocess.check_output(["upower", "-e"]).decode().splitlines()
    device = next((d for d in devices if "battery" in d.lower()), None)
    if not device:
        return None
    return subprocess.check_output(["upower", "-i", device]).decode()


def parse(info):
    def find(pattern, default=None):
        m = re.search(pattern, info)
        return m.group(1).strip() if m else default

    pct = int(float(find(r"percentage:\s+(\d+(?:\.\d+)?)%", "0")))
    state = find(r"state:\s+(\S+)", "unknown")
    charging = state in ("charging", "pending-charge")
    time_to = find(r"time to (?:empty|full):\s+(.+)")
    power = find(r"energy-rate:\s+([\d.]+)")
    return pct, charging, state, time_to, power


def main():
    info = upower_info()
    if info is None:
        # A single space, not "" -- waybar hides a custom module outright if
        # its text is truly empty.
        print(json.dumps({"text": " ", "tooltip": "Battery: N/A"}))
        return

    pct, charging, state, time_to, power = parse(info)

    if time_to and power:
        detail = f"{time_to} — {power}W"
    elif time_to:
        detail = time_to
    else:
        detail = state.replace("-", " ").capitalize()
    tooltip = f"{pct}% — {detail}"

    # Exact percent, matching the pre-rendered icon set in icons/battery/
    # (see generate_battery_icons.py) -- the class name picks which
    # background-image CSS rule in battery-icons-generated.css applies.
    pct_clamped = min(100, max(0, pct))
    state_class = "charging" if charging else "discharging"

    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": tooltip,
        "class": f"level-{pct_clamped}-{state_class}",
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
