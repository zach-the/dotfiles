#!/usr/bin/env python3
"""Waybar custom/mic module: icon-only mic glyph (see
generate_mic_icons.py), unmuted or muted -- no level rings (mic input
gain isn't something to gauge at a glance the way output volume is).
The exact percentage lives in the tooltip.
"""
import json
import re
import subprocess

SOURCE = "@DEFAULT_AUDIO_SOURCE@"


def get_volume():
    out = subprocess.run(["wpctl", "get-volume", SOURCE], capture_output=True, text=True, check=True).stdout
    m = re.search(r"([\d.]+)", out)
    pct = round(float(m.group(1)) * 100) if m else 0
    return pct, "MUTED" in out


def main():
    try:
        pct, muted = get_volume()
    except (subprocess.CalledProcessError, FileNotFoundError):
        print(json.dumps({"text": " ", "tooltip": "Mic: N/A"}))
        return

    tooltip = "Mic Muted" if muted else f"Mic: {pct}%"

    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": tooltip,
        "class": "muted" if muted else "mic",
        "percentage": pct,
    }))


if __name__ == "__main__":
    main()
