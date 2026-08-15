#!/usr/bin/env python3
"""Waybar custom/volume module: reports the default sink's volume via
`wpctl` and colors the label by flat bands (no blending):
    0%        -> grey   (@fg-muted)
    0-85%     -> green  (@green)
   85-100%    -> yellow (@yellow)
  100-130%    -> orange (@orange)
  130%+       -> red    (@pink)
Muted is shown in that same grey regardless of the actual level, as a
distinct "off" signal.

Color stops come from waybar/colors.css, a symlink toggled by
waybar/toggle_colors.sh between the active palette (colors-neon.css,
generated from palettes/*.toml by generate_colors.py) and a plain
white scheme (colors-mono.css) — so switching palettes, or toggling
mono mode, retints the volume module automatically.
"""
import json
import re
import subprocess
from pathlib import Path

COLORS_CSS = Path(__file__).resolve().parent.parent / "waybar" / "colors.css"
SINK = "@DEFAULT_AUDIO_SINK@"


def load_palette_colors():
    text = COLORS_CSS.read_text()
    colors = dict(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", text))
    return colors["fg-muted"], colors["green"], colors["yellow"], colors["orange"], colors["pink"]


def volume_color(pct, grey, green, yellow, orange, red):
    if pct <= 0:
        return grey
    if pct < 85:
        return green
    if pct < 100:
        return yellow
    if pct < 130:
        return orange
    return red


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
