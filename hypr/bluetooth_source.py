#!/usr/bin/env python3
"""Pure Bluetooth logic (no curses, no GTK) shared by bluetooth_popup.py
(popup_daemon.py's bluetooth target). Ported from the old
bluetooth_menu.py curses TUI, which this replaces."""
import subprocess

ACTION_TIMEOUT = 15  # seconds; bounds a connect/disconnect/pair attempt
SCAN_DURATION = 12  # seconds; how long a "Search" click scans for nearby devices
MAX_AVAILABLE = 10  # cap on discovered-but-unpaired devices shown


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
    connected flag) and available ones -- everything else bluetoothd
    currently has cached, e.g. from a "Search" scan (this one or an
    earlier one) -- sorted and capped for display."""
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
    # which isn't useful to pick out of a list. Also excludes bare-digit
    # names: ambient BLE beacons/trackers nearby (fitness bands, etc.)
    # advertise short numeric names, and in a noisy area there can be
    # dozens of them -- sorting alphabetically before the MAX_AVAILABLE
    # cap would otherwise bury real devices (e.g. "MX Anywhere 2S")
    # under a pile of "909", "1009", "1010", ... entries.
    available = [
        d for d in all_devices
        if d["mac"] not in paired_macs
        and d["name"] != d["mac"].replace(":", "-")
        and not d["name"].isdigit()
    ]
    available.sort(key=lambda d: d["name"])
    return paired, available[:MAX_AVAILABLE]


def start_toggle(mac, connected, kind):
    """Kick off a pair/connect/disconnect in the background and return the
    Popen handle to wait on. Runs detached (own session, no inherited
    stdio) so bluetoothctl keeps running to completion even if the
    popup closes -- e.g. the mouse moving off it -- while still in flight.

    A device that isn't paired yet (kind == "available") gets `pair`,
    not `connect`: per bluetoothctl's own man page, `pair` bonds,
    trusts, AND connects as one flow, while `connect` just opens the
    ATT link and lets profile drivers start probing GATT
    characteristics immediately -- without necessarily finishing SMP
    bonding first. `pair` must never be used on an already-paired
    device though -- the man page warns it removes the existing
    pairing first -- so a "known" row still gets connect/disconnect.

    Either way this relies on bluetooth_agent.sh (autostarted by
    Hyprland) already holding a NoInputNoOutput default agent
    registered for the whole session -- pairing requires one to be
    selected, and a one-shot invocation exits (dropping any agent it
    registered itself) the instant its single command resolves,
    typically before an async confirmation request would even arrive."""
    verb = "pair" if kind == "available" else ("disconnect" if connected else "connect")
    cmd = ["bluetoothctl", "--timeout", str(ACTION_TIMEOUT), verb, mac]
    return subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def check_toggle_success(mac, kind, was_connected):
    """bluetoothctl's own exit code for `connect` (and, per its general
    unreliability, potentially `disconnect`/`pair` too) can be 0 even
    when the operation never actually succeeded -- confirmed directly
    against this adapter: a connect attempt to an unreachable device
    still exits 0. Determine success from real post-attempt device
    state instead of trusting the exit code."""
    paired, _available = get_devices()
    d = find_by_mac(paired, mac)
    if kind == "available":
        return d is not None  # now shows up paired at all -> pair succeeded
    if was_connected:
        return d is None or not d["connected"]  # disconnect succeeded
    return d is not None and d["connected"]  # connect succeeded


def start_scan():
    """Kick off a scan for nearby devices in the background, detached the
    same way start_toggle() is -- self-bounded by --timeout regardless,
    but this keeps a closed popup from leaving anything wedged."""
    cmd = ["bluetoothctl", "--timeout", str(SCAN_DURATION), "scan", "on"]
    return subprocess.Popen(
        cmd,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )


def device_path(mac):
    return "/org/bluez/hci0/dev_" + mac.replace(":", "_")


def rename_device(mac, alias):
    """set-alias only operates on bluetoothctl's own "current device"
    state (and per testing, only works at all when that device is
    currently connected -- "No device connected" otherwise), which a
    one-shot invocation has no clean way to establish. Alias is just a
    local BlueZ property, so setting it directly over D-Bus sidesteps
    that entirely."""
    subprocess.run(
        ["busctl", "set-property", "org.bluez", device_path(mac), "org.bluez.Device1", "Alias", "s", alias],
        capture_output=True, check=False,
    )


def forget_device(mac):
    subprocess.run(["bluetoothctl", "remove", mac], capture_output=True, check=False)


def find_by_mac(items, mac):
    return next((d for d in items if d["mac"] == mac), None)
