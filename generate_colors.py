#!/usr/bin/env python3
"""
Generate per-tool color files from a palette.

Usage:
  python3 generate_colors.py              # interactive palette picker
  python3 generate_colors.py dark         # use palettes/dark.toml
  python3 generate_colors.py light        # use palettes/light.toml
  python3 generate_colors.py /path/to/x.toml  # use any file
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).parent
PALETTES_DIR = ROOT / "palettes"


# ── Palette loading ────────────────────────────────────────────────────────────

def load_palette(path: Path) -> dict:
    """Parse the [palette] section of a .toml file without external deps."""
    p = {}
    in_section = False
    for line in path.read_text().splitlines():
        line = line.strip()
        if line == "[palette]":
            in_section = True
            continue
        if line.startswith("[") and in_section:
            break
        if in_section and line and not line.startswith("#"):
            m = re.match(r'^(\w+)\s*=\s*"([^"]+)"', line)
            if m:
                p[m.group(1)] = m.group(2)
    return p


def available_palettes():
    return sorted(p.stem for p in PALETTES_DIR.glob("*.toml"))


def resolve_palette(arg) -> Path:
    """Turn a name, path, or None (interactive) into a palette file path."""
    if arg is not None:
        # Explicit file path
        as_path = Path(arg)
        if as_path.suffix == ".toml" or as_path.is_file():
            if as_path.is_file():
                return as_path
            sys.exit(f"error: file not found: {arg}")
        # Named palette
        named = PALETTES_DIR / f"{arg}.toml"
        if named.is_file():
            return named
        names = available_palettes()
        sys.exit(f"error: palette {arg!r} not found. Available: {', '.join(names)}")

    # Interactive picker
    names = available_palettes()
    if not names:
        sys.exit(f"error: no palettes found in {PALETTES_DIR}")
    print("Available palettes:")
    for i, name in enumerate(names, 1):
        print(f"  {i}. {name}")
    try:
        raw = input(f"Select [1]: ").strip()
    except (EOFError, KeyboardInterrupt):
        sys.exit(0)
    choice = raw if raw else "1"
    if choice.isdigit() and 1 <= int(choice) <= len(names):
        return PALETTES_DIR / f"{names[int(choice) - 1]}.toml"
    # Treat as a name
    named = PALETTES_DIR / f"{choice}.toml"
    if named.is_file():
        return named
    sys.exit(f"error: invalid selection: {choice!r}")


# ── Generators ────────────────────────────────────────────────────────────────

def _header(palette_name: str, comment: str = "#") -> str:
    return f"{comment} GENERATED from palettes/{palette_name}.toml — run generate_colors.py to update"

def _header_css(palette_name: str) -> str:
    return f"/* GENERATED from palettes/{palette_name}.toml — run generate_colors.py to update */"


def gen_kitty_theme(p: dict, name: str) -> str:
    return f"""\
{_header(name)}

# Basic
foreground              {p['fg']}
background              {p['bg']}
selection_foreground    {p['bg']}
selection_background    {p['blue']}

# Cursor
cursor                  {p['pink']}
cursor_text_color       {p['bg']}

# URL
url_color               {p['green']}

# Window borders
active_border_color     {p['pink']}
inactive_border_color   {p['bg_inactive']}
bell_border_color       {p['blue']}

# Tab bar
active_tab_foreground   {p['bg']}
active_tab_background   {p['pink']}
inactive_tab_foreground {p['grey']}
inactive_tab_background {p['bg_inactive']}
tab_bar_background      {p['bg']}

# Terminal palette (ANSI 0–15)
# black
color0  {p['bg']}
color8  {p['black_bright']}
# red / pink
color1  {p['pink']}
color9  {p['pink_bright']}
# green
color2  {p['green']}
color10 {p['green_bright']}
# yellow
color3  {p['yellow']}
color11 {p['yellow_bright']}
# blue
color4  {p['blue']}
color12 {p['blue_bright']}
# magenta / purple
color5  {p['purple']}
color13 {p['purple_bright']}
# cyan slot (actually orange)
color6  {p['orange']}
color14 {p['orange_bright']}
# white
color7  {p['white']}
color15 {p['white_bright']}
"""


def gen_wezterm_colors(p: dict, name: str) -> str:
    return f"""\
