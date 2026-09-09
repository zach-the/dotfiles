#!/usr/bin/env python3
"""Persistent daemon replacing the old per-click curses-in-wezterm
popups (see popup_launch.py/popup_common.py) for audio output, Wi-Fi,
and Bluetooth selection. Started once via hyprland.conf's exec-once;
owns one already-built GTK window per registered target, shown/hidden
instead of spawned/destroyed, and a Unix socket (popup_ipc.py) that
waybar's on-click (popup_client.py) talks to.

TARGETS is a plain registry -- audio/wifi/bluetooth all register the
same way in main() below, each reusing glib_async.py for anything that
needs to run without blocking this process's single GTK main loop.
"""
import json
import os
import re
import socket
import subprocess
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GLib, Gtk

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import audio_popup
import bluetooth_popup
import popup_ipc
import wifi_popup

WAYBAR_COLORS_CSS = os.path.expanduser("~/.config/waybar/colors.css")
POPUP_THEME_CSS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "popup_theme.css")

# How long to wait after a `pactl subscribe` event before actually
# refreshing/repainting, so a burst of events (e.g. a fast scroll-wheel
# volume change) collapses into one update — mirrors volume_refresh.sh's
# own debounce window for the same reason.
PACTL_DEBOUNCE_MS = 150

# How long the pointer/focus has to stay off a popup before it actually
# closes. Without this, Hyprland's follow_mouse (keyboard focus follows
# the pointer, not just clicks) fires our focus-out-event the instant
# the mouse merely passes over another window en route to the popup
# (e.g. a wezterm window sitting between the waybar icon and the
# popup's own position), closing it before the click ever lands. A
# short grace period, cancelled if focus/pointer comes back to the
# popup in time, absorbs that without needing to touch the global
# follow_mouse setting itself.
#
# Dismissal is driven by focus-out-event, leave-notify-event, AND a
# periodic pointer-position poll (PopupTarget._poll_pointer): on an
# empty workspace, moving the pointer off the popup has nothing else
# for the compositor to hand keyboard focus to, so focus-out-event
# never fires -- confirmed empirically that, at least in this setup,
# leave-notify-event isn't fully reliable there either once the
# pointer's over bare compositor background with no other surface
# present. The poll is a compositor-agnostic safety net that can't be
# fooled by either: it just reads the real pointer position. The event
# handlers still give snappier dismissal in the normal case (another
# window to cross into) where they do fire correctly.
DISMISS_GRACE_MS = 750
POINTER_POLL_MS = 300


