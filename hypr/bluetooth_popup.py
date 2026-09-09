#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "bluetooth" target: a layer-shell
popup listing paired Bluetooth devices (via bluetooth_source.py, ported
from the old bluetooth_menu.py curses TUI). Click a device to connect
it, or to disconnect if it's already connected -- unlike Wi-Fi, several
Bluetooth devices can be connected at once (mouse + headphones, say),
so this is a toggle rather than a single-select list. If Bluetooth
itself is off, shows a single row to turn it on instead of a device
list.

A "Search" button in the header kicks off a scan for nearby devices;
anything bluetoothd knows about but that isn't paired yet is listed
below a divider under the known devices. Clicking one of those pairs,
trusts, and connects it in one step.

Right-clicking a paired device opens a small device menu (Rename /
Forget), and Rename opens a text-entry view -- both implemented as
Gtk.Stack pages swapped within the one persistent window rather than
separate windows, matching this framework's one-window-per-target
design. Escape (or the menu's own Cancel button) returns to the list.

Pairing/connecting/disconnecting/scanning all shell out to
bluetoothctl and can take several seconds, so they run via
glib_async.call_in_thread (a blocking Popen.wait() in a background
thread, result delivered back to the GTK thread) rather than blocking
this daemon's single GTK main loop.

build() is called once at daemon startup; refresh() is called on show
and after every action completes."""
import json
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

import bluetooth_source
import glib_async

# Gap below waybar's own bottom edge -- same value audio_popup.py uses,
# tuned by eye against the same bar.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge
# to the bluetooth module's position in modules-right (backlight + wifi
# + battery icons, their spacing, and waybar's own right margin --
# bluetooth sits just right of volume, so this is smaller than
# audio_popup.py's AUDIO_ANCHOR_MARGIN_RIGHT). Waybar exposes no
# per-module geometry over IPC, so this has to be tuned by eye against
# the live bar; re-measure if modules-right's order, icon sizes, or
# font changes.
BLUETOOTH_ANCHOR_MARGIN_RIGHT = 35

# How long a just-completed successful connect/disconnect/pair stays
# visible before the popup closes itself, mirroring the old curses
# popup's same behavior (it `break`s out of its loop on success).
CLOSE_DELAY_MS = 400

# Ellipsis animation tick while a scan is running.
SCAN_DOT_INTERVAL_MS = 1000
SCAN_DOT_MAX = 3


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, BLUETOOTH_ANCHOR_MARGIN_RIGHT)


def _set_status(window, text):
    if text:
        window._status_label.set_text(text)
        window._status_label.show()
    else:
        window._status_label.hide()


# --- Row construction -------------------------------------------------

def _make_known_row(d):
    row = Gtk.ListBoxRow()
    row.mac = d["mac"]
    row.kind = "known"
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    marker = Gtk.Label(label="●" if d["connected"] else "○")
    name = Gtk.Label(label=d["name"], xalign=0)
    box.pack_start(marker, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _make_available_row(d):
    row = Gtk.ListBoxRow()
    row.mac = d["mac"]
    row.kind = "available"
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    plus = Gtk.Label(label="+")
    name = Gtk.Label(label=d["name"], xalign=0)
    box.pack_start(plus, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _make_power_row():
    row = Gtk.ListBoxRow()
    row.kind = "power"
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label="Turn Bluetooth on", xalign=0), True, True, 0)
    row.add(box)
    return row


def _make_divider():
    row = Gtk.ListBoxRow(activatable=False, selectable=False)
    row.kind = "divider"
    row.add(Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL))
    return row


# --- List page click handling -------------------------------------------

def _on_row_activated(_listbox, row, window):
    if window._pending is not None:
        return
    kind = getattr(row, "kind", None)

    if kind == "power":
        _set_status(window, "Turning on...")
        bluetooth_source.set_power(True)
        # Mirrors the old curses popup's own 0.5s settle-then-recheck --
        # done via a timeout instead of blocking this GTK loop with sleep().
        GLib.timeout_add(500, lambda: (_finish_power_on(window), False)[1])
        return

    if kind not in ("known", "available"):
        return

    items = window._devices if kind == "known" else window._available
    d = bluetooth_source.find_by_mac(items, row.mac)
    if d is None:
        return
    connected = d.get("connected", False)
    verb = "Pairing with" if kind == "available" else ("Disconnecting from" if connected else "Connecting to")
    _set_status(window, f"{verb} {d['name']}...")
    window._pending = {"mac": row.mac, "kind": kind, "was_connected": connected}
    proc = bluetooth_source.start_toggle(row.mac, connected, kind)
    glib_async.call_in_thread(proc.wait, on_done=lambda _code: _on_toggle_done(window))


def _finish_power_on(window):
    refresh(window)
    _set_status(window, None)


def _on_toggle_done(window):
    pending = window._pending
    window._pending = None
    subprocess.run(["pkill", "-RTMIN+9", "waybar"], capture_output=True, check=False)
    refresh(window)
    # bluetoothctl's exit code isn't trustworthy here (a `connect` to an
    # unreachable device still exits 0) -- check what actually happened.
    ok = bluetooth_source.check_toggle_success(pending["mac"], pending["kind"], pending["was_connected"])
    if ok:
        _set_status(window, None)
        GLib.timeout_add(CLOSE_DELAY_MS, lambda: window.hide() or False)
    else:
        _set_status(window, "Connection failed")


def _on_listbox_button_press(listbox, event, window):
    if event.button != 3 or window._pending is not None:
        return False
    row = listbox.get_row_at_y(int(event.y))
    if row is None or getattr(row, "kind", None) != "known":
        return False
    d = bluetooth_source.find_by_mac(window._devices, row.mac)
    if d is None:
        return False
    _open_device_menu(window, d)
    return True


# --- Search -------------------------------------------------------------

def _on_search_clicked(_button, window):
    if window._scanning or window._pending is not None:
        return
    window._scanning = True
    window._scan_dots = 0
    _set_status(window, "Searching")
    proc = bluetooth_source.start_scan()
    window._scan_dot_source = GLib.timeout_add(SCAN_DOT_INTERVAL_MS, lambda: _tick_scan_dots(window))
    glib_async.call_in_thread(proc.wait, on_done=lambda _code: _on_scan_done(window))


def _tick_scan_dots(window):
    if not window._scanning:
        return False
    window._scan_dots = (window._scan_dots + 1) % (SCAN_DOT_MAX + 1)
    if window._pending is None:
        _set_status(window, "Searching" + "." * window._scan_dots)
    return True


def _on_scan_done(window):
    window._scanning = False
    if window._scan_dot_source is not None:
        GLib.source_remove(window._scan_dot_source)
        window._scan_dot_source = None
    # A connect/disconnect/pair mid-flight owns the status line and the
    # eventual refresh -- don't stomp it here.
    if window._pending is None:
        refresh(window)
        _set_status(window, None)


# --- Device menu / rename pages ------------------------------------------

def _open_device_menu(window, device):
    window._menu_device = device
    window._menu_name_label.set_text(device["name"])
    window._stack.set_visible_child_name("menu")


def _on_menu_rename_clicked(_button, window):
    window._rename_entry.set_text(window._menu_device["name"])
    window._stack.set_visible_child_name("rename")
    window._rename_entry.grab_focus()


def _on_menu_forget_clicked(_button, window):
    bluetooth_source.forget_device(window._menu_device["mac"])
    subprocess.run(["pkill", "-RTMIN+9", "waybar"], capture_output=True, check=False)
    window._stack.set_visible_child_name("list")
    refresh(window)


def _on_menu_cancel_clicked(_button, window):
    window._stack.set_visible_child_name("list")


def _on_rename_activate(entry, window):
    new_name = entry.get_text().strip()
    current = window._menu_device["name"]
    if new_name and new_name != current:
        bluetooth_source.rename_device(window._menu_device["mac"], new_name)
    window._stack.set_visible_child_name("list")
    refresh(window)


def _on_window_key_press(window, event):
    if event.keyval == Gdk.KEY_Escape and window._stack.get_visible_child_name() in ("menu", "rename"):
        window._stack.set_visible_child_name("list")
        return True
    return False


# --- Shared ---------------------------------------------------------------

def refresh(window):
    window._stack.set_visible_child_name("list")
    window._powered = bluetooth_source.is_powered()
    window._search_button.set_visible(window._powered)

    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    if not window._powered:
        window._devices, window._available = [], []
        listbox.add(_make_power_row())
        listbox.show_all()
        return

    window._devices, window._available = bluetooth_source.get_devices()
    if not window._devices:
        empty = Gtk.ListBoxRow(activatable=False, selectable=False)
        empty.add(Gtk.Label(label="No paired devices"))
        listbox.add(empty)
    else:
        for d in window._devices:
            listbox.add(_make_known_row(d))

    if window._available:
        listbox.add(_make_divider())
        for d in window._available:
            listbox.add(_make_available_row(d))

    listbox.show_all()


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-bluetooth")
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
    title = Gtk.Label(label="Bluetooth", xalign=0)
    title.get_style_context().add_class("popup-header")
    header.pack_start(title, True, True, 0)
    search_button = Gtk.Button(label="Search")
    header.pack_end(search_button, False, False, 0)
    outer.pack_start(header, False, False, 0)

    status_label = Gtk.Label(xalign=0)
    status_label.get_style_context().add_class("popup-subheader")
    status_label.set_no_show_all(True)
    outer.pack_start(status_label, False, False, 0)

    stack = Gtk.Stack()

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    stack.add_named(listbox, "list")

    menu_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    menu_box.set_border_width(6)
    menu_name_label = Gtk.Label(xalign=0)
    menu_name_label.get_style_context().add_class("popup-header")
    menu_box.pack_start(menu_name_label, False, False, 4)
    rename_btn = Gtk.Button(label="Rename")
    forget_btn = Gtk.Button(label="Forget")
    cancel_btn = Gtk.Button(label="Cancel")
    for b in (rename_btn, forget_btn, cancel_btn):
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.get_child().set_xalign(0)
        menu_box.pack_start(b, False, False, 0)
    stack.add_named(menu_box, "menu")

    rename_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    rename_box.set_border_width(6)
    rename_title = Gtk.Label(label="Rename device", xalign=0)
    rename_title.get_style_context().add_class("popup-header")
    rename_entry = Gtk.Entry()
    rename_hint = Gtk.Label(label="Enter to save · Esc to cancel", xalign=0)
    rename_hint.get_style_context().add_class("popup-subheader")
    rename_box.pack_start(rename_title, False, False, 0)
    rename_box.pack_start(rename_entry, False, False, 0)
    rename_box.pack_start(rename_hint, False, False, 0)
    stack.add_named(rename_box, "rename")

    outer.pack_start(stack, False, False, 0)
    window.add(outer)

    window._stack = stack
    window._listbox = listbox
    window._status_label = status_label
    window._search_button = search_button
    window._menu_name_label = menu_name_label
    window._rename_entry = rename_entry
    window._devices = []
    window._available = []
    window._powered = True
    window._pending = None
    window._scanning = False
    window._scan_dots = 0
    window._scan_dot_source = None
    window._menu_device = None

    listbox.connect("row-activated", _on_row_activated, window)
    listbox.connect("button-press-event", _on_listbox_button_press, window)
    search_button.connect("clicked", _on_search_clicked, window)
    rename_btn.connect("clicked", _on_menu_rename_clicked, window)
    forget_btn.connect("clicked", _on_menu_forget_clicked, window)
    cancel_btn.connect("clicked", _on_menu_cancel_clicked, window)
    rename_entry.connect("activate", _on_rename_activate, window)
    window.connect("key-press-event", _on_window_key_press)

    return window
