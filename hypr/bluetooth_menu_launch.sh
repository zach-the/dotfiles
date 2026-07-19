#!/usr/bin/env python3
"""Waybar custom/bluetooth module on-click: opens bluetooth_menu.py in a
floating popup sized to how many rows it'll actually show. Unlike the
Wi-Fi menu, bluetoothctl's device listing is just reading cached state
(no active scan), so a quick pre-check before spawning is fine here —
same approach as audio_menu_launch.sh. See popup_launch.py for the
generic positioning/floating logic.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_launch

MIN_ROWS = 4
MAX_ROWS = 15
ROW_OVERHEAD = 3

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bluetooth_menu.py")


def row_count():
    out = subprocess.run(["python3", SCRIPT, "--count"], capture_output=True, check=True, text=True).stdout
    return int(out.strip() or 0)


if __name__ == "__main__":
    rows = max(MIN_ROWS, min(MAX_ROWS, ROW_OVERHEAD + max(row_count(), 1)))
    popup_launch.launch("bluetooth-menu", SCRIPT, rows)