class PopupTarget:
    def __init__(self, name, build, refresh):
        self.name = name
        self.refresh = refresh
        self.window = build()
        self.window.add_events(Gdk.EventMask.ENTER_NOTIFY_MASK | Gdk.EventMask.LEAVE_NOTIFY_MASK)
        self.window.connect("hide", self._on_hidden)
        self.window.connect("focus-out-event", self._on_lost)
        self.window.connect("focus-in-event", self._on_gained)
        self.window.connect("leave-notify-event", self._on_lost)
        self.window.connect("enter-notify-event", self._on_gained)
        self._visible = False
        self._hide_source = None
        self._poll_source = None

    def _on_hidden(self, _window):
        self._visible = False

    def _on_lost(self, _window, event):
        # focus-out-event has no "detail" field; leave-notify-event does,
        # and NOTIFY_INFERIOR means the pointer only moved onto a child
        # widget *within* this same window (e.g. from one row to
        # another) -- not an actual exit, so ignore those.
        if event.type == Gdk.EventType.LEAVE_NOTIFY and event.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._schedule_hide()
        return False

    def _on_gained(self, _window, event):
        if event.type == Gdk.EventType.ENTER_NOTIFY and event.detail == Gdk.NotifyType.INFERIOR:
            return False
        self._cancel_pending_hide()
        return False

    def _schedule_hide(self):
        if self._hide_source is None:
            self._hide_source = GLib.timeout_add(DISMISS_GRACE_MS, self._grace_expired)

    def _grace_expired(self):
        self._hide_source = None
        self.hide()
        return False

    def _cancel_pending_hide(self):
        if self._hide_source is not None:
            GLib.source_remove(self._hide_source)
            self._hide_source = None

    def _poll_pointer(self):
        """Fallback for _on_lost/_on_gained: on an empty workspace (no
        other window for keyboard focus to go to, and apparently
        sometimes no reliable leave-notify-event either -- confirmed
        empirically, not just theorized -- once the pointer's crossed
        onto bare compositor background with nothing else present),
        neither event can be trusted to fire at all, which would leave
        the popup stuck open forever with only the event-driven path.

        This can't use GDK's own get_device_position(): under Wayland a
        client only learns the pointer's position via motion events on
        its *own* surfaces, so once the pointer leaves ours we simply
        stop hearing about it at all -- querying afterward just replays
        the last position we were told, forever, since Wayland gives
        clients no protocol for asking "where is it now" once they've
        lost it (confirmed empirically: the query kept reporting the
        old in-bounds position long after the pointer had genuinely
        moved elsewhere). Asking the compositor itself instead
        (`hyprctl cursorpos`) sidesteps that entirely, since Hyprland
        tracks the pointer globally regardless of which surface (if
        any) currently has it. `hyprctl -j layers` gives this popup's
        own on-screen rectangle to test that position against, since
        GTK doesn't know the compositor-assigned layer-shell position
        either. Runs at a coarser interval than DISMISS_GRACE_MS purely
        as a safety net; the event handlers above still give snappier
        dismissal when they do fire correctly."""
        if not self._visible:
            self._poll_source = None
            return False
        try:
            pos_out = subprocess.run(["hyprctl", "cursorpos"], capture_output=True, check=True, text=True).stdout
            cx, cy = (int(v.strip()) for v in pos_out.split(","))
            layers = json.loads(subprocess.run(["hyprctl", "-j", "layers"], capture_output=True, check=True, text=True).stdout)
        except Exception:
            return True  # transient failure; try again next tick rather than force-closing

        rect = next(
            (s for mon in layers.values() for lvl in mon["levels"].values() for s in lvl if s.get("namespace") == "popup-daemon"),
            None,
        )
        if rect is None:
            return True

        inside = rect["x"] <= cx < rect["x"] + rect["w"] and rect["y"] <= cy < rect["y"] + rect["h"]
        if inside:
            self._cancel_pending_hide()
        else:
            self._schedule_hide()
        return True

    def show(self):
        for other in TARGETS.values():
            if other is not self and other._visible:
                other.hide()
        _load_css()
        self.refresh(self.window)
        self.window.show_all()
        self._visible = True
        if self._poll_source is None:
            self._poll_source = GLib.timeout_add(POINTER_POLL_MS, self._poll_pointer)

    def hide(self):
        self._cancel_pending_hide()
        self.window.hide()

    def toggle(self):
        self.hide() if self._visible else self.show()


TARGETS = {}


_css_providers = {}


def _load_css():
    """Called on every show() (not just once at startup) so a
    toggle_colors.sh swap takes effect on the next open with no daemon
    restart. Must remove each path's previous provider before adding a
    fresh one -- naively re-adding a brand new provider on every call
    without ever removing the old one leaked one CssProvider per show()
    for the daemon's whole lifetime, and a long-running daemon that's
    been toggled open/closed many times accumulates enough stacked
    providers to visibly corrupt rendering (confirmed: a fully opaque
    background-color came out badly blended with the desktop behind
    after ~50+ accumulated providers, fixed instantly by a fresh
    restart -- this dict-based swap is what keeps that from
    recurring)."""
    screen = Gdk.Screen.get_default()
    for path in (WAYBAR_COLORS_CSS, POPUP_THEME_CSS):
        if not os.path.exists(path):
            continue
        old = _css_providers.get(path)
        if old is not None:
            Gtk.StyleContext.remove_provider_for_screen(screen, old)
        provider = Gtk.CssProvider()
        try:
            provider.load_from_path(path)
        except GLib.Error:
            continue
        Gtk.StyleContext.add_provider_for_screen(screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION)
        _css_providers[path] = provider


# --- IPC socket server -------------------------------------------------