-- GENERATED from palettes/{name}.toml — run generate_colors.py to update
return {{
  bg          = '{p['bg']}',
  bg_dim      = '{p['bg_dim']}',
  bg_inactive = '{p['bg_inactive']}',
  bg_normal   = '{p['bg_normal']}',

  fg    = '{p['fg']}',
  grey  = '{p['grey']}',
  white = '{p['white']}',

  pink   = '{p['pink']}',
  blue   = '{p['blue']}',
  green  = '{p['green']}',
  yellow = '{p['yellow']}',
  purple = '{p['purple']}',
  orange = '{p['orange']}',

  black_bright  = '{p['black_bright']}',
  pink_bright   = '{p['pink_bright']}',
  green_bright  = '{p['green_bright']}',
  yellow_bright = '{p['yellow_bright']}',
  blue_bright   = '{p['blue_bright']}',
  purple_bright = '{p['purple_bright']}',
  orange_bright = '{p['orange_bright']}',
  white_bright  = '{p['white_bright']}',

  battery_warning = '{p['battery_warning']}',
}}
"""


def gen_tmux_colors(p: dict, name: str) -> str:
    return f"""\
{_header(name)}
set -g @background     "{p['bg_normal']}"
set -g @dim_background "{p['bg_dim']}"
set -g @white          "{p['white']}"
set -g @grey           "{p['grey']}"
set -g @pink           "{p['pink']}"
"""


def gen_hypr_colors(p: dict, name: str) -> str:
    def rgba(hex_color: str, alpha: str) -> str:
        return f"rgba({hex_color.lstrip('#')}{alpha})"
    return f"""\
{_header(name)}
$active_border_start = {rgba(p['blue'], 'cc')}
$active_border_end   = {rgba(p['green'], '88')}
$inactive_border     = {rgba(p['border_inactive'], 'aa')}
$shadow_color        = {rgba(p['shadow'], 'ee')}
"""


def gen_waybar_css(p: dict, name: str) -> str:
    return f"""\
{_header_css(name)}
:root {{
  --fg:           {p['fg']};
  --fg-muted:     {p['grey']};
  --fg-dim:       {p['black_bright']};
  --pink:         {p['pink']};
  --blue:         {p['blue']};
  --green:        {p['green']};
  --battery-warn: {p['battery_warning']};
}}
"""


def gen_rofi_colors(p: dict, name: str) -> str:
    bg, bg_alt = p['rofi_bg'], p['rofi_bg_alt']
    fg_dim, fg_sec = p['rofi_fg_dim'], p['rofi_fg_sec']
    return f"""\
{_header_css(name)}
* {{
    bg:            {bg}ee;
    bg-solid:      {bg}ff;
    bg-alt:        {bg_alt}cc;
    bg-selected:   {p['green']}55;
    fg:            #ffffffff;
    fg-dim:        {fg_dim}ff;
    fg-secondary:  {fg_sec}99;
    border-accent: {p['blue']}88;
    separator-bg:  #ffffff18;
}}
"""


# ── Main ──────────────────────────────────────────────────────────────────────

OUTPUTS = {
    "kitty/theme.conf":   gen_kitty_theme,
    "wezterm/colors.lua": gen_wezterm_colors,
    "tmux-colors.conf":   gen_tmux_colors,
    "hypr/colors.conf":   gen_hypr_colors,
    "waybar/colors.css":  gen_waybar_css,
    "rofi-colors.rasi":   gen_rofi_colors,
}


def main():
    arg = sys.argv[1] if len(sys.argv) > 1 else None
    palette_path = resolve_palette(arg)
    palette_name = palette_path.stem

    p = load_palette(palette_path)
    print(f"Generating color files from palettes/{palette_name}.toml...")
    for rel, generator in OUTPUTS.items():
        path = ROOT / rel
        path.write_text(generator(p, palette_name))
        print(f"  wrote {rel}")
    print("Done.")


if __name__ == "__main__":
    main()
