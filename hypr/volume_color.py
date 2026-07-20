#!/usr/bin/env python3
"""Waybar custom/volume module: reports the default sink's volume via
`wpctl` and colors the label along a grey -> green -> yellow -> orange ->
red curve, mixed in OKLab the same way custom/battery does — see
color_gradient.py.

Color stops come from waybar/colors.css (generated from the active
palettes/*.toml by generate_colors.py), so switching palettes retints
the volume gradient automatically:
    0% -> grey/muted  (@fg-muted)
   60% -> green       (@green), ramp from grey ends here
  100% -> green       (@green), solid from 60% to here
  120% -> yellow      (@yellow), full strength
  135% -> orange      (@orange), full strength
  150% -> red         (@pink), full strength from here up
Muted is shown in that same 0% grey regardless of the actual level, as
a distinct "off" signal.
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
SINK = "@DEFAULT_AUDIO_SINK@"


def load_palette_colors():
    text = COLORS_CSS.read_text()
    colors = dict(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", text))
    return colors["fg-muted"], colors["green"], colors["yellow"], colors["orange"], colors["pink"]


def volume_color(pct, grey, green, yellow, orange, red):
    return gradient_color(pct, [(0, grey), (60, green), (100, green), (120, yellow), (135, orange), (150, red)])


def get_volume():
    out = subprocess.run(["wpctl", "get-volume", SINK], capture_output=True, text=True, check=True).stdout
    m = re.search(r"([\d.]+)", out)
    pct = round(float(m.group(1)) * 100) if m else 0
    return pct, "MUTED" in out


def main():
    try:
        pct, muted = get_volume()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(json.dumps({"text": "Volume: N/A"}))
        return

    grey, green, yellow, orange, red = load_palette_colors()
    color = grey if muted else volume_color(pct, grey, green, yellow, orange, red)
    label = "Muted" if muted else f"Volume: {pct}%"

    print(json.dumps({
        "text": f"<span foreground='{color}'>{label}</span>",
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
