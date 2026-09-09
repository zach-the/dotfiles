#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "wifi" target: a layer-shell popup
listing nearby Wi-Fi networks (via wifi_source.py, ported from the old
wifi_menu.py curses TUI). Click a network to connect; if it's secured
and nmcli has no saved profile, a password sub-view (a second page of
the same window's Gtk.Stack — never a second window) asks for one.

Scanning runs via glib_async.run_subprocess_async so nmcli's multi-
second scan never blocks the daemon's GTK loop; try_connect() (which
can block up to wifi_source.CONNECT_TIMEOUT seconds) runs via
glib_async.call_in_thread for the same reason.

build() is called once at daemon startup; refresh() runs every time
the popup is shown, kicking off a fresh scan."""
import json
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, GLib, Gtk, GtkLayerShell

import glib_async
import wifi_source

# Gap below waybar's own bottom edge -- see audio_popup.py's own
# GAP_BELOW_BAR for the reasoning; same tuning approach, separate
# constant since this popup sits over a different part of the bar.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge
# to the wifi module's position in modules-right (custom/wifi sits
# between custom/backlight and custom/battery). Waybar exposes no
# per-module geometry over IPC, so this has to be tuned by eye against
# the live bar; re-measure if modules-right's order, icon sizes, or
# font changes.
WIFI_ANCHOR_MARGIN_RIGHT = 10

# How long "Connected to X" stays visible before the popup closes
# itself, mirroring the old curses popup's same pause before it
# returned/closed on a successful connection.
CLOSE_DELAY_MS = 700


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, WIFI_ANCHOR_MARGIN_RIGHT)


# --- List page -------------------------------------------------------------

def _make_network_row(net):
    row = Gtk.ListBoxRow()
    row.ssid = net["ssid"]

    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    marker = Gtk.Label(label="●" if net["connected"] else "○")
    # A Nerd Font glyph rather than the 🔒 emoji, which renders in color
    # (yellow) via the system emoji font instead of matching the rest
    # of this monochrome UI.
    lock = Gtk.Label(label="" if net["secured"] else "  ")
    lock.get_style_context().add_class("lock-icon")
    name = Gtk.Label(label=net["ssid"], xalign=0)
    box.pack_start(marker, False, False, 0)
    box.pack_start(lock, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _render_list(window):
    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    if window._scanning:
        row = Gtk.ListBoxRow(activatable=False, selectable=False)
        row.add(Gtk.Label(label="Scanning networks…"))
        listbox.add(row)
    elif not window._networks:
        row = Gtk.ListBoxRow(activatable=False, selectable=False)
        row.add(Gtk.Label(label="No networks found"))
        listbox.add(row)
    else:
        for net in window._networks:
            listbox.add(_make_network_row(net))
    listbox.show_all()

    if window._status:
        window._status_label.set_text(window._status)
        window._status_label.set_visible(True)
    else:
        window._status_label.set_visible(False)


def _start_scan(window):
    window._scanning = True
    window._status = None
    _render_list(window)

    lines = []

    def on_exit(_status):
        window._scanning = False
        window._networks = wifi_source.parse_networks(lines)
        _render_list(window)

    glib_async.run_subprocess_async(wifi_source.SCAN_CMD, on_line=lines.append, on_exit=on_exit)


def _on_row_activated(_listbox, row, window):
    if not hasattr(row, "ssid"):
        return
    net = next((n for n in window._networks if n["ssid"] == row.ssid), None)
    if net is None:
        return
    _attempt_connect(window, net, password=None)


# --- Password page -----------------------------------------------------

def _show_password_page(window, net):
    window._pending_net = net
    window._password_label.set_text(f"Password for {net['ssid']}")
    window._password_entry.set_text("")
    window._stack.set_visible_child_name("password")
    window._password_entry.grab_focus()


def _on_password_activate(entry, window):
    _attempt_connect(window, window._pending_net, entry.get_text())


def _on_password_key(_entry, event, window):
    if event.keyval == Gdk.KEY_Escape:
        window._stack.set_visible_child_name("list")
        _render_list(window)
        return True
    return False


# --- Connecting ----------------------------------------------------------

def _attempt_connect(window, net, password):
    window._stack.set_visible_child_name("list")
    window._status = f"Connecting to {net['ssid']}…"
    _render_list(window)

    def worker():
        return wifi_source.try_connect(net["ssid"], password)

    def on_done(result):
        ok, _err = result
        if ok:
            window._status = f"Connected to {net['ssid']}"
            _render_list(window)
            GLib.timeout_add(CLOSE_DELAY_MS, lambda: window.hide() or False)
        elif net["secured"] and password is None:
            # No saved profile (or it needs new credentials) -- ask,
            # same as the old curses popup's one-shot prompt.
            _show_password_page(window, net)
        else:
            window._status = "Wrong password or connection failed"
            _render_list(window)

    glib_async.call_in_thread(worker, on_done=on_done)


# --- Shared ---------------------------------------------------------------

def refresh(window):
    # See audio_popup.py's refresh() for why this is recomputed on every
    # show() instead of only once in build().
    _apply_margins(window)
    window._stack.set_visible_child_name("list")
    _start_scan(window)


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-wifi")
    window.set_decorated(False)

    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_namespace(window, "popup-daemon")
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.RIGHT, True)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.ON_DEMAND)
    _apply_margins(window)

    stack = Gtk.Stack()

    # --- list page ---
    list_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    list_page.set_border_width(8)
    title = Gtk.Label(label="Wi-Fi Networks", xalign=0)
    title.get_style_context().add_class("popup-header")
    list_page.pack_start(title, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    list_page.pack_start(listbox, False, False, 0)

    status_label = Gtk.Label(xalign=0)
    status_label.get_style_context().add_class("popup-subheader")
    status_label.set_no_show_all(True)
    status_label.set_visible(False)
    list_page.pack_start(status_label, False, False, 0)

    stack.add_named(list_page, "list")

    # --- password page ---
    pw_page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
    pw_page.set_border_width(8)
    pw_label = Gtk.Label(xalign=0)
    pw_label.get_style_context().add_class("popup-header")
    pw_page.pack_start(pw_label, False, False, 0)

    pw_entry = Gtk.Entry()
    pw_entry.set_visibility(False)
    pw_entry.connect("activate", _on_password_activate, window)
    pw_entry.connect("key-press-event", _on_password_key, window)
    pw_page.pack_start(pw_entry, False, False, 0)

    hint = Gtk.Label(label="Enter to connect · Esc to cancel", xalign=0)
    hint.get_style_context().add_class("popup-subheader")
    pw_page.pack_start(hint, False, False, 0)

    stack.add_named(pw_page, "password")

    window.add(stack)

    window._stack = stack
    window._listbox = listbox
    window._status_label = status_label
    window._password_label = pw_label
    window._password_entry = pw_entry
    window._networks = []
    window._scanning = False
    window._status = None
    window._pending_net = None

    return window
