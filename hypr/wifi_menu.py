#!/usr/bin/env python3
"""Curses popup listing nearby Wi-Fi networks (via `nmcli`). Click a
network to connect. If it's secured and there's no saved profile for
it, nmcli's connect attempt fails and this prompts for a password —
the one place this popup needs the keyboard, since a password can't be
clicked in. Click outside to dismiss, same as audio_menu.py.
Launched by wifi_menu_launch.sh, which waybar's network module
on-click runs. Shared popup plumbing (focus-watching, follow_mouse
handling) lives in popup_common.py.
"""
import curses
import json
import os
import queue
import re
import subprocess
import sys
import tempfile
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_common
import popup_launch

CLASS = "wifi-menu"
MAX_NETWORKS = 10
CONNECT_TIMEOUT = 15  # seconds; bounds nmcli's worst-case hang on a bad attempt
SCRIPT_PATH = os.path.abspath(__file__)

# Matches wifi_menu_launch.sh's placeholder size logic conceptually:
# header + blank spacer + bottom padding, around however many network
# rows we actually end up drawing. MIN_ROWS doubles as the row count we
# were actually spawned with while loading — must match
# wifi_menu_launch.sh's DEFAULT_ROWS.
MIN_ROWS = 6
MAX_ROWS = 15
ROW_OVERHEAD = 3


def _split_terse(line):
    # nmcli -t escapes literal ':' as '\:' and '\' as '\\' within a field
    fields = re.split(r"(?<!\\):", line)
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in fields]


def get_networks():
    out = subprocess.run(
        ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"],
        capture_output=True, text=True, check=True,
    ).stdout

    by_ssid = {}
    for line in out.splitlines():
        fields = _split_terse(line)
        if len(fields) < 4:
            continue
        in_use, ssid, signal, security = fields[0], fields[1], fields[2], fields[3]
        if not ssid:
            continue  # hidden network; can't usefully click a blank name
        try:
            signal_i = int(signal)
        except ValueError:
            signal_i = 0
        existing = by_ssid.get(ssid)
        if existing is None or signal_i > existing["signal"]:
            by_ssid[ssid] = {
                "ssid": ssid,
                "signal": signal_i,
                "secured": security.strip() != "",
                "connected": in_use.strip() == "*",
            }

    networks = sorted(by_ssid.values(), key=lambda n: (not n["connected"], -n["signal"]))
    return networks[:MAX_NETWORKS]


def try_connect(ssid, password=None):
    cmd = ["nmcli", "-w", str(CONNECT_TIMEOUT), "device", "wifi", "connect", ssid]
    if password is not None:
        cmd += ["password", password]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr.strip()


def draw_list(stdscr, networks, hover, status=None):
    stdscr.erase()
    stdscr.addstr(0, 1, "Wi-Fi Networks", curses.A_BOLD)
    row_start = 2
    max_col = max(curses.COLS - 2, 1)
    if not networks:
        stdscr.addstr(row_start, 1, "No networks found", curses.A_DIM)
    for i, n in enumerate(networks):
        marker = "●" if n["connected"] else "○"
        lock = "*" if n["secured"] else " "
        popup_common.draw_row(stdscr, row_start + i, 1, f"{marker} {lock} ", n["ssid"], i == hover, max_col)
    if status:
        try:
            stdscr.addstr(row_start + len(networks) + 1, 1, status[:max_col], curses.A_DIM)
        except curses.error:
            pass
    stdscr.refresh()


def prompt_password(stdscr, ssid, close_event):
    """Blocking (but close_event-aware) password entry. Returns the
    entered string, or None if cancelled/dismissed."""
    curses.curs_set(1)
    stdscr.timeout(100)
    buf = ""
    max_col = max(curses.COLS - 3, 1)
    try:
        while not close_event.is_set():
            stdscr.erase()
            stdscr.addstr(0, 1, f"Password for {ssid}"[:max_col], curses.A_BOLD)
            stdscr.addstr(2, 1, ("> " + "*" * len(buf))[:max_col])
            stdscr.addstr(4, 1, "enter to connect . esc to cancel"[:max_col], curses.A_DIM)
            stdscr.refresh()

            key = stdscr.getch()
            if key == -1:
                continue
            if key == 27:
                return None
            elif key in (curses.KEY_ENTER, 10, 13):
                return buf
            elif key in (curses.KEY_BACKSPACE, 127, 8):
                buf = buf[:-1]
            elif 32 <= key < 127:
                buf += chr(key)
        return None
    finally:
        curses.curs_set(0)


