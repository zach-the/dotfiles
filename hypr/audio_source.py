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
