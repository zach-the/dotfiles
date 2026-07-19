#!/usr/bin/env python3
"""Waybar pulseaudio module on-click: opens audio_menu.py in a floating
popup sized to how many sinks it'll actually show. See popup_launch.py
for the generic positioning/floating logic.
"""
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_launch

MIN_ROWS = 4
MAX_ROWS = 15
# header + blank spacer + bottom padding, around however many sink rows
# audio_menu.py will actually draw
ROW_OVERHEAD = 3

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "audio_menu.py")


def sink_count():
    out = subprocess.run(["python3", SCRIPT, "--count"], capture_output=True, check=True, text=True).stdout
    return int(out.strip() or 0)


if __name__ == "__main__":
    rows = max(MIN_ROWS, min(MAX_ROWS, ROW_OVERHEAD + max(sink_count(), 1)))
    popup_launch.launch("audio-menu", SCRIPT, rows)
