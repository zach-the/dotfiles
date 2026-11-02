#!/usr/bin/env python3
"""Pure audio-sink logic (no curses, no GTK) shared by audio_popup.py
(popup_daemon.py's audio target) and, potentially, volume_color.py.
Ported from the old audio_menu.py curses TUI, which this replaces.

Also owns Multi-Output support: a PipeWire "combine sink" (via
pipewire-pulse's module-combine-sink, the same mechanism bin/audio-combine
uses) that fans a single default output out to several physical sinks at
once."""
import os
import re
import subprocess

# Fixed name for our combine sink (rather than a per-invocation random
# name like bin/audio-combine's `pw_combo_$$`) so it can be found again
# by name alone on any later call, including after this daemon restarts
# -- no in-memory state needs to survive, matching how everything else
# here re-derives truth from pactl/wpctl on demand instead of caching it.
COMBINE_SINK_NAME = "waybar_combined"


def get_sinks():
    """List real (non-combine) sinks: id, display name, whether it's the
    current default, and its pactl-facing name (needed for
    module-combine-sink's slaves= list; see _pactl_sink_info's docstring
    for why this can't just be derived from the id)."""
    out = subprocess.run(["wpctl", "status"], capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == "Audio"), None)
    if start is None:
        return []
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() == "Video"), len(lines))
    audio_lines = lines[start:end]

    pactl_info = _pactl_sink_info()

    sinks = []
    in_sinks = False
    for line in audio_lines:
        stripped = line.strip()
        if stripped.endswith("Sinks:"):
            in_sinks = True
            continue
        if in_sinks and (stripped.endswith("Sources:") or stripped.endswith("Filters:")):
            break
        if in_sinks:
            m = re.match(r"^[│\s]*(\*)?\s*(\d+)\.\s+(.*?)\s*\[vol:", stripped)
            if not m:
                continue
            raw_name = m.group(3).strip()
            # Never list our own combine sink as something you could
            # select/combine into itself.
            if raw_name == COMBINE_SINK_NAME:
                continue
            info = pactl_info.get(raw_name)
            if info and info["unavailable"]:
                continue
            sinks.append({
                "id": m.group(2),
                "raw_name": raw_name,
                "name": raw_name,
                "default": m.group(1) is not None,
                "pactl_name": info["pactl_name"] if info else None,
            })

    names = simplify_names([s["raw_name"] for s in sinks])
    for s, name in zip(sinks, names):
        s["name"] = name
    return sinks


def _pactl_sink_info():
    """Map each sink's raw hardware description (which matches wpctl's
    raw sink name exactly, before simplify_names() shortens it) to its
    pactl-facing sink name and jack-sensed availability.

    pactl's own "Sink #N" numbering is a *different, unrelated* id
    namespace from wpctl's ids -- e.g. on this machine wpctl calls the
    built-in speaker sink 92, pactl calls that same sink Sink #94 --
    despite both being small integers in a similar range. The old
    audio_menu.py this replaces compared pactl's Sink # directly
    against wpctl's id, which only ever "worked" by numeric
    coincidence. Description text is the one field both tools render
    identically for the same sink, so it's the correct join key."""
    try:
        out = subprocess.run(["pactl", "list", "sinks"], capture_output=True, text=True, check=True).stdout
    except Exception:
        return {}

    info = {}
    for block in re.split(r"(?m)^Sink #\d+\n", out)[1:]:
        name_m = re.search(r"^\tName: (.+)$", block, re.M)
        desc_m = re.search(r"^\tDescription: (.+)$", block, re.M)
        if not (name_m and desc_m):
            continue
        unavailable = False
        active_m = re.search(r"Active Port:\s*(.+)", block)
        if active_m:
            port_m = re.search(re.escape(active_m.group(1).strip()) + r":.*\(([^)]*)\)", block)
            unavailable = bool(port_m and "not available" in port_m.group(1))
        info[desc_m.group(1).strip()] = {
            "pactl_name": name_m.group(1).strip(),
            "unavailable": unavailable,
        }
    return info


def simplify_names(names):
    """Strip the shared device-description prefix (e.g. "Core Ultra
    Processors (Series 3) HD Audio ") that ALSA/PipeWire prepend to every
    port name on a device, then tidy up what's left."""
    prefix = ""
    if len(names) > 1:
        prefix = os.path.commonprefix(names)
        cut = prefix.rfind(" ")
        prefix = prefix[: cut + 1] if cut != -1 else ""
        if not (prefix and all(len(n) > len(prefix) for n in names)):
            prefix = ""
    return [cleanup_name(n[len(prefix):]) for n in names]


def cleanup_name(name):
    name = re.sub(r"HDMI\s*/\s*DisplayPort", "DisplayPort", name).strip()
    if name in ("Speaker", "Speakers"):
        name = "Built-In " + name
    return name


def set_default(sink_id):
    subprocess.run(["wpctl", "set-default", sink_id], check=True)


# --- Sources (microphones) -----------------------------------------------
#
# No pactl-name join needed here, unlike get_sinks()/_pactl_sink_info()
# above: there's no Multi-Output-equivalent combine-source feature, so
# nothing needs a pactl-facing slaves= name -- wpctl's own id is all
# set_default_source()/get_source_volume()/set_source_volume() need.

def _default_source_id():
    try:
        out = subprocess.run(
            ["wpctl", "inspect", "@DEFAULT_AUDIO_SOURCE@"], capture_output=True, text=True, check=True
        ).stdout
    except Exception:
        return None
    m = re.match(r"id (\d+)", out)
    return m.group(1) if m else None


