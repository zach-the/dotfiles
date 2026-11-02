#!/usr/bin/env python3
"""GTK content for popup_daemon.py's "scrollsesh" target: a layer-shell
popup listing scrollsesh's blocked domains as clickable "Unlock ..." rows
while blocked, or a single "End session" row while one is active -- same
visual language as power_popup.py's action-row list. No second confirm
step is needed here (unlike power's reboot/shutdown): unlocking or ending
a session is trivially reversible.

Reads scrollsesh's own state/config files directly (all world-readable,
/etc/scrollsesh/*) rather than shelling out to the CLI on every refresh.
Row clicks write through the polkit-authorized systemd units
(scrollsesh-start@<domain>.service / scrollsesh-end.service) -- the same
no-sudo path the waybar icon's own on-click used before this popup
existed -- never by writing scrollsesh's files directly from here.

build() is called once at daemon startup; refresh() runs every time the
popup is shown."""
import json
import os
import subprocess
import time

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("GtkLayerShell", "0.1")
from gi.repository import Gtk, GtkLayerShell

BASE = "/etc/scrollsesh"
DOMAINS_PATH = f"{BASE}/domains.txt"
CONFIG_PATH = f"{BASE}/config.env"
STATE_PATH = f"{BASE}/state.json"

# Gap below waybar's own bottom edge -- same value the other popups use,
# tuned by eye against the live bar.
GAP_BELOW_BAR = -12

# Empirically-measured horizontal distance from the screen's right edge to
# the scrollsesh module's position in modules-right. It's the leftmost
# entry there (before jellyfin), so this needs jellyfin_popup.py's own
# 210px -- tuned when JELLYFIN was leftmost -- plus jellyfin's own
# rendered width (~20px padding-left + 15px icon) now that it sits between
# scrollsesh and the rest of the bar. Waybar exposes no per-module
# geometry over IPC, so this is a starting estimate, not a measurement;
# nudge it by eye against the live bar if the icon looks off-center under
# the module.
SCROLLSESH_ANCHOR_MARGIN_RIGHT = 245


def _monitor_reserved_top():
    try:
        out = subprocess.run(["hyprctl", "-j", "monitors"], capture_output=True, check=True, text=True).stdout
        mon = json.loads(out)[0]
        return mon["reserved"][1]
    except Exception:
        return 0


def _apply_margins(window):
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.TOP, _monitor_reserved_top() + GAP_BELOW_BAR)
    GtkLayerShell.set_margin(window, GtkLayerShell.Edge.RIGHT, SCROLLSESH_ANCHOR_MARGIN_RIGHT)


# --- reading scrollsesh's own state (world-readable, no sudo) ----------

def _read_config():
    cfg = {"SESSIONS_PER_DAY": 5, "SESSION_MINUTES": 3}
    if os.path.exists(CONFIG_PATH):
        for line in open(CONFIG_PATH):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            try:
                cfg[k.strip()] = int(v.strip())
            except ValueError:
                pass
    return cfg


def _read_domains():
    if not os.path.exists(DOMAINS_PATH):
        return []
    out = []
    for line in open(DOMAINS_PATH):
        line = line.strip().lower()
        if line and not line.startswith("#"):
            out.append(line)
    return out


def _read_status():
    state = {"sessions_left": 0, "unblocked_until": 0, "active_domain": None}
    if os.path.exists(STATE_PATH):
        try:
            with open(STATE_PATH) as f:
                state.update(json.load(f))
        except (json.JSONDecodeError, OSError):
            pass
    cfg = _read_config()
    now = time.time()
    blocked = not (state.get("unblocked_until") and now < state["unblocked_until"])
    minutes_remaining = 0
    if not blocked:
        minutes_remaining = max(0, int((state["unblocked_until"] - now) // 60) + 1)
    return {
        "blocked": blocked,
        "active_domain": state.get("active_domain") if not blocked else None,
        "sessions_left": state.get("sessions_left", 0),
        "sessions_per_day": cfg["SESSIONS_PER_DAY"],
        "minutes_remaining": minutes_remaining,
    }


# --- row construction -------------------------------------------------

def _make_domain_row(domain):
    row = Gtk.ListBoxRow()
    row.kind = "unlock"
    row.domain = domain
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label=f"Unlock {domain}", xalign=0), True, True, 0)
    row.add(box)
    return row


def _make_end_row(domain, minutes_remaining):
    row = Gtk.ListBoxRow()
    row.kind = "end"
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label=f"End session ({domain}, {minutes_remaining} min left)", xalign=0),
                    True, True, 0)
    row.add(box)
    return row


def _make_info_row(text):
    row = Gtk.ListBoxRow(activatable=False, selectable=False)
    box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
    box.set_border_width(6)
    box.pack_start(Gtk.Label(label=text, xalign=0), True, True, 0)
    row.add(box)
    return row


# --- click handling -----------------------------------------------------

def _on_row_activated(_listbox, row, window):
    kind = getattr(row, "kind", None)
    if kind == "unlock":
        subprocess.run(["systemctl", "start", f"scrollsesh-start@{row.domain}.service"], check=False)
    elif kind == "end":
        subprocess.run(["systemctl", "start", "scrollsesh-end.service"], check=False)
    else:
        return
    window.hide()


# --- shared ---------------------------------------------------------------

def refresh(window):
    _apply_margins(window)
    listbox = window._listbox
    for child in listbox.get_children():
        listbox.remove(child)

    st = _read_status()
    if not st["blocked"]:
        listbox.add(_make_end_row(st["active_domain"], st["minutes_remaining"]))
    else:
        domains = _read_domains()
        if not domains:
            listbox.add(_make_info_row("No domains configured"))
        elif st["sessions_left"] <= 0:
            listbox.add(_make_info_row("No sessions left today"))
        else:
            for d in domains:
                listbox.add(_make_domain_row(d))
    listbox.show_all()
    window._status_label.set_text(f"{st['sessions_left']}/{st['sessions_per_day']} sessions left today")


def build():
    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.get_style_context().add_class("popup-scrollsesh")
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
    title = Gtk.Label(label="scrollsesh", xalign=0)
    title.get_style_context().add_class("popup-header")
    header.pack_start(title, True, True, 0)
    outer.pack_start(header, False, False, 0)

    status_label = Gtk.Label(xalign=0)
    status_label.get_style_context().add_class("popup-subheader")
    outer.pack_start(status_label, False, False, 0)

    listbox = Gtk.ListBox(selection_mode=Gtk.SelectionMode.NONE)
    listbox.set_activate_on_single_click(True)
    listbox.connect("row-activated", _on_row_activated, window)
    outer.pack_start(listbox, False, False, 0)

    window.add(outer)
    window._listbox = listbox
    window._status_label = status_label

    return window
