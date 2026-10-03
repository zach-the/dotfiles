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
    _set_status(window, None)
    window._pending = False

    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    if not jellyfin_source.is_running():
        window._libraries = []
        listbox.add(_make_power_row())
        listbox.show_all()
        return

    def worker():
        libraries = jellyfin_source.get_libraries()
        _user_id, policy = jellyfin_source.get_policy()
        return libraries, policy

    def on_done(result):
        window._libraries, window._policy = result
        _render_list(window)

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

    title = Gtk.Label(label="Jellyfin Libraries", xalign=0)
    title.get_style_context().add_class("popup-header")
    outer.pack_start(title, False, False, 0)

    status_label = Gtk.Label(xalign=0)
    status_label.get_style_context().add_class("popup-subheader")
    status_label.set_no_show_all(True)
    outer.pack_start(status_label, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    outer.pack_start(listbox, False, False, 0)

    window.add(outer)
    window._listbox = listbox
    window._status_label = status_label
    window._libraries = []
    window._policy = None
    window._pending = False

    return window
