#!/usr/bin/env python3
"""Curses popup listing paired Bluetooth devices (via `bluetoothctl`).
Click a device to connect it, or to disconnect if it's already
connected — unlike Wi-Fi, several Bluetooth devices can be connected
at once (mouse + headphones, say), so this is a toggle rather than a
single-select list. If Bluetooth itself is off, shows a single row to
turn it on instead of a device list.

A "Search" button in the top-right corner kicks off a scan for nearby
devices; anything bluetoothd knows about but that isn't paired yet
(freshly discovered, or left over from an earlier scan) is listed
below a dividing line under the known devices. Clicking one of those
pairs, trusts, and connects it in one step. Since the result of a
search can need more rows than the popup was originally sized for,
growing the list respawns the popup at the right size — same trick
wifi_menu.py uses, see popup_launch.py's module docstring.

Launched by bluetooth_menu_launch.sh, which waybar's custom/bluetooth
module on-click runs. Shared popup plumbing (focus-watching,
follow_mouse handling) lives in popup_common.py.
"""
import curses
import json
import os
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import popup_common
import popup_launch

CLASS = "bluetooth-menu"
ACTION_TIMEOUT = 15  # seconds; bounds a connect/disconnect attempt
SCAN_DURATION = 5  # seconds; how long a "Search" click scans for nearby devices
MAX_AVAILABLE = 10  # cap on discovered-but-unpaired devices shown, same idea as wifi_menu.py's MAX_NETWORKS
SEARCH_LABEL = "Search"
SCRIPT_PATH = os.path.abspath(__file__)

# Matches bluetooth_menu_launch.sh's placeholder size logic — must stay in
# sync with the constants of the same name there, since --count's output
# (fed through that same formula) is what sizes the popup at launch, while
# these are used to decide whether a post-search respawn needs to happen.
MIN_ROWS = 4
MAX_ROWS = 15
ROW_OVERHEAD = 3


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
    """Returns (paired, available): paired devices (bonded, with a live
    connected flag) and available ones — everything else bluetoothd
    currently has cached, e.g. from a "Search" scan (this one or an
    earlier one) — sorted and capped for display."""
    all_devices = _parse_devices(
        subprocess.run(["bluetoothctl", "devices"], capture_output=True, text=True, check=True).stdout
    )
    paired_macs = {
        d["mac"]
        for d in _parse_devices(
            subprocess.run(["bluetoothctl", "devices", "Paired"], capture_output=True, text=True, check=True).stdout
        )
    }
    connected_macs = {
        d["mac"]
        for d in _parse_devices(
            subprocess.run(["bluetoothctl", "devices", "Connected"], capture_output=True, text=True, check=True).stdout
        )
    }

    paired = [d for d in all_devices if d["mac"] in paired_macs]
    for d in paired:
        d["connected"] = d["mac"] in connected_macs
    paired.sort(key=lambda d: (not d["connected"], d["name"]))

    # Excludes devices that haven't broadcast a real name: bluetoothctl
    # falls back to the address itself (dashed) as the alias for those,
    # which isn't useful to pick out of a list.
    available = [
        d for d in all_devices
        if d["mac"] not in paired_macs and d["name"] != d["mac"].replace(":", "-")
    ]
    available.sort(key=lambda d: d["name"])
    return paired, available[:MAX_AVAILABLE]


def start_toggle(mac, connected):
    """Kick off a connect/disconnect in the background and return the Popen
    handle to poll. Runs detached (own session, no inherited stdio) so
    bluetoothctl keeps running to completion even if the popup window
    closes — e.g. the mouse moving off it — while it's still in flight."""
    cmd = ["bluetoothctl", "--timeout", str(ACTION_TIMEOUT), "disconnect" if connected else "connect", mac]
    return subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def start_scan():
    """Kick off a scan for nearby devices in the background, detached the
    same way start_toggle() is — self-bounded by --timeout regardless,
    but this keeps a closed popup from leaving anything wedged."""
    cmd = ["bluetoothctl", "--timeout", str(SCAN_DURATION), "scan", "on"]
    return subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def total_rows(paired, available):
    """How many content rows (devices, plus a divider if there are any
    available ones) it takes to draw this data — the same number
    bluetooth_menu_launch.sh's --count precheck feeds into its own
    ROW_OVERHEAD/MIN_ROWS/MAX_ROWS formula for the initial spawn size."""
    n = max(len(paired), 1)  # the "No paired devices" placeholder takes a row too
    if available:
        n += 1 + len(available)
    return n


