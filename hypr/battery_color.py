#!/usr/bin/env python3
"""Waybar custom/battery module: reports capacity via upower and colors
the label along a green -> yellow -> red curve, mixed in OKLab so the
gradient stays perceptually smooth instead of drifting through the
muddy tones a plain sRGB lerp produces between unrelated hues.

Color stops come from waybar/colors.css (generated from the active
palettes/*.toml by generate_colors.py), so switching palettes retints
the battery gradient automatically:
  100% -> green   (@green)
   30% -> yellow  (@yellow), full strength
   20% -> orange  (@orange), full strength
   10% -> red     (@pink), full strength from here to 0%
While charging, the level isn't urgent regardless of percentage, so
the color is pinned to green.
"""
import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from color_gradient import gradient_color

COLORS_CSS = Path(__file__).resolve().parent.parent / "waybar" / "colors.css"


def load_palette_colors():
    text = COLORS_CSS.read_text()
    colors = dict(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", text))
    return colors["green"], colors["yellow"], colors["orange"], colors["pink"]


def battery_color(pct, green, yellow, orange, red):
    return gradient_color(pct, [(0, red), (10, red), (20, orange), (30, yellow), (100, green)])


# --- upower ---

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
        print(json.dumps({"text": "Battery: N/A"}))
        return

    pct, charging, state, time_to, power = parse(info)
    green, yellow, orange, red = load_palette_colors()
    color = green if charging else battery_color(pct, green, yellow, orange, red)

    label = "Charging" if charging else "Battery"
    text = f"<span foreground='{color}'>{label}: {pct}%</span>"

    if time_to and power:
        tooltip = f"{time_to} — {power}W"
    elif time_to:
        tooltip = time_to
    else:
        tooltip = state.replace("-", " ").capitalize()

    print(json.dumps({
        "text": text,
        "tooltip": tooltip,
        "class": "charging" if charging else "discharging",
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
