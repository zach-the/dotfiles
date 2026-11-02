#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "mic" target: a layer-shell popup
listing WirePlumber audio sources (via audio_source.py's
get_sources()/set_default_source()), mirroring audio_popup.py's
single-output picker for sinks. Click a row to make it the default
input; the popup closes itself shortly after, same as the output
picker.

Unlike audio_popup.py there's no Multi-Output-equivalent here (no
combine-source feature -- selecting more than one input at once isn't
a thing wpctl/PipeWire support the way module-combine-sink lets
several outputs fan out together), so this is just the single-output
picker's logic reused for sources, plus one addition: a persistent
volume slider below the list, always bound to whichever source is
currently default, so mic gain can be set precisely instead of only
in 10%-per-click waybar scroll steps.

build() is called once at daemon startup; refresh() every time the
popup is shown, whenever popup_daemon.py's `pactl subscribe` watcher
sees a source/default change while it's visible (skipped while the
slider is being dragged -- see window._dragging -- for the same reason
audio_popup.py skips it during a Multi-Output slider drag)."""
import json
import subprocess

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import GLib, Gtk, GtkLayerShell

import audio_source
from audio_popup import _monitor_reserved_top

GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge
# to the mic module's position in modules-right (custom/mic sits just
# left of custom/volume -- see AUDIO_ANCHOR_MARGIN_RIGHT in
# audio_popup.py for why this can't be computed analytically instead).
MIC_ANCHOR_MARGIN_RIGHT = 134

CLOSE_DELAY_MS = 150
SLIDER_DEBOUNCE_MS = 80
VOLUME_MAX = 150


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, MIC_ANCHOR_MARGIN_RIGHT)


def _make_row(source):
    row = Gtk.ListBoxRow()
    row.source_id = source["id"]

    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    marker = Gtk.Label(label="●" if source["default"] else "○")
    name = Gtk.Label(label=source["name"], xalign=0)
    box.pack_start(marker, False, False, 0)
    box.pack_start(name, True, True, 0)
    row.add(box)
    return row


def _on_row_activated(_listbox, row, window):
    if not hasattr(row, "source_id"):
        return
    audio_source.set_default_source(row.source_id)
    refresh(window)
    GLib.timeout_add(CLOSE_DELAY_MS, lambda: window.hide() or False)


def _schedule_slider_apply(window, source_id, value):
    pending = window._slider_debounce.pop(source_id, None)
    if pending is not None:
        GLib.source_remove(pending)

    def _apply():
        window._slider_debounce.pop(source_id, None)
        audio_source.set_source_volume(source_id, value)
        return False

    window._slider_debounce[source_id] = GLib.timeout_add(SLIDER_DEBOUNCE_MS, _apply)


def _on_scale_changed(scale, window):
    if window._current_source_id is not None:
        _schedule_slider_apply(window, window._current_source_id, scale.get_value())


def _on_scale_pressed(_scale, _event, window):
    window._dragging = True
    return False


def _on_scale_released(_scale, _event, window):
    window._dragging = False
    return False


def refresh(window):
    # Recomputed on every show(), not just once in build() -- see
    # audio_popup.py's refresh() for why (a startup-ordering race with
    # waybar's own exclusive-zone registration).
    _apply_margins(window)

    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    sources = audio_source.get_sources()

    if not sources:
        empty = Gtk.ListBoxRow(activatable=False, selectable=False)
        empty.add(Gtk.Label(label="No input devices found"))
        listbox.add(empty)
        window._current_source_id = None
        window._scale.set_sensitive(False)
    else:
        for source in sources:
            listbox.add(_make_row(source))
        default = next((s for s in sources if s["default"]), sources[0])
        window._current_source_id = default["id"]
        window._scale.set_sensitive(True)
        if not window._dragging:
            window._scale.set_value(audio_source.get_source_volume(default["id"]))
    listbox.show_all()


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-mic")
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

    title = Gtk.Label(label="Microphone Input", xalign=0)
    title.get_style_context().add_class("popup-header")
    outer.pack_start(title, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    outer.pack_start(listbox, False, False, 0)

    scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, VOLUME_MAX, 1)
    scale.set_draw_value(False)
    scale.set_margin_top(4)
    scale.connect("value-changed", _on_scale_changed, window)
    scale.connect("button-press-event", _on_scale_pressed, window)
    scale.connect("button-release-event", _on_scale_released, window)
    outer.pack_start(scale, False, False, 0)

    window.add(outer)
    window._listbox = listbox
    window._scale = scale
    window._current_source_id = None
    window._dragging = False
    window._slider_debounce = {}

    return window