class _Connection:
    def __init__(self, conn):
        self.conn = conn
        self.buf = b""

    def on_readable(self, source, condition):
        if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
            self.conn.close()
            return False
        try:
            chunk = self.conn.recv(4096)
        except OSError:
            self.conn.close()
            return False
        if not chunk:
            self.conn.close()
            return False

        self.buf += chunk
        if b"\n" not in self.buf:
            return True

        line, _, _ = self.buf.partition(b"\n")
        response = _handle_request(line)
        try:
            self.conn.sendall((json.dumps(response) + "\n").encode())
        except OSError:
            pass
        self.conn.close()
        return False


def _handle_request(line):
    try:
        req = json.loads(line.decode())
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {"ok": False, "error": "bad request"}

    cmd = req.get("cmd")
    target_name = req.get("target")

    if cmd == "ping":
        return {"ok": True}

    if cmd == "close" and target_name == "*":
        for target in TARGETS.values():
            if target._visible:
                target.hide()
        return {"ok": True}

    target = TARGETS.get(target_name)
    if target is None:
        return {"ok": False, "error": f"no such target: {target_name}"}

    if cmd == "toggle":
        target.toggle()
    elif cmd == "open":
        target.show()
    elif cmd == "close":
        target.hide()
    else:
        return {"ok": False, "error": f"no such command: {cmd}"}
    return {"ok": True}


def _on_accept(sock, condition):
    conn, _addr = sock.accept()
    conn.setblocking(False)
    connection = _Connection(conn)
    GLib.io_add_watch(conn, GLib.IOCondition.IN | GLib.IOCondition.HUP, connection.on_readable)
    return True


def _start_server():
    """Bind the IPC socket, first checking (by connecting) whether
    another daemon instance already owns it — doubles as the
    single-instance lock, no separate lockfile needed."""
    try:
        probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        probe.settimeout(0.3)
        probe.connect(popup_ipc.SOCKET_PATH)
        probe.close()
        print("popup_daemon: another instance is already running, exiting", file=sys.stderr)
        sys.exit(0)
    except OSError:
        pass

    try:
        os.unlink(popup_ipc.SOCKET_PATH)
    except FileNotFoundError:
        pass

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.bind(popup_ipc.SOCKET_PATH)
    sock.listen(5)
    sock.setblocking(False)
    GLib.io_add_watch(sock, GLib.IOCondition.IN, _on_accept)
    return sock


# --- pactl subscribe watcher --------------------------------------------

_pactl_debounce_source = None


def _on_pactl_event():
    global _pactl_debounce_source
    _pactl_debounce_source = None
    audio = TARGETS.get("audio")
    # Skip while a Multi-Output volume slider is being dragged: the drag
    # itself generates these same subscribe events, and refresh() would
    # tear down and rebuild the very slider the pointer is gripping.
    if audio is not None and audio._visible and not getattr(audio.window, "_dragging", False):
        audio.refresh(audio.window)
    subprocess.run(["pkill", "-RTMIN+10", "waybar"], check=False)
    return False


def _on_pactl_line(source, condition):
    global _pactl_debounce_source
    if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
        return False
    line = source.readline()
    if not line:
        return False
    if re.search(r"on (sink|server) #", line):
        if _pactl_debounce_source is not None:
            GLib.source_remove(_pactl_debounce_source)
        _pactl_debounce_source = GLib.timeout_add(PACTL_DEBOUNCE_MS, _on_pactl_event)
    return True


def _start_pactl_watch():
    proc = subprocess.Popen(["pactl", "subscribe"], stdout=subprocess.PIPE, text=True, bufsize=1)
    channel = GLib.IOChannel.unix_new(proc.stdout.fileno())
    GLib.io_add_watch(channel, GLib.IOCondition.IN | GLib.IOCondition.HUP, _on_pactl_line)
    return proc


def main():
    _start_server()
    TARGETS["audio"] = PopupTarget("audio", audio_popup.build, audio_popup.refresh)
    TARGETS["wifi"] = PopupTarget("wifi", wifi_popup.build, wifi_popup.refresh)
    TARGETS["bluetooth"] = PopupTarget("bluetooth", bluetooth_popup.build, bluetooth_popup.refresh)
    _load_css()
    _start_pactl_watch()
    Gtk.main()


if __name__ == "__main__":
    main()
