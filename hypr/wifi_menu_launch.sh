#!/usr/bin/env python3
"""Waybar network module on-click: opens wifi_menu.py in a floating
popup immediately (a Wi-Fi scan can take a couple seconds, so this
doesn't wait on one — wifi_menu.py opens with a "Loading" message and
resizes itself once results are in). See popup_launch.py for the
generic positioning/floating logic.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_launch

# Enough for the loading message and, once it resolves, the
# password-entry sub-screen (label + input + hint) even with few/no
# networks in range. wifi_menu.py resizes to fit the real count once
# known — its MIN_ROWS must match this value, since it's also used as
# the "how many rows were we actually spawned with" for that resize.
DEFAULT_ROWS = 6

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "wifi_menu.py")

if __name__ == "__main__":
    popup_launch.launch("wifi-menu", SCRIPT, DEFAULT_ROWS)
