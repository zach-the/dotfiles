#!/usr/bin/env python3
"""Waybar custom/backlight module: icon-only sun glyph (see
generate_backlight_icons.py) that grows more rays as brightness increases.
No percentage baked in -- the exact number lives in the tooltip.

Reads brightness through brightnessctl's own -e4 exponential curve (the
same one the scroll/XF86 key bindings in config.jsonc/hyprland.conf set
through), rather than the raw linear percentage -- so the tooltip number
and the tier thresholds both track what a "10%" adjustment actually felt
like, not the linear fraction of max brightness.
"""
import json
import subprocess


def brightness_percent():
    out = subprocess.check_output(["brightnessctl", "-e4", "-m"]).decode().strip()
    # device,class,current,percent%,max -- percent here is already on the
    # exponential curve because of -e4.
    return int(out.split(",")[3].rstrip("%"))


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