def clamp_rows(n):
    return max(MIN_ROWS, min(MAX_ROWS, ROW_OVERHEAD + n))


def known_row_count(devices):
    return len(devices) if devices else 1  # "No paired devices" placeholder takes a row too


def hit_test(row, devices, available):
    """Map a 0-based content row (my - row_start) to ("known", i) or
    ("available", i), or None if it's the placeholder text, the divider,
    or out of bounds."""
    kn = known_row_count(devices)
    if devices and 0 <= row < kn:
        return ("known", row)
    if available:
        start = kn + 1
        if start <= row < start + len(available):
            return ("available", row - start)
    return None


def search_button_bounds():
    w = len(SEARCH_LABEL) + 2  # +2 for draw_row's capsule/space padding on each side
    x = max(curses.COLS - 1 - w, 1)
    return x, w


def draw(stdscr, devices, available, hover, powered, status=None):
    stdscr.erase()
    stdscr.addstr(0, 1, "Bluetooth", curses.A_BOLD)
    row_start = 2
    max_col = max(curses.COLS - 2, 1)

    if powered:
        search_x, search_w = search_button_bounds()
        popup_common.draw_row(stdscr, 0, search_x, "", SEARCH_LABEL, hover == "search", search_w)

    if not powered:
        popup_common.draw_row(stdscr, row_start, 1, "", "Turn Bluetooth on", hover == "power", max_col)
        content_rows = 1
    elif not devices:
        stdscr.addstr(row_start, 1, "No paired devices", curses.A_DIM)
        content_rows = 1
    else:
        for i, d in enumerate(devices):
            marker = "●" if d["connected"] else "○"
            popup_common.draw_row(stdscr, row_start + i, 1, f"{marker} ", d["name"], hover == ("known", i), max_col)
        content_rows = len(devices)

    if powered and available:
        divider_row = row_start + content_rows
        try:
            stdscr.addstr(divider_row, 1, "─" * max_col, curses.A_DIM)
        except curses.error:
            pass
        for i, d in enumerate(available):
            popup_common.draw_row(stdscr, divider_row + 1 + i, 1, "+ ", d["name"], hover == ("available", i), max_col)
        content_rows += 1 + len(available)

    if status:
        footer_row = row_start + content_rows + 1
        try:
            stdscr.addstr(footer_row, 1, status[:max_col], curses.A_DIM)
        except curses.error:
            pass
    stdscr.refresh()


def _find_mac(items, mac):
    return next((i for i, d in enumerate(items) if d["mac"] == mac), None)


