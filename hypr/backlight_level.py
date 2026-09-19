#!/usr/bin/env python3
"""Waybar custom/backlight module: icon-only sun glyph (see
generate_backlight_icons.py) that grows more rays as brightness increases.
No percentage baked in -- the exact number lives in the tooltip.

Shows the brightness of whichever monitor the mouse is on, the same one the
scroll/XF86 bindings in config.jsonc/hyprland.conf adjust (see
brightness.py). The built-in panel is read through brightnessctl's -e4
exponential curve rather than the raw linear percentage, so the tooltip
number and the tier thresholds track what a "10%" adjustment actually felt
like. External monitors report their DDC value (cached, so this stays fast).
"""
import json

from brightness import percent as brightness_percent


def tier_for(pct):
    # One tier per 10%-wide band, same convention as volume_color.py and
    # wifi_signal.py, matched to the 10%-per-click scroll step in
    # config.jsonc.
    return min(10, pct // 10 + 1)


def main():
    pct = brightness_percent()
    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": f"Screen: {pct}%",
        "class": f"tier{tier_for(pct)}",
    }))


if __name__ == "__main__":
    main()
