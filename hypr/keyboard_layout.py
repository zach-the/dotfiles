#!/usr/bin/env python3
"""Waybar custom/language module: icon-only rounded-square letter badge
(see waybar/generate_language_icons.py). The class is derived directly from
Hyprland's active keymap name -- lowercase its first word ("English (US)"
-> "english", "Georgian" -> "georgian") -- so this script needs no changes
when a new language is added; only the generator's LANGUAGES dict does (see
its docstring).
"""
import json
import subprocess

KEYBOARD_NAME = "at-translated-set-2-keyboard"


def active_keymap():
    devices = json.loads(subprocess.check_output(["hyprctl", "devices", "-j"]))
    for kb in devices["keyboards"]:
        if kb["name"] == KEYBOARD_NAME:
            return kb["active_keymap"]
    return None


def main():
    keymap = active_keymap()
    if not keymap:
        print(json.dumps({"text": ""}))
        return

    code = keymap.split()[0].lower()
    print(json.dumps({
        "text": " ",  # icon-only; waybar hides the module if text is truly empty
        "tooltip": keymap,
        "class": code,
    }))


if __name__ == "__main__":
    main()
