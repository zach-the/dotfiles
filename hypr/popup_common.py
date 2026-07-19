#!/usr/bin/env python3
"""Shared plumbing for mouse-driven curses popups launched by
popup_launch.py (audio_menu.py, wifi_menu.py, bluetooth_menu.py):
detecting our own window address, watching Hyprland's event socket to
close on a real click elsewhere (filtering out the focus churn window
creation itself causes), and the follow_mouse disable/restore popups
share with popup_launch.py.
"""
import curses
import fcntl
import json
import os
import re
import socket
import subprocess
import sys
import threading
import time

# A muted mid-grey (xterm 256-color palette) for the hover pill's
# background - plain reverse-video looked too bright/white, since it
# just inverts whatever the terminal's own foreground color is.
HOVER_BG = 240

_hover_pairs_ready = False


def init_hover_colors():
    """Set up the pill's two color pairs: the body (default text color
    on the muted grey) and the caps (that same grey as foreground, on
    the default background, so the capsule's rounded ink matches the
    body's fill). Must run after curses color support is initialized -
    called once from run() below, before main_fn - and needs
    use_default_colors() already called so -1 is a valid "default"
    color in these pairs; run() handles that ordering too. Falls back
    to a plain dim reverse if the terminal can't do 256 colors."""
    global _hover_pairs_ready
    if curses.COLORS >= 256:
        curses.init_pair(1, -1, HOVER_BG)
        curses.init_pair(2, HOVER_BG, -1)
        _hover_pairs_ready = True


def hover_attr():
    return curses.color_pair(1) if _hover_pairs_ready else (curses.A_REVERSE | curses.A_DIM)


def cap_attr():
    return curses.color_pair(2) if _hover_pairs_ready else curses.A_DIM


# Powerline capsule caps (Nerd Font private-use glyphs): filled
# semicircles that bulge left/right.
LEFT_CAP = ""
RIGHT_CAP = ""


def draw_row(stdscr, y, x, prefix, name, hovered, max_col):
    """Draw one row as `prefix` (a radio button, lock icon, etc. — never
    highlighted) followed by `name` wrapped in a rounded capsule when
    hovered. The capsule is built from LEFT_CAP/RIGHT_CAP in place of
    the plain spaces that flank the name when it isn't hovered, so the
    highlight visibly starts and ends right at those spaces rather than
    bleeding into the prefix."""
    col = x

    def put(text, attr):
        nonlocal col
        remaining = max_col - (col - x)
        if remaining <= 0 or not text:
            return
        s = text[:remaining]
        try:
            stdscr.addstr(y, col, s, attr)
        except curses.error:
            pass
        col += len(s)

    put(prefix, curses.A_NORMAL)
    put(LEFT_CAP if hovered else " ", cap_attr() if hovered else curses.A_NORMAL)
    put(name, hover_attr() if hovered else curses.A_NORMAL)
    put(RIGHT_CAP if hovered else " ", cap_attr() if hovered else curses.A_NORMAL)


def enable_motion_tracking():
    """curses.mousemask(REPORT_MOUSE_POSITION) asks ncurses to report
    mouse motion, but whether that actually happens depends on the
    terminfo entry declaring an XM capability telling ncurses which
    escape sequence enables it — this TERM (xterm-256color, at least on
    this setup) doesn't, so ncurses falls back to button-drag-only
    tracking and idle hovering never generates events. Enabling xterm's
    "any-event" mode (1003) directly sidesteps that negotiation
    entirely; ncurses still parses the resulting reports fine since
    kmous already points it at the right prefix."""
    sys.stdout.write("\x1b[?1003h")
    sys.stdout.flush()


def disable_motion_tracking():
    sys.stdout.write("\x1b[?1003l")
    sys.stdout.flush()


def get_active_address():
    try:
        out = subprocess.run(["hyprctl", "-j", "activewindow"], capture_output=True, text=True, check=True).stdout
        data = json.loads(out) if out.strip() else {}
        addr = data.get("address")
        return addr.lower().removeprefix("0x") if addr else None
    except Exception:
        return None


def get_own_address(class_name, retries=20, delay=0.05):
    """Find our own window by class in the client list — not by waiting
    for it to become the active window, since windows spawned via
    `hyprctl dispatch exec` (popup_launch.py uses this for frame-1
    positioning) don't reliably auto-focus the way a directly-Popen'd
    process's window does."""
    for _ in range(retries):
        try:
            out = subprocess.run(["hyprctl", "-j", "clients"], capture_output=True, text=True, check=True).stdout
            matches = [c for c in json.loads(out) if c.get("class") == class_name]
            if matches:
                return matches[-1]["address"].lower().removeprefix("0x")
        except Exception:
            pass
        time.sleep(delay)
    return None


# Window creation/positioning itself causes a burst of transient focus
# bounces (observed: several rapid activewindowv2 flips between this
# popup and whatever was previously focused, before things settle) —
# ignore events entirely for this long after startup.
STARTUP_GRACE = 0.5
# Once settled, don't act on the first differing event alone (it could
# still be a stray bounce) — wait this long and re-check via a direct
# query before actually closing, so only a focus change that sticks
# (i.e. an actual click elsewhere) triggers a close.
CONFIRM_DELAY = 0.2