def main(stdscr, close_event, own_addr, preloaded, restore_value):
    curses.curs_set(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    curses.mouseinterval(0)
    stdscr.keypad(True)
    stdscr.timeout(100)
    curses.use_default_colors()

    row_start = 2
    hover = None

    if preloaded is not None:
        # Respawned by an earlier instance once it knew the real network
        # count (see below) — already sized correctly, nothing to load.
        networks = preloaded
        draw_list(stdscr, networks, hover)
        networks_ready = None
    else:
        stdscr.addstr(0, 1, "Wi-Fi Networks", curses.A_BOLD)
        stdscr.addstr(row_start, 1, "Loading networks...", curses.A_DIM)
        stdscr.refresh()
        # nmcli's scan can take a few seconds — run it in the background
        # so the getch() loop below keeps polling close_event the whole
        # time. Without this, moving off the popup while it's still
        # loading wouldn't close it until the scan finished.
        networks_ready = queue.Queue()
        threading.Thread(target=lambda: networks_ready.put(get_networks()), daemon=True).start()
        networks = None

    def finish(ssid, row):
        refreshed = get_networks()
        idx = next((i for i, n in enumerate(refreshed) if n["ssid"] == ssid), row)
        draw_list(stdscr, refreshed, idx, f"Connected to {ssid}")
        time.sleep(0.6)

    def connect(net, row, password=None):
        draw_list(stdscr, networks, row, f"Connecting to {net['ssid']}...")
        ok, err = try_connect(net["ssid"], password)
        if ok:
            finish(net["ssid"], row)
            return True
        if net["secured"] and password is None:
            # No saved profile (or it needs new credentials) — ask.
            pw = prompt_password(stdscr, net["ssid"], close_event)
            if pw is None:
                draw_list(stdscr, networks, row, None)
                return False
            return connect(net, row, pw)
        draw_list(stdscr, networks, row, "Wrong password or connection failed")
        return False

    while not close_event.is_set():
        if networks is None:
            try:
                networks = networks_ready.get_nowait()
            except queue.Empty:
                pass
            else:
                rows = max(MIN_ROWS, min(MAX_ROWS, ROW_OVERHEAD + max(len(networks), 1)))
                if rows != MIN_ROWS and own_addr:
                    win = next((c for c in popup_launch.hyprctl_json("clients") if c["address"] == own_addr), None)
                    if win:
                        with tempfile.NamedTemporaryFile(
                            mode="w", suffix=".json", prefix="wifi_menu_", delete=False
                        ) as f:
                            json.dump(networks, f)
                            tmp_path = f.name
                        anchor_x, anchor_y = win["at"]
                        new_addr = popup_launch.respawn(
                            CLASS, SCRIPT_PATH,
                            ["--networks-file", tmp_path, "--restore-follow-mouse", restore_value],
                            rows, anchor_x, anchor_y,
                        )
                        if new_addr:
                            subprocess.run(
                                ["hyprctl", "dispatch", "closewindow", f"address:{own_addr}"],
                                capture_output=True, check=False,
                            )
                            return True  # handoff: the new instance owns follow_mouse restore now
                        try:
                            os.remove(tmp_path)
                        except OSError:
                            pass
                # No respawn needed (already the right size) or it failed
                # — just draw what we've got at our current size.
                draw_list(stdscr, networks, hover)

        key = stdscr.getch()
        if networks is None or key != curses.KEY_MOUSE:
            continue
        try:
            _, mx, my, _, bstate = curses.getmouse()
        except curses.error:
            continue
        row = my - row_start
        new_hover = row if networks and 0 <= row < len(networks) else None
        if new_hover != hover:
            hover = new_hover
            draw_list(stdscr, networks, hover)

        clicked = bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED)
        if clicked and networks and 0 <= row < len(networks):
            if connect(networks[row], row):
                break
    return False


if __name__ == "__main__":
    restore_value = popup_common.parse_restore_arg(sys.argv)

    preloaded = None
    if "--networks-file" in sys.argv:
        _path = sys.argv[sys.argv.index("--networks-file") + 1]
        with open(_path) as _f:
            preloaded = json.load(_f)
        try:
            os.remove(_path)
        except OSError:
            pass

    def _main(stdscr, close_event, own_addr):
        return main(stdscr, close_event, own_addr, preloaded, restore_value)

    popup_common.run(CLASS, _main, restore_value)
