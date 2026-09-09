#!/usr/bin/env python3
"""Waybar custom/wifi module: a 10-tier signal-strength glyph. Icon-only (no
percentage baked in, see waybar/generate_wifi_icons.py) -- the tier picks a
"tierN" class, which waybar/wifi-icons-generated.css maps to the matching
background-image.

Any time there's no active wifi connection -- radio off, or radio on but
not associated with a network (e.g. on ethernet instead) -- this shows the
same dimmed+struck-through "off" icon (see generate_wifi_icons.py's
OFF_SHAPES) rather than hiding the module, so something's always visible;
the tooltip still distinguishes the two cases.
"""
import json
import re
import subprocess


def _split_terse(line):
    # nmcli -t escapes literal ':' as '\:' and '\' as '\\' within a field
    fields = re.split(r"(?<!\\):", line)
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in fields]


def active_wifi():
    out = subprocess.run(
        ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL", "device", "wifi", "list"],
        capture_output=True, text=True,
    ).stdout
    for line in out.splitlines():
        fields = _split_terse(line)
        if len(fields) < 3:
            continue
        in_use, ssid, signal = fields[0], fields[1], fields[2]
        if in_use.strip() == "*":
            return ssid, int(signal)
    return None


def tier_for(signal):
    # One tier per 10%-wide band, same convention as volume_color.py and
    # backlight_level.py.
    return min(10, signal // 10 + 1)


def radio_enabled():
    out = subprocess.run(["nmcli", "radio", "wifi"], capture_output=True, text=True).stdout
    return out.strip() == "enabled"


def main():
    if not radio_enabled():
        print(json.dumps({"text": " ", "tooltip": "WiFi: Off", "class": "off"}))
        return

    active = active_wifi()
    if active is None:
        print(json.dumps({"text": " ", "tooltip": "WiFi: Not Connected", "class": "off"}))
        return

    ssid, signal = active
    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": f"{ssid} — {signal}%",
        "class": f"tier{tier_for(signal)}",
    }))


if __name__ == "__main__":
    main()
