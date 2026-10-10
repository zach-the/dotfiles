#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "jellyfin" target: a layer-shell
popup listing Jellyfin libraries (via jellyfin_source.py) as ●/○ toggle
rows, same visual language as audio_popup.py's single-output rows and
bluetooth_popup.py's device rows. Clicking a row flips that library's
visibility for the account (EnabledFolders over the REST API) without
touching files or restarting the server.

If jellyfin.service isn't running, the list is replaced with a single
"Turn Jellyfin on" row (same pattern as bluetooth_popup.py's
_make_power_row for an off adapter) rather than showing library rows
that would just fail against an unreachable server.

A "Refresh" button in the header (same spot/role as bluetooth_popup.py's
"Search") kicks off Jellyfin's own "Scan Media Library" scheduled task
and polls it (jellyfin_source.get_scan_progress) every
SCAN_POLL_INTERVAL_MS for a live percentage, drawn as a flat
Gtk.ProgressBar under the header -- Jellyfin reports this itself via
ScheduledTasks' CurrentProgressPercentage, so no guessing/animating a
fake progress is needed. refresh() also checks for a scan already in
progress (e.g. kicked off from Jellyfin's own dashboard, or its nightly
trigger) and resumes polling it rather than assuming idle.

Network calls (jellyfin_source's requests.* calls) all run via
glib_async.call_in_thread, same reasoning as bluetooth_popup.py: this
daemon has one GTK main loop and nothing may block it.

build() is called once at daemon startup; refresh() runs every time the
popup is shown."""
import json
import subprocess
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gtk, GtkLayerShell

import glib_async
import jellyfin_source

# Gap below waybar's own bottom edge -- same value the other popups use,
# tuned by eye against the live bar.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge
# to the jellyfin module's position in modules-right (it's the leftmost
# entry there, so this is the largest of any popup's margin -- language
# + mode + volume + bluetooth + backlight + wifi + battery icons, their
# spacing, and waybar's own right margin, all sit to its right). Waybar
# exposes no per-module geometry over IPC, so this has to be tuned by
# eye against the live bar; re-measure if modules-right's order, icon
# sizes, or font changes.
JELLYFIN_ANCHOR_MARGIN_RIGHT = 210

# How often to re-poll ScheduledTasks' CurrentProgressPercentage while a
# library scan is running. The server only updates it a few times a
# second internally, so this doesn't need to be tighter than that.
SCAN_POLL_INTERVAL_MS = 600


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, JELLYFIN_ANCHOR_MARGIN_RIGHT)


def _set_status(window, text):
    if text:
        window._status_label.set_text(text)
        window._status_label.show()
    else:
        window._status_label.hide()


def _set_progress(window, fraction):
    """fraction is 0.0-1.0, or None to hide the bar entirely (idle, or a
    running scan whose percentage the server hasn't reported yet --
    distinct from 0.0, which draws an actual empty bar)."""
    if fraction is None:
        window._progress_bar.hide()
    else:
        window._progress_bar.set_fraction(fraction)
        window._progress_bar.show()


# --- Row construction -------------------------------------------------

def _make_library_row(lib, enabled):
    row = Gtk.ListBoxRow()
    row.kind = "library"
    row.folder_id = lib["id"]
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    marker = Gtk.Label(label="●" if enabled else "○")
    name = Gtk.Label(label=lib["name"], xalign=0)
    box.pack_start(marker, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _make_power_row():
    row = Gtk.ListBoxRow()
    row.kind = "power"
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label="Turn Jellyfin on", xalign=0), True, True, 0)
    row.add(box)
    return row


# --- Click handling -----------------------------------------------------

def _on_row_activated(_listbox, row, window):
    if window._pending:
        return
    kind = getattr(row, "kind", None)

    if kind == "power":
        _set_status(window, "Starting…")
        window._pending = True

        def worker():
            jellyfin_source.start()
            # Give the server a moment to actually come up before the
            # next refresh tries to hit its API.
            for _ in range(20):
                if jellyfin_source.is_running():
                    break
                time.sleep(0.25)
            return None

        glib_async.call_in_thread(worker, on_done=lambda _r: _on_power_done(window))
        return

    if kind != "library":
        return

    lib = next((l for l in window._libraries if l["id"] == row.folder_id), None)
    if lib is None:
        return
    enabled = jellyfin_source.is_enabled(window._policy, lib["id"])
    window._pending = True
    _set_status(window, f"{'Hiding' if enabled else 'Showing'} {lib['name']}…")
    all_ids = [l["id"] for l in window._libraries]

    def worker():
        jellyfin_source.set_folder_enabled(lib["id"], not enabled, all_ids)
        return jellyfin_source.get_policy()

    glib_async.call_in_thread(worker, on_done=lambda result: _on_toggle_done(window, result))


def _on_refresh_clicked(_button, window):
    if window._scanning:
        return
    window._scanning = True
    _set_status(window, "Scanning…")
    _set_progress(window, 0.0)
    glib_async.call_in_thread(jellyfin_source.start_library_scan, on_done=lambda _ok: _poll_scan(window))


def _poll_scan(window):
    """One tick of the scan-progress poll: fires a background request
    and, once it returns, schedules the next tick itself (rather than
    GLib.timeout_add re-firing on a fixed schedule) so a slow request
    can never stack a second one behind it."""
    if not window._scanning:
        return
    glib_async.call_in_thread(jellyfin_source.get_scan_progress, on_done=lambda result: _on_scan_progress(window, result))


def _on_scan_progress(window, result):
    if not window._scanning:
        return  # popup/daemon could have moved on (e.g. a fresh refresh()) while this request was in flight
    running, percent = result
    if not running:
        window._scanning = False
        _set_progress(window, None)
        refresh(window)  # library list may have changed (new folders found); also clears status
        return

    _set_progress(window, (percent or 0) / 100)
    _set_status(window, f"Scanning… {percent:.0f}%" if percent is not None else "Scanning…")
    GLib.timeout_add(SCAN_POLL_INTERVAL_MS, lambda: (_poll_scan(window), False)[1])


def _on_power_done(window):
    window._pending = False
    refresh(window)
    _set_status(window, None)


def _on_toggle_done(window, result):
    window._pending = False
    _user_id, window._policy = result
    _set_status(window, None)
    _render_list(window)


# --- Shared ---------------------------------------------------------------

def _render_list(window):
    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    if not window._libraries:
        empty = Gtk.ListBoxRow(activatable=False, selectable=False)
        empty.add(Gtk.Label(label="No libraries found"))
        listbox.add(empty)
    else:
        for lib in window._libraries:
            enabled = jellyfin_source.is_enabled(window._policy, lib["id"])
            listbox.add(_make_library_row(lib, enabled))
    listbox.show_all()


def refresh(window):
    # See audio_popup.py's refresh() for why this is recomputed on every
    # show() instead of only once in build().
    _apply_margins(window)
    window._pending = False
    # A scan already in flight (see _on_refresh_clicked/_poll_scan) owns
    # the status line/progress bar and keeps polling across hide/show --
    # don't stomp it, just leave it be.
    if not window._scanning:
        _set_status(window, None)
        _set_progress(window, None)

    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    if not jellyfin_source.is_running():
        window._libraries = []
        window._refresh_button.hide()
        listbox.add(_make_power_row())
        listbox.show_all()
        return

    window._refresh_button.show()

    def worker():
        libraries = jellyfin_source.get_libraries()
        _user_id, policy = jellyfin_source.get_policy()
        scan = jellyfin_source.get_scan_progress()
        return libraries, policy, scan

    def on_done(result):
        window._libraries, window._policy, scan = result
        _render_list(window)
        running, percent = scan
        if running and not window._scanning:
            # A scan is running that this popup didn't start (Jellyfin's
            # own dashboard, or its nightly trigger) -- pick up polling
            # it rather than showing a stale "idle" state.
            window._scanning = True
            _on_scan_progress(window, (running, percent))

    glib_async.call_in_thread(worker, on_done=on_done)


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-jellyfin")
    window.set_decorated(False)

    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_namespace(window, "popup-daemon")
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.RIGHT, True)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.ON_DEMAND)
    _apply_margins(window)

    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    outer.set_border_width(8)

    header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
    title = Gtk.Label(label="Jellyfin Libraries", xalign=0)
    title.get_style_context().add_class("popup-header")
    header.pack_start(title, True, True, 0)
    refresh_button = Gtk.Button(label="Refresh")
    header.pack_end(refresh_button, False, False, 0)
    outer.pack_start(header, False, False, 0)

    status_label = Gtk.Label(xalign=0)
    status_label.get_style_context().add_class("popup-subheader")
    status_label.set_no_show_all(True)
    outer.pack_start(status_label, False, False, 0)

    progress_bar = Gtk.ProgressBar()
    progress_bar.set_no_show_all(True)
    outer.pack_start(progress_bar, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    outer.pack_start(listbox, False, False, 0)

    window.add(outer)
    window._listbox = listbox
    window._status_label = status_label
    window._progress_bar = progress_bar
    window._refresh_button = refresh_button
    window._libraries = []
    window._policy = None
    window._pending = False
    window._scanning = False

    refresh_button.connect("clicked", _on_refresh_clicked, window)

    return window
