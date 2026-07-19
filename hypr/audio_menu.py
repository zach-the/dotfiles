#!/usr/bin/env python3
"""Curses popup listing WirePlumber audio output sinks (via `wpctl`).
Purely mouse-driven: click a device to make it the default output, or
click anywhere outside this window to dismiss it.
Launched by audio_menu_launch.sh, which waybar's pulseaudio module
on-click runs. Shared popup plumbing (focus-watching, follow_mouse
handling) lives in popup_common.py.
"""
import curses
import os
import re
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_common

CLASS = "audio-menu"


def get_unavailable_sink_ids():
    """Sink IDs whose active port reports jack-sensed 'not available' (e.g.
    HDMI with no display attached, headphone jack with nothing plugged
    in). Ports with no sensing capability (built-in speakers) report
    'availability unknown' and are never treated as unavailable."""
    try:
        out = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True, check=True).stdout
    except Exception:
        return set()

    unavailable = set()
    for block in re.split(r"(?m)^Sink #", out)[1:]:
        id_match = re.match(r"(\d+)", block)
        active_match = re.search(r"Active Port:\s*(.+)", block)
        if not id_match or not active_match:
            continue
        port_line = re.search(re.escape(active_match.group(1).strip()) + r":.*\(([^)]*)\)", block)
        if port_line and "not available" in port_line.group(1):
            unavailable.add(id_match.group(1))
    return unavailable


def get_sinks():
    out = subprocess.run(["wpctl", "status"], capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == "Audio"), None)
    if start is None:
        return []
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() == "Video"), len(lines))
    audio_lines = lines[start:end]

    unavailable = get_unavailable_sink_ids()

    sinks = []
    in_sinks = False
    for line in audio_lines:
        stripped = line.strip()
        if stripped.endswith("Sinks:"):
            in_sinks = True
            continue
        if in_sinks and (stripped.endswith("Sources:") or stripped.endswith("Filters:")):
            break
        if in_sinks:
            m = re.match(r"^[│\s]*(\*)?\s*(\d+)\.\s+(.*?)\s*\[vol:", stripped)
            if m and m.group(2) not in unavailable:
                sinks.append({"id": m.group(2), "name": m.group(3).strip(), "default": m.group(1) is not None})
    return sinks


def set_default(sink_id):
    subprocess.run(["wpctl", "set-default", sink_id], check=True)


def draw(stdscr, sinks, hover):
    stdscr.erase()
    stdscr.addstr(0, 1, "Audio Output", curses.A_BOLD)
    row_start = 2
    max_col = max(curses.COLS - 2, 1)
    if not sinks:
        stdscr.addstr(row_start, 1, "No output devices found", curses.A_DIM)
    for i, s in enumerate(sinks):
        marker = "●" if s["default"] else "○"
        popup_common.draw_row(stdscr, row_start + i, 1, f"{marker} ", s["name"], i == hover, max_col)
    stdscr.refresh()


def main(stdscr, close_event, own_addr):
    curses.curs_set(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    curses.mouseinterval(0)
    stdscr.keypad(True)
    stdscr.timeout(100)  # poll, so we can check close_event between mouse events
    curses.use_default_colors()

    sinks = get_sinks()
    row_start = 2
    hover = None

    def choose(i):
        set_default(sinks[i]["id"])
        for j, s in enumerate(sinks):
            s["default"] = j == i
        draw(stdscr, sinks, hover)
        time.sleep(0.15)

    draw(stdscr, sinks, hover)
    while not close_event.is_set():
        key = stdscr.getch()
        if key != curses.KEY_MOUSE:
            continue
        try:
            _, mx, my, _, bstate = curses.getmouse()
        except curses.error:
            continue
        row = my - row_start
        new_hover = row if sinks and 0 <= row < len(sinks) else None
        if new_hover != hover:
            hover = new_hover
            draw(stdscr, sinks, hover)
        clicked = bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED)
        if clicked and sinks and 0 <= row < len(sinks):
            choose(row)
            break


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--count":
        # Used by audio_menu_launch.sh to size the window before spawning
        # it, so the popup's height matches how many sinks will show.
        print(len(get_sinks()))
        raise SystemExit(0)
    popup_common.run(CLASS, main, popup_common.parse_restore_arg(sys.argv))
