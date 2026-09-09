#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "audio" target: a layer-shell
popup listing WirePlumber audio sinks (via audio_source.py, ported
from the old audio_menu.py curses TUI). Click a row to make it the
default output; the popup closes itself shortly after so the
selection is visible for a beat first.

The "Multi-Output" switch in the header flips the list into
checkbox/slider mode, driving audio_source.py's PipeWire combine-sink
support (the same mechanism bin/audio-combine uses): check 2+ boxes to
fan output to all of them at once, with a per-output volume slider
appearing under each checked row. In that mode, the popup does not
auto-close on click -- selecting is a multi-step process -- and
waybar's existing scroll/click volume bindings keep working unchanged,
since they always act on @DEFAULT_AUDIO_SINK@, which becomes the
combine sink itself once 2+ outputs are checked; that gives "global"
volume control for free, no separate wiring needed.

build() is called once at daemon startup; refresh() is called every
time the popup is shown, whenever a checkbox changes, and whenever
popup_daemon.py's `pactl subscribe` watcher sees a sink/default change
while it's visible (skipped while a slider is being dragged -- see
window._dragging -- since dragging itself generates the same
subscribe events that would otherwise rebuild the very slider being
dragged out from under the pointer)."""
import json
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gtk, GtkLayerShell

import audio_source

# Gap below waybar's own bottom edge. Tuned by eye against the live bar
# (see AUDIO_ANCHOR_MARGIN_RIGHT below for why this can't be computed
# analytically) to sit close under it rather than leaving visible dead
# space.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge
# to the volume module's position in modules-right (bluetooth + backlight
# + wifi + battery icons, their spacing, and waybar's own right margin).
# Waybar exposes no per-module geometry over IPC, so this has to be
# tuned by eye against the live bar; re-measure if modules-right's
# order, icon sizes, or font changes.
AUDIO_ANCHOR_MARGIN_RIGHT = 110

# How long a just-picked row stays visibly marked before the popup
# closes itself, mirroring the old curses popup's same pause. Only
# applies to single-output mode -- Multi-Output never auto-closes.
CLOSE_DELAY_MS = 150

# How long to wait after the last checkbox change before actually
# tearing down/recreating the combine sink, so checking several boxes
# in quick succession costs one rebuild instead of one per click.
COMBINE_APPLY_DEBOUNCE_MS = 300

# Same idea for slider drags: collapse a burst of value-changed signals
# into one wpctl call instead of one per pixel of drag.
SLIDER_DEBOUNCE_MS = 80

VOLUME_MAX = 150


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, AUDIO_ANCHOR_MARGIN_RIGHT)


# --- Single-output (radio) rows ------------------------------------------

def _make_single_row(sink):
    row = Gtk.ListBoxRow()
    row.sink_id = sink["id"]

    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    marker = Gtk.Label(label="●" if sink["default"] else "○")
    name = Gtk.Label(label=sink["name"], xalign=0)
    box.pack_start(marker, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _on_row_activated(_listbox, row, window):
    if not hasattr(row, "sink_id"):
        return
    if window._switch.get_active():
        sink_id = row.sink_id
        if sink_id in window._checked:
            window._checked.discard(sink_id)
        else:
            window._checked.add(sink_id)
        refresh(window)
        _schedule_combine_apply(window)
        return
    audio_source.set_default(row.sink_id)
    refresh(window)
    GLib.timeout_add(CLOSE_DELAY_MS, lambda: window.hide() or False)


# --- Multi-Output (toggle marker + slider) rows ---------------------------

def _schedule_slider_apply(window, sink_id, value):
    pending = window._slider_debounce.pop(sink_id, None)
    if pending is not None:
        GLib.source_remove(pending)

    def _apply():
        window._slider_debounce.pop(sink_id, None)
        audio_source.set_volume(sink_id, value)
        return False

    window._slider_debounce[sink_id] = GLib.timeout_add(SLIDER_DEBOUNCE_MS, _apply)


def _on_scale_changed(scale, window, sink_id):
    _schedule_slider_apply(window, sink_id, scale.get_value())


def _on_scale_pressed(_scale, _event, window):
    window._dragging = True
    return False


def _on_scale_released(_scale, _event, window):
    window._dragging = False
    return False


def _make_multi_row(sink, window, checked):
    # Same ●/○ marker as the single-output rows -- clicking anywhere on
    # the row (handled by _on_row_activated above) toggles it in/out of
    # window._checked instead of exclusively selecting it. Plain GTK
    # checkboxes were tried here first and looked dated next to the
    # rest of this UI; this reuses the existing visual language instead
    # of fighting GTK3's default checkbox indicator styling.
    row = Gtk.ListBoxRow()
    row.sink_id = sink["id"]

    outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)

    top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    top.set_border_width(6)
    marker = Gtk.Label(label="●" if checked else "○")
    name = Gtk.Label(label=sink["name"], xalign=0)
    top.pack_start(marker, False, False, 0)
    top.pack_start(name, True, True, 0)
    outer.pack_start(top, False, False, 0)

    if checked:
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, VOLUME_MAX, 1)
        scale.set_value(audio_source.get_volume(sink["id"]))
        scale.set_draw_value(False)
        scale.connect("value-changed", _on_scale_changed, window, sink["id"])
        scale.connect("button-press-event", _on_scale_pressed, window)
        scale.connect("button-release-event", _on_scale_released, window)
        outer.pack_start(scale, False, False, 0)

    row.add(outer)
    return row


def _schedule_combine_apply(window):
    if window._combine_apply_source is not None:
        GLib.source_remove(window._combine_apply_source)

    def _apply():
        window._combine_apply_source = None
        _apply_combine(window)
        return False

    window._combine_apply_source = GLib.timeout_add(COMBINE_APPLY_DEBOUNCE_MS, _apply)


def _apply_combine(window):
    checked = [window._sinks_by_id[i] for i in window._checked if i in window._sinks_by_id]
    names = [s["pactl_name"] for s in checked if s.get("pactl_name")]
    existing = audio_source.find_combine_module()

    if len(names) >= 2:
        if existing:
            audio_source.remove_combine(existing["module_id"])
        audio_source.create_combine(names)
    elif len(names) == 1:
        if existing:
            audio_source.remove_combine(existing["module_id"])
        audio_source.set_default(checked[0]["id"])
    elif existing:
        audio_source.remove_combine(existing["module_id"])

    refresh(window)


def _on_switch_toggled(switch, _pspec, window):
    if switch.get_active():
        existing = audio_source.find_combine_module()
        if existing:
            window._checked = {
                sid for sid, s in window._sinks_by_id.items()
                if s.get("pactl_name") in existing["slaves"]
            }
        else:
            window._checked = {sid for sid, s in window._sinks_by_id.items() if s["default"]}
    else:
        existing = audio_source.find_combine_module()
        if existing:
            audio_source.remove_combine(existing["module_id"])
        window._checked = set()
    refresh(window)


# --- Shared ---------------------------------------------------------------

def refresh(window):
    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    sinks = audio_source.get_sinks()
    window._sinks_by_id = {s["id"]: s for s in sinks}
    multi = window._switch.get_active()

    if not sinks:
        empty = Gtk.ListBoxRow(activatable=False, selectable=False)
        empty.add(Gtk.Label(label="No output devices found"))
        listbox.add(empty)
    elif multi:
        for sink in sinks:
            listbox.add(_make_multi_row(sink, window, sink["id"] in window._checked))
    else:
        for sink in sinks:
            listbox.add(_make_single_row(sink))
    listbox.show_all()


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-audio")
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
    title = Gtk.Label(label="Audio Output", xalign=0)
    title.get_style_context().add_class("popup-header")
    header.pack_start(title, True, True, 0)

    switch = Gtk.Switch()
    switch.set_valign(Gtk.Align.CENTER)
    header.pack_end(switch, False, False, 0)
    multi_label = Gtk.Label(label="Multi-Output")
    multi_label.get_style_context().add_class("popup-subheader")
    header.pack_end(multi_label, False, False, 0)

    outer.pack_start(header, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    outer.pack_start(listbox, False, False, 0)

    window.add(outer)
    window._listbox = listbox
    window._switch = switch
    window._checked = set()
    window._sinks_by_id = {}
    window._dragging = False
    window._combine_apply_source = None
    window._slider_debounce = {}

    # Prime state from whatever's actually active right now (e.g. this
    # daemon restarted while a combine sink from a previous session was
    # still loaded) *before* wiring the switch's own signal, so this
    # doesn't also trigger _on_switch_toggled's (harmless but redundant)
    # re-derivation of the same thing.
    existing = audio_source.find_combine_module()
    if existing:
        window._sinks_by_id = {s["id"]: s for s in audio_source.get_sinks()}
        window._checked = {
            sid for sid, s in window._sinks_by_id.items()
            if s.get("pactl_name") in existing["slaves"]
        }
        switch.set_active(True)

    switch.connect("notify::active", _on_switch_toggled, window)

    return window
