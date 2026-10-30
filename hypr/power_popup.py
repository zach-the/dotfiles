#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "power" target: a layer-shell
popup listing Reboot/Shut Down, same visual language as the other
popups (bluetooth_popup.py's menu/rename Gtk.Stack pages in
particular). Unlike every other target here, this one anchors to the
screen's TOP-LEFT instead of TOP-RIGHT, since the power button sits at
the start of waybar's modules-left rather than among modules-right.

Reboot/shut down both get a one-step confirm page (Gtk.Stack swap, same
mechanism as bluetooth_popup.py's device menu) before anything runs --
there's no undoing either action once systemctl has them, so unlike
every other popup here (which acts immediately on click) this is the
one place that needs a second deliberate click.

No network/async machinery is needed: systemctl reboot/poweroff return
almost immediately (they just hand the request to PID 1 and the actual
shutdown happens later), so a plain subprocess.run is fine on the GTK
thread.

build() is called once at daemon startup; refresh() runs every time the
popup is shown."""
import json
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gdk, Gtk, GtkLayerShell

# Gap below waybar's own bottom edge -- same value the other popups use,
# tuned by eye against the live bar.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's left edge
# to the power module's position in modules-left (it's the first entry
# there, so this is just waybar's own left margin plus the window's own
# margin -- no other module sits to its left). Waybar exposes no
# per-module geometry over IPC, so this has to be tuned by eye against
# the live bar; re-measure if modules-left's order or the bar's margins
# change.
POWER_ANCHOR_MARGIN_LEFT = 8

ACTIONS = {
    "reboot": {"label": "Reboot", "confirm": "Reboot now?", "cmd": ["systemctl", "reboot"]},
    "poweroff": {"label": "Shut Down", "confirm": "Shut down now?", "cmd": ["systemctl", "poweroff"]},
}


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.LEFT, POWER_ANCHOR_MARGIN_LEFT)


# --- Row construction -------------------------------------------------

def _make_action_row(action_id, action):
    row = Gtk.ListBoxRow()
    row.action_id = action_id
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label=action["label"], xalign=0), True, True, 0)
    row.add(box)
    return row


# --- Click handling -----------------------------------------------------

def _on_row_activated(_listbox, row, window):
    action_id = getattr(row, "action_id", None)
    if action_id is None:
        return
    _open_confirm(window, action_id)


def _open_confirm(window, action_id):
    window._pending_action = action_id
    window._confirm_label.set_text(ACTIONS[action_id]["confirm"])
    window._stack.set_visible_child_name("confirm")


def _on_confirm_clicked(_button, window):
    action_id = window._pending_action
    if action_id is None:
        return
    subprocess.run(ACTIONS[action_id]["cmd"], check=False)
    window.hide()


def _on_cancel_clicked(_button, window):
    window._pending_action = None
    window._stack.set_visible_child_name("list")


def _on_window_key_press(window, event):
    if event.keyval == Gdk.KEY_Escape and window._stack.get_visible_child_name() == "confirm":
        _on_cancel_clicked(None, window)
        return True
    return False


# --- Shared ---------------------------------------------------------------

def refresh(window):
    # See audio_popup.py's refresh() for why this is recomputed on every
    # show() instead of only once in build().
    _apply_margins(window)
    window._pending_action = None
    window._stack.set_visible_child_name("list")


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-power")
    window.set_decorated(False)

    GtkLayerShell.init_for_window(window)
    GtkLayerShell.set_layer(window, GtkLayerShell.Layer.OVERLAY)
    GtkLayerShell.set_namespace(window, "popup-daemon")
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.TOP, True)
    GtkLayerShell.set_anchor(window, GtkLayerShell.Edge.LEFT, True)
    GtkLayerShell.set_keyboard_mode(window, GtkLayerShell.KeyboardMode.ON_DEMAND)
    _apply_margins(window)

    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
    outer.set_border_width(8)

    header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
    title = Gtk.Label(label="Power", xalign=0)
    title.get_style_context().add_class("popup-header")
    header.pack_start(title, True, True, 0)
    outer.pack_start(header, False, False, 0)

    stack = Gtk.Stack()
    # Default Gtk.Stack sizing is homogeneous: it allocates space for the
    # tallest page regardless of which one is actually shown, so the
    # shorter "list" page (two rows) was being padded out to match the
    # taller "confirm" page (header + two buttons), leaving dead space
    # below Reboot/Shut Down. Each page should size to its own content.
    stack.set_vhomogeneous(False)
    stack.set_hhomogeneous(False)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    for action_id, action in ACTIONS.items():
        listbox.add(_make_action_row(action_id, action))
    stack.add_named(listbox, "list")

    confirm_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
    confirm_box.set_border_width(6)
    confirm_label = Gtk.Label(xalign=0)
    confirm_label.get_style_context().add_class("popup-header")
    confirm_box.pack_start(confirm_label, False, False, 4)
    confirm_btn = Gtk.Button(label="Confirm")
    confirm_btn.get_style_context().add_class("popup-danger")
    cancel_btn = Gtk.Button(label="Cancel")
    for b in (confirm_btn, cancel_btn):
        b.set_relief(Gtk.ReliefStyle.NONE)
        b.get_child().set_xalign(0)
        confirm_box.pack_start(b, False, False, 0)
    stack.add_named(confirm_box, "confirm")

    outer.pack_start(stack, False, False, 0)
    window.add(outer)

    window._stack = stack
    window._confirm_label = confirm_label
    window._pending_action = None

    listbox.connect("row-activated", _on_row_activated, window)
    confirm_btn.connect("clicked", _on_confirm_clicked, window)
    cancel_btn.connect("clicked", _on_cancel_clicked, window)
    window.connect("key-press-event", _on_window_key_press)

    return window
