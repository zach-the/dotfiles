#!/usr/bin/env python3
"""Waybar custom/volume module: icon-only speaker glyph (see
generate_volume_icons.py) with rings that grow as volume increases. No
percentage baked in -- the exact number (or "Muted") lives in the tooltip.
"""
import json
import re
import subprocess

SINK = "@DEFAULT_AUDIO_SINK@"


def get_volume():
    out = subprocess.run(["wpctl", "get-volume", SINK], capture_output=True, text=True, check=True).stdout
    m = re.search(r"([\d.]+)", out)
    pct = round(float(m.group(1)) * 100) if m else 0
    return pct, "MUTED" in out


def main():
    try:
        pct, muted = get_volume()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(json.dumps({"text": " ", "tooltip": "Volume: N/A"}))
        return

    if muted:
        icon_class = "muted"
    elif pct <= 0:
        icon_class = "vol0"
    elif pct <= 100:
        # One tier per 10% band, matched to the 10%-per-click scroll/button
        # step in config.jsonc so every click grows or shrinks the arc.
        icon_class = f"tier{min(10, pct // 10 + 1)}"
    else:
        # Boosted past 100% (wpctl's --limit 1.5 allows up to 150%) -- the
        # red over1..5 icons, one per 10% band from 100-150%.
        icon_class = f"over{min(5, -(-(pct - 100) // 10))}"

    tooltip = "Muted" if muted else f"Volume: {pct}%"

    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": tooltip,
        "class": icon_class,
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
