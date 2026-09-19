#!/usr/bin/env python3
"""Brightness keys for whichever monitor the mouse is on.

usage: brightness.py up|down     adjust the monitor under the cursor
       brightness.py percent     print its current brightness (0-100)

eDP-* (built-in panel): brightnessctl, on the same -e4 exponential curve the
bindings always used.
Anything else: DDC/CI through ddcutil (the Linux counterpart of what
MonitorControl / Lunar do on macOS). The I2C bus comes straight from
/sys/class/drm/card*-<connector>/ddc, which skips `ddcutil detect` -- that
probe takes seconds per run.

A DDC write takes ~100s of ms, so a held key would pile up writes. Each press
only bumps a cached target and pokes waybar; a serialized writer then applies
whatever the latest target is, so a burst of presses collapses to a few writes.
"""
import contextlib
import fcntl
import glob
import json
import os
import subprocess
import sys
import time

STEP = 10  # percent per press, same as the old bindings
STALE = 10  # seconds; older cached targets are re-read (monitor OSD may have changed it)
VCP_BRIGHTNESS = "10"
WAYBAR_SIGNAL = "-RTMIN+13"  # matches "signal": 13 on custom/backlight
STATE_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "brightness")


def hyprctl(what):
    return json.loads(subprocess.check_output(["hyprctl", "-j", what]))


def monitor_under_cursor():
    pos = hyprctl("cursorpos")
    monitors = hyprctl("monitors")
    for m in monitors:
        w, h = m["width"] / m["scale"], m["height"] / m["scale"]
        if m["x"] <= pos["x"] < m["x"] + w and m["y"] <= pos["y"] < m["y"] + h:
            return m["name"]
    return next(m["name"] for m in monitors if m["focused"])


def poke_waybar():
    subprocess.run(["pkill", WAYBAR_SIGNAL, "waybar"])


def notify(msg):
    subprocess.run(["notify-send", "-t", "3000", "-u", "low", "Brightness", msg])


# --- small state store -----------------------------------------------------
# <conn>.target   {value, max, ts}  what the user asked for (written under lock a)
# <conn>.applied  {value}           what we last wrote to the monitor (lock b)
# lock a guards the target, lock b serializes access to the I2C bus. Always
# take a before b, never the reverse.

def state_path(name):
    os.makedirs(STATE_DIR, exist_ok=True)
    return os.path.join(STATE_DIR, name)


@contextlib.contextmanager
def lock(name):
    fd = os.open(state_path(name), os.O_CREAT | os.O_RDWR)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


def load(name):
    try:
        with open(state_path(name)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save(name, obj):
    path = state_path(name)
    with open(path + ".tmp", "w") as f:
        json.dump(obj, f)
    os.replace(path + ".tmp", path)


# --- DDC/CI ----------------------------------------------------------------

def ddc_bus(connector):
    for p in glob.glob(f"/sys/class/drm/card*-{connector}/ddc"):
        return os.path.basename(os.path.realpath(p)).removeprefix("i2c-")
    raise RuntimeError(f"no DDC bus for {connector}")


def ddcutil(bus, *args):
    return subprocess.run(["ddcutil", "--bus", bus, *args],
                          capture_output=True, text=True, timeout=20)


def ddc_read(bus):
    r = ddcutil(bus, "--terse", "getvcp", VCP_BRIGHTNESS)
    try:  # terse: "VCP 10 C <current> <max>"
        parts = r.stdout.split()
        return int(parts[3]), int(parts[4])
    except (IndexError, ValueError):
        raise RuntimeError(f"ddcutil getvcp failed: {(r.stderr or r.stdout).strip()}")


def refresh(connector, bus):
    """Re-read the monitor into the cache. Caller holds lock a."""
    with lock(f"{connector}.b"):
        value, mx = ddc_read(bus)
        save(f"{connector}.applied", {"value": value})
    target = {"value": value, "max": mx, "ts": time.time()}
    save(f"{connector}.target", target)
    return target


def ddc_percent(connector):
    with lock(f"{connector}.a"):
        t = load(f"{connector}.target") or refresh(connector, ddc_bus(connector))
    return t["value"] * 100 // t["max"]


def ddc_adjust(connector, sign):
    bus = ddc_bus(connector)
    with lock(f"{connector}.a"):
        t = load(f"{connector}.target")
        if not t or time.time() - t["ts"] > STALE:
            t = refresh(connector, bus)
        step = max(1, round(t["max"] * STEP / 100))
        t["value"] = min(t["max"], max(0, t["value"] + sign * step))
        t["ts"] = time.time()
        save(f"{connector}.target", t)
    poke_waybar()  # icon follows the target immediately, before the slow write

    with lock(f"{connector}.b"):
        t = load(f"{connector}.target")
        applied = load(f"{connector}.applied")
        if applied and applied["value"] == t["value"]:
            return  # a writer ahead of us in the queue already applied it
        r = ddcutil(bus, "--noverify", "setvcp", VCP_BRIGHTNESS, str(t["value"]))
        if r.returncode == 0:
            save(f"{connector}.applied", {"value": t["value"]})
        else:
            with contextlib.suppress(OSError):
                os.unlink(state_path(f"{connector}.target"))  # force a re-read next press
            raise RuntimeError(f"ddcutil setvcp failed: {(r.stderr or r.stdout).strip()}")


# --- built-in panel --------------------------------------------------------

def panel_percent():
    # device,class,current,percent%,max -- percent is on the -e4 curve.
    out = subprocess.check_output(["brightnessctl", "-e4", "-m"]).decode().strip()
    return int(out.split(",")[3].rstrip("%"))


def panel_adjust(sign):
    subprocess.run(["brightnessctl", "-e4", "-n2", "set", f"{STEP}%{'+' if sign > 0 else '-'}"])
    poke_waybar()


# --- entry points ----------------------------------------------------------

def percent():
    name = monitor_under_cursor()
    return panel_percent() if name.startswith("eDP") else ddc_percent(name)


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("up", "down", "percent"):
        sys.exit(__doc__)
    if sys.argv[1] == "percent":
        print(percent())
        return
    sign = 1 if sys.argv[1] == "up" else -1
    try:
        name = monitor_under_cursor()
        if name.startswith("eDP"):
            panel_adjust(sign)
        else:
            ddc_adjust(name, sign)
    except Exception as e:
        print(e, file=sys.stderr)
        notify(str(e))
        sys.exit(1)


if __name__ == "__main__":
    main()
