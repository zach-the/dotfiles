#!/usr/bin/env python3
"""Async helpers for popup_daemon.py consumers, so nothing ever blocks
the daemon's single GTK main loop. audio_popup.py doesn't need these
yet (every call it makes is a quick synchronous subprocess) — this
exists so a future wifi consumer's network scan or a bluetooth
consumer's pairing flow can plug into the same daemon without a second
async redesign."""
import threading

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib


def run_subprocess_async(argv, on_line=None, on_exit=None):
    """Spawn argv without blocking the GTK loop. on_line(str) fires once
    per stdout line as it arrives; on_exit(returncode) fires when the
    process exits. Returns the GLib.Pid so callers can kill it (e.g. a
    scan-timeout path) via GLib.spawn_close_pid / os.kill."""
    flags = GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD
    pid, _stdin, stdout, _stderr = GLib.spawn_async(
        argv, flags=flags, standard_output=True
    )

    if on_line is not None:
        channel = GLib.IOChannel.unix_new(stdout)

        def _on_readable(chan, condition):
            if condition & (GLib.IOCondition.HUP | GLib.IOCondition.ERR):
                return False
            try:
                line = chan.readline()
            except GLib.Error:
                return False
            if not line:
                return False
            on_line(line.rstrip("\n"))
            return True

        GLib.io_add_watch(channel, GLib.IOCondition.IN | GLib.IOCondition.HUP, _on_readable)

    if on_exit is not None:
        def _on_child_exit(pid, status, _data=None):
            GLib.spawn_close_pid(pid)
            on_exit(status)

        GLib.child_watch_add(pid, _on_child_exit)

    return pid


def call_in_thread(fn, *args, on_done=None):
    """Run fn(*args) on a daemon thread for blocking calls with no fd to
    watch (e.g. a synchronous dbus-python pairing call). fn must not
    touch GTK widgets directly — its result is handed to on_done on the
    main thread via GLib.idle_add, where touching widgets is safe."""
    def _worker():
        result = fn(*args)
        if on_done is not None:
            GLib.idle_add(on_done, result)

    threading.Thread(target=_worker, daemon=True).start()
