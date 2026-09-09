#!/usr/bin/env python3
"""Waybar custom/battery module: reports capacity via upower.

Icon-only -- the percent and charge state select a "<prefix>-N-<state>"
class, which waybar/battery-icons-generated.css maps to the matching
pre-rendered gauge in waybar/icons/battery/ (see generate_battery_icons.py).
Hover the module for exact time-to-empty/full via the tooltip.

generate_battery_icons.py renders two parallel sets of gauges -- "pct" ones
with the percentage knocked out inside the fill, and "plain" ones that are
just the outline+fill with no digit. Clicking the module
(battery_toggle.sh) toggles which set this script picks its class prefix
from, tracked by whether SHOW_PCT_FILE exists.
"""
import json
import re
import subprocess
from pathlib import Path

SHOW_PCT_FILE = Path.home() / ".config" / "hypr" / "battery_show_pct"


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
        tooltip = f"{time_to} — {power}W"
    elif time_to:
        tooltip = time_to
    else:
        tooltip = state.replace("-", " ").capitalize()

    # Exact percent, matching the pre-rendered icon set in icons/battery/
    # (see generate_battery_icons.py) -- the class name picks which
    # background-image CSS rule in battery-icons-generated.css applies.
    pct_clamped = min(100, max(0, pct))
    state_class = "charging" if charging else "discharging"
    prefix = "pct" if SHOW_PCT_FILE.exists() else "plain"

    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": tooltip,
        "class": f"{prefix}-{pct_clamped}-{state_class}",
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
