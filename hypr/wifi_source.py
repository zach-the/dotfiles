#!/usr/bin/env python3
"""Pure Wi-Fi network logic (no curses, no GTK), ported from the old
wifi_menu.py curses TUI, which this replaces."""
import re
import subprocess

MAX_NETWORKS = 10
CONNECT_TIMEOUT = 15  # seconds; bounds nmcli's worst-case hang on a bad attempt


def _split_terse(line):
    # nmcli -t escapes literal ':' as '\:' and '\' as '\\' within a field
    fields = re.split(r"(?<!\\):", line)
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in fields]


SCAN_CMD = ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]


def get_networks():
    """Blocking scan — used by tests/manual checks. wifi_popup.py runs
    SCAN_CMD itself via glib_async.run_subprocess_async instead, so the
    GTK loop is never blocked on nmcli, but feeds the same lines through
    parse_networks() below."""
    out = subprocess.run(SCAN_CMD, capture_output=True, text=True, check=True).stdout
    return parse_networks(out.splitlines())


def parse_networks(lines):
    by_ssid = {}
    for line in lines:
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
        connected = in_use.strip() == "*"
        existing = by_ssid.get(ssid)
        # Prefer whichever entry is actually connected over raw signal
        # strength: hotel/mesh Wi-Fi often broadcasts the same SSID from
        # several APs, and the one you're on isn't necessarily the
        # strongest — picking by signal alone could silently replace the
        # connected entry with an unconnected one of the same name,
        # dropping the "connected" flag entirely.
        if existing is None or (connected and not existing["connected"]) or (
            connected == existing["connected"] and signal_i > existing["signal"]
        ):
            by_ssid[ssid] = {
                "ssid": ssid,
                "signal": signal_i,
                "secured": security.strip() != "",
                "connected": connected,
            }

    networks = sorted(by_ssid.values(), key=lambda n: (not n["connected"], -n["signal"]))
    return networks[:MAX_NETWORKS]


def try_connect(ssid, password=None):
    cmd = ["nmcli", "-w", str(CONNECT_TIMEOUT), "device", "wifi", "connect", ssid]
    if password is not None:
        cmd += ["password", password]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return result.returncode == 0, result.stderr.strip()
