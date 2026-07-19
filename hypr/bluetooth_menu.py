#!/usr/bin/env python3
"""Curses popup listing paired Bluetooth devices (via `bluetoothctl`).
Click a device to connect it, or to disconnect if it's already
connected — unlike Wi-Fi, several Bluetooth devices can be connected
at once (mouse + headphones, say), so this is a toggle rather than a
single-select list. If Bluetooth itself is off, shows a single row to
turn it on instead of a device list.
Launched by bluetooth_menu_launch.sh, which waybar's custom/bluetooth
module on-click runs. Shared popup plumbing (focus-watching,
follow_mouse handling) lives in popup_common.py.
"""
import curses
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_common

CLASS = "bluetooth-menu"
ACTION_TIMEOUT = 15  # seconds; bounds a connect/disconnect attempt


def is_powered():
    out = subprocess.run(["bluetoothctl", "show"], capture_output=True, text=True, check=True).stdout
    return "Powered: yes" in out


def set_power(on):
    subprocess.run(["bluetoothctl", "power", "on" if on else "off"], capture_output=True, check=True)
    subprocess.run(["pkill", "-RTMIN+9", "waybar"], capture_output=True, check=False)


def _parse_devices(output):
    devices = []
    for line in output.splitlines():
        parts = line.split(" ", 2)
        if len(parts) == 3 and parts[0] == "Device":
            devices.append({"mac": parts[1], "name": parts[2]})
    return devices


def get_devices():
    paired = _parse_devices(
        subprocess.run(["bluetoothctl", "devices", "Paired"], capture_output=True, text=True, check=True).stdout
    )
    connected_macs = {
        d["mac"]
        for d in _parse_devices(
            subprocess.run(["bluetoothctl", "devices", "Connected"], capture_output=True, text=True, check=True).stdout
        )
    }
    for d in paired:
        d["connected"] = d["mac"] in connected_macs
    paired.sort(key=lambda d: (not d["connected"], d["name"]))
    return paired


def toggle_connection(mac, connected):
    cmd = ["bluetoothctl", "--timeout", str(ACTION_TIMEOUT), "disconnect" if connected else "connect", mac]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=ACTION_TIMEOUT + 5)
        ok = result.returncode == 0
    except subprocess.TimeoutExpired:
        ok = False
    subprocess.run(["pkill", "-RTMIN+9", "waybar"], capture_output=True, check=False)
    return ok


def draw(stdscr, devices, hover, powered, status=None):
    stdscr.erase()
    stdscr.addstr(0, 1, "Bluetooth", curses.A_BOLD)
    row_start = 2
    max_col = max(curses.COLS - 2, 1)

    if not powered:
        popup_common.draw_row(stdscr, row_start, 1, "", "Turn Bluetooth on", hover == 0, max_col)
    elif not devices:
        stdscr.addstr(row_start, 1, "No paired devices", curses.A_DIM)
    else:
        for i, d in enumerate(devices):
            marker = "●" if d["connected"] else "○"
            popup_common.draw_row(stdscr, row_start + i, 1, f"{marker} ", d["name"], i == hover, max_col)

    if status:
        footer_row = row_start + (1 if not powered else max(len(devices), 1)) + 1
        try:
            stdscr.addstr(footer_row, 1, status[:max_col], curses.A_DIM)
        except curses.error:
            pass
    stdscr.refresh()


def main(stdscr, close_event, own_addr):
    curses.curs_set(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    curses.mouseinterval(0)
    stdscr.keypad(True)
    stdscr.timeout(100)
    curses.use_default_colors()

    row_start = 2
    powered = is_powered()
    devices = get_devices() if powered else []
    hover = None

    draw(stdscr, devices, hover, powered)
    while not close_event.is_set():
        key = stdscr.getch()
        if key != curses.KEY_MOUSE:
            continue
        try:
            _, mx, my, _, bstate = curses.getmouse()
        except curses.error:
            continue
        row = my - row_start
        valid_rows = 1 if not powered else len(devices)
        new_hover = row if 0 <= row < valid_rows else None
        if new_hover != hover:
            hover = new_hover
            draw(stdscr, devices, hover, powered)

        clicked = bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED)
        if not clicked:
            continue

        if not powered:
            if row == 0:
                draw(stdscr, devices, hover, powered, "Turning on...")
                set_power(True)
                time.sleep(0.5)
                powered = is_powered()
                devices = get_devices() if powered else []
                hover = None
                draw(stdscr, devices, hover, powered)
            continue

        if devices and 0 <= row < len(devices):
            d = devices[row]
            draw(stdscr, devices, row, powered, f"{'Disconnecting from' if d['connected'] else 'Connecting to'} {d['name']}...")
            ok = toggle_connection(d["mac"], d["connected"])
            devices = get_devices()
            idx = next((i for i, n in enumerate(devices) if n["mac"] == d["mac"]), row)
            if ok:
                draw(stdscr, devices, idx, powered)
                break
            draw(stdscr, devices, idx, powered, "Connection failed")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--count":
        # Used by bluetooth_menu_launch.sh to size the window before
        # spawning it, so the popup's height matches how many rows it'll
        # actually draw (1 for the "turn on" row if powered off).
        print(len(get_devices()) if is_powered() else 1)
        raise SystemExit(0)
    popup_common.run(CLASS, main, popup_common.parse_restore_arg(sys.argv))