def main(stdscr, close_event, own_addr, preloaded=None, restore_value="1"):
    curses.curs_set(0)
    curses.mousemask(curses.ALL_MOUSE_EVENTS | curses.REPORT_MOUSE_POSITION)
    curses.mouseinterval(0)
    stdscr.keypad(True)
    stdscr.timeout(100)
    curses.use_default_colors()

    row_start = 2
    if preloaded is not None:
        # Respawned by an earlier instance once it knew the real
        # post-search device count (see below) — only ever happens while
        # powered, since Search isn't available otherwise.
        powered = True
        devices, available = preloaded
    else:
        powered = is_powered()
        devices, available = get_devices() if powered else ([], [])
    current_rows = clamp_rows(total_rows(devices, available)) if powered else MIN_ROWS
    hover = None
    pending = None  # {"proc", "mac", "kind"} while a connect/disconnect runs in the background
    scanning = None  # Popen while a Search scan runs in the background

    draw(stdscr, devices, available, hover, powered)
    while not close_event.is_set():
        key = stdscr.getch()

        # Runs every iteration (stdscr.timeout(100) guarantees one even
        # without mouse activity) rather than blocking on the subprocess,
        # so hover/close_event stay responsive while a connect/disconnect
        # is in flight.
        if pending is not None and pending["proc"].poll() is not None:
            ok = pending["proc"].returncode == 0
            subprocess.run(["pkill", "-RTMIN+9", "waybar"], capture_output=True, check=False)
            if ok and pending["kind"] == "available":
                # Newly paired — trust it so future reconnects don't need
                # another search/confirm dance.
                subprocess.run(["bluetoothctl", "trust", pending["mac"]], capture_output=True, check=False)
            devices, available = get_devices()
            idx = _find_mac(devices, pending["mac"])
            if idx is not None:
                hover = ("known", idx)
            else:
                idx = _find_mac(available, pending["mac"])
                hover = ("available", idx) if idx is not None else None
            pending = None
            if ok:
                draw(stdscr, devices, available, hover, powered)
                break
            draw(stdscr, devices, available, hover, powered, "Connection failed")

        if scanning is not None and scanning.poll() is not None:
            scanning = None
            devices, available = get_devices()
            new_rows = clamp_rows(total_rows(devices, available))
            if new_rows != current_rows and own_addr:
                win = next((c for c in popup_launch.hyprctl_json("clients") if c["address"] == own_addr), None)
                if win:
                    with tempfile.NamedTemporaryFile(
                        mode="w", suffix=".json", prefix="bluetooth_menu_", delete=False
                    ) as f:
                        json.dump([devices, available], f)
                        tmp_path = f.name
                    anchor_x, anchor_y = win["at"]
                    new_addr = popup_launch.respawn(
                        CLASS, SCRIPT_PATH,
                        ["--devices-file", tmp_path, "--restore-follow-mouse", restore_value],
                        new_rows, anchor_x, anchor_y,
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
            hover = None
            draw(stdscr, devices, available, hover, powered)

        if key != curses.KEY_MOUSE:
            continue
        try:
            _, mx, my, _, bstate = curses.getmouse()
        except curses.error:
            continue

        search_x, search_w = search_button_bounds()
        over_search = powered and my == 0 and search_x <= mx < search_x + search_w
        row = my - row_start
        if over_search:
            new_hover = "search"
        elif not powered:
            new_hover = "power" if row == 0 else None
        else:
            new_hover = hit_test(row, devices, available)

        if pending is None and scanning is None and new_hover != hover:
            hover = new_hover
            draw(stdscr, devices, available, hover, powered)

        clicked = bstate & (curses.BUTTON1_CLICKED | curses.BUTTON1_PRESSED | curses.BUTTON1_RELEASED)
        if not clicked or pending is not None or scanning is not None:
            continue

        if over_search:
            scanning = start_scan()
            draw(stdscr, devices, available, hover, powered, "Searching...")
            continue

        if not powered:
            if row == 0:
                draw(stdscr, devices, available, hover, powered, "Turning on...")
                set_power(True)
                time.sleep(0.5)
                powered = is_powered()
                devices, available = get_devices() if powered else ([], [])
                hover = None
                draw(stdscr, devices, available, hover, powered)
            continue

        target = hit_test(row, devices, available)
        if target is not None:
            kind, i = target
            d = (devices if kind == "known" else available)[i]
            connected = d.get("connected", False)
            verb = "Disconnecting from" if connected else "Connecting to"
            draw(stdscr, devices, available, target, powered, f"{verb} {d['name']}...")
            pending = {"proc": start_toggle(d["mac"], connected), "mac": d["mac"], "kind": kind}
    return False


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--count":
        # Used by bluetooth_menu_launch.sh to size the window before
        # spawning it, so the popup's height matches how many rows it'll
        # actually draw (1 for the "turn on" row if powered off).
        paired, available = get_devices() if is_powered() else ([], [])
        print(total_rows(paired, available))
        raise SystemExit(0)

    restore_value = popup_common.parse_restore_arg(sys.argv)

    preloaded = None
    if "--devices-file" in sys.argv:
        _path = sys.argv[sys.argv.index("--devices-file") + 1]
        with open(_path) as _f:
            preloaded = tuple(json.load(_f))
        try:
            os.remove(_path)
        except OSError:
            pass

    def _main(stdscr, close_event, own_addr):
        return main(stdscr, close_event, own_addr, preloaded, restore_value)

    popup_common.run(CLASS, _main, restore_value)