def watch_focus(own_addr, close_event):
    """Set close_event once Hyprland reports a different window as active
    and that holds up after a short confirmation delay."""
    sock_path = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr", os.environ["HYPRLAND_INSTANCE_SIGNATURE"], ".socket2.sock")
    start = time.monotonic()
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.connect(sock_path)
            buf = b""
            while not close_event.is_set():
                data = sock.recv(4096)
                if not data:
                    break
                buf += data
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    text = line.decode(errors="ignore")
                    if not text.startswith("activewindowv2>>"):
                        continue
                    addr = text.split(">>", 1)[1].strip().lower()
                    if time.monotonic() - start < STARTUP_GRACE:
                        continue
                    if addr == own_addr:
                        continue
                    time.sleep(CONFIRM_DELAY)
                    if get_active_address() != own_addr:
                        close_event.set()
                        return
    except OSError:
        pass


def make_close_event(class_name):
    """A threading.Event that gets set once focus has genuinely moved
    elsewhere (see watch_focus), and our own window's address in
    hyprctl's usual "0x..." form (or None if it couldn't be determined).
    Starts the watcher thread."""
    close_event = threading.Event()
    own_addr = get_own_address(class_name)
    if own_addr:
        threading.Thread(target=watch_focus, args=(own_addr, close_event), daemon=True).start()
    return close_event, (f"0x{own_addr}" if own_addr else None)


def parse_restore_arg(argv, flag="--restore-follow-mouse", default="1"):
    """popup_launch.py passes state like this as a CLI arg rather than an
    env var, since it spawns via `hyprctl dispatch exec` (for frame-1
    positioning) which doesn't inherit its own env the way
    subprocess.Popen(env=...) would."""
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv):
            return argv[i + 1]
    return default


FOLLOW_MOUSE_LOCK = os.path.join(os.environ["XDG_RUNTIME_DIR"], "hypr-popup-followmouse.lock")


def _live_follow_mouse():
    out = subprocess.run(
        ["hyprctl", "getoption", "input:follow_mouse"], capture_output=True, check=True, text=True
    ).stdout
    m = re.search(r"int:\s*(-?\d+)", out)
    return m.group(1) if m else "1"


def acquire_follow_mouse():
    """Disable follow_mouse for a popup's lifetime and return the true
    original value for it to later pass to restore_follow_mouse().
    Refcounted via a lock file rather than having each popup
    independently read-and-remember "whatever follow_mouse is right
    now" as its own "original": if a second popup opens before the
    first has restored, a naive read would capture 0 (the first
    popup's disabled value) as "original" and later restore to 0 —
    leaving follow_mouse stuck off. The lock file tracks how many
    popups currently hold it disabled plus the one true original value,
    set once by the first opener and handed to every popup opened while
    it's still held."""
    with open(FOLLOW_MOUSE_LOCK, "a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        content = f.read().strip()
        if content:
            count, original = content.split(":", 1)
            count = int(count) + 1
        else:
            original = _live_follow_mouse()
            count = 1
            subprocess.run(["hyprctl", "keyword", "input:follow_mouse", "0"], capture_output=True, check=False)
        f.seek(0)
        f.truncate()
        f.write(f"{count}:{original}")
    return original


def restore_follow_mouse(value):
    # Undo one acquire_follow_mouse() call. Refcounted against the same
    # lock file: only the popup whose release brings the count back to
    # 0 actually restores follow_mouse (to `value`, which
    # acquire_follow_mouse() guarantees is the same true original for
    # every popup that opened while another was already open) — closing
    # while other popups are still holding it just decrements.
    with open(FOLLOW_MOUSE_LOCK, "a+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.seek(0)
        content = f.read().strip()
        count = int(content.split(":", 1)[0]) - 1 if content else 0
        f.seek(0)
        f.truncate()
        if count > 0:
            f.write(f"{count}:{value}")
    if count <= 0:
        subprocess.run(["hyprctl", "keyword", "input:follow_mouse", value], capture_output=True, check=False)


def run(class_name, main_fn, restore_follow_mouse_value="1"):
    """curses.wrapper(main_fn) wired up with the close_event + follow_mouse
    restore boilerplate every popup needs. main_fn(stdscr, close_event,
    own_addr) is the app-specific loop; it should exit once close_event
    is set. own_addr (hyprctl's "0x..." form) is handed over so a popup
    that needs to target itself precisely (e.g. closing itself to hand
    off to a freshly-respawned replacement, see popup_launch.respawn)
    can do so exactly, rather than searching by class — which would be
    ambiguous if a stale duplicate ever lingered.

    If main_fn returns True, this is a handoff: something else (a
    respawned replacement window) now owns restoring follow_mouse, so
    this instance skips doing it itself."""
    handoff = False

    def _run(stdscr):
        nonlocal handoff
        curses.use_default_colors()
        init_hover_colors()
        enable_motion_tracking()
        close_event, own_addr = make_close_event(class_name)
        handoff = main_fn(stdscr, close_event, own_addr)

    try:
        curses.wrapper(_run)
    finally:
        disable_motion_tracking()
        if not handoff:
            restore_follow_mouse(restore_follow_mouse_value)