def _pactl_source_descriptions():
    """Map each source's pactl-facing Name to its human-readable
    Description, keyed the same way _pactl_sink_info() keys sinks --
    except here the join key going the other direction (wpctl's
    Filters-section display text *is* the Name, not the Description),
    so this is looked up by Name instead."""
    try:
        out = subprocess.run(["pactl", "list", "sources"], capture_output=True, text=True, check=True).stdout
    except Exception:
        return {}
    descriptions = {}
    for block in re.split(r"(?m)^Source #\d+\n", out)[1:]:
        name_m = re.search(r"^\tName: (.+)$", block, re.M)
        desc_m = re.search(r"^\tDescription: (.+)$", block, re.M)
        if name_m and desc_m:
            descriptions[name_m.group(1).strip()] = desc_m.group(1).strip()
    return descriptions


_SOURCE_HEADERS = {
    "Devices:": None,
    "Sinks:": None,
    "Sources:": "sources",
    "Filters:": "filters",
    "Streams:": None,
}


def get_sources():
    """List real microphones (wpctl status's Sources: section) plus any
    Audio/Source filter-chain node -- e.g. PipeWire's echo-cancel
    module's virtual mic (see ~/.config/pipewire/pipewire.conf.d/99-echo-cancel.conf)
    -- that wpctl status buckets under Filters instead, since those are
    exactly as selectable/controllable via wpctl as a real Sources:
    entry despite not being listed there."""
    out = subprocess.run(["wpctl", "status"], capture_output=True, text=True, check=True).stdout
    lines = out.splitlines()
    start = next((i for i, l in enumerate(lines) if l.strip() == "Audio"), None)
    if start is None:
        return []
    end = next((i for i in range(start + 1, len(lines)) if lines[i].strip() == "Video"), len(lines))
    audio_lines = lines[start:end]

    default_id = _default_source_id()
    descriptions = _pactl_source_descriptions()

    sources = []
    section = None
    for line in audio_lines:
        stripped = line.strip()
        header = next((h for h in _SOURCE_HEADERS if stripped.endswith(h)), None)
        if header is not None:
            section = _SOURCE_HEADERS[header]
            continue

        if section == "sources":
            m = re.match(r"^[│\s]*(?:\*)?\s*(\d+)\.\s+(.*?)\s*\[vol:", stripped)
            if not m:
                continue
            sid, raw_name = m.group(1), m.group(2).strip()
            sources.append({"id": sid, "raw_name": raw_name, "name": raw_name, "default": sid == default_id})
        elif section == "filters":
            # Same optional "*" (currently-default) prefix as the
            # Sources: rows above -- easy to miss since this filter
            # entry only ever carries it once it's actually selected as
            # the default source, i.e. exactly the state this function
            # must not drop it in.
            m = re.match(r"^[│\s]*(?:\*)?\s*(\d+)\.\s+(.*?)\s+\[Audio/Source\]\s*$", stripped)
            if not m:
                continue
            sid, raw_name = m.group(1), m.group(2).strip()
            display = descriptions.get(raw_name, raw_name)
            sources.append({"id": sid, "raw_name": display, "name": display, "default": sid == default_id})

    names = simplify_names([s["raw_name"] for s in sources])
    for s, name in zip(sources, names):
        s["name"] = name
    return sources


def set_default_source(source_id):
    subprocess.run(["wpctl", "set-default", source_id], check=True)


def get_source_volume(source_id):
    out = subprocess.run(["wpctl", "get-volume", source_id], capture_output=True, text=True, check=True).stdout
    m = re.search(r"([\d.]+)", out)
    return round(float(m.group(1)) * 100) if m else 0


def set_source_volume(source_id, pct):
    pct = max(0, min(150, round(pct)))
    subprocess.run(["wpctl", "set-volume", source_id, f"{pct}%"], check=True)


def get_volume(sink_id):
    out = subprocess.run(["wpctl", "get-volume", sink_id], capture_output=True, text=True, check=True).stdout
    m = re.search(r"([\d.]+)", out)
    return round(float(m.group(1)) * 100) if m else 0


def set_volume(sink_id, pct):
    pct = max(0, min(150, round(pct)))
    subprocess.run(["wpctl", "set-volume", sink_id, f"{pct}%"], check=True)


# --- Multi-Output (combine sink) ----------------------------------------

def find_combine_module():
    """Our combine module's id and the pactl sink names currently
    feeding it, or None if it's not loaded. Looked up fresh from pactl
    every time rather than cached -- same reasoning as COMBINE_SINK_NAME
    above, nothing here needs to survive as in-memory state."""
    try:
        out = subprocess.run(["pactl", "list", "modules"], capture_output=True, text=True, check=True).stdout
    except Exception:
        return None

    for block in re.split(r"(?m)^Module #", out)[1:]:
        id_m = re.match(r"(\d+)", block)
        if not id_m or "Name: module-combine-sink" not in block:
            continue
        if f"sink_name={COMBINE_SINK_NAME}" not in block:
            continue
        slaves_m = re.search(r"slaves=(\S+)", block)
        slaves = slaves_m.group(1).split(",") if slaves_m else []
        return {"module_id": id_m.group(1), "slaves": slaves}
    return None


def create_combine(pactl_sink_names):
    subprocess.run(
        [
            "pactl", "load-module", "module-combine-sink",
            f"sink_name={COMBINE_SINK_NAME}",
            "sink_properties=device.description=Multi-Output",
            f"slaves={','.join(pactl_sink_names)}",
        ],
        check=True, capture_output=True,
    )
    subprocess.run(["pactl", "set-default-sink", COMBINE_SINK_NAME], check=False, capture_output=True)


def remove_combine(module_id):
    subprocess.run(["pactl", "unload-module", module_id], check=False, capture_output=True)
