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


def gen_nvim_colorscheme(p: dict, name: str) -> str:
    cs_name = "custom_autogen_nvim_colorscheme"

    def hl(group, fg=None, bg=None, sp=None, bold=False, italic=False,
           underline=False, undercurl=False, strikethrough=False, link=None):
        g = f'"{group}"'
        if link:
            return f'hl(0, {g:<37s}, {{ link = "{link}" }})'
        attrs = []
        if fg:            attrs.append(f'fg = c.{fg}')
        if bg:            attrs.append(f'bg = c.{bg}')
        if sp:            attrs.append(f'sp = c.{sp}')
        if bold:          attrs.append('bold = true')
        if italic:        attrs.append('italic = true')
        if underline:     attrs.append('underline = true')
        if undercurl:     attrs.append('undercurl = true')
        if strikethrough: attrs.append('strikethrough = true')
        return f'hl(0, {g:<37s}, {{ {", ".join(attrs)} }})'

    ln = [
        f'-- GENERATED from palettes/{name}.toml — run generate_colors.py to update',
        'vim.cmd("highlight clear")',
        'if vim.fn.exists("syntax_on") == 1 then vim.cmd("syntax reset") end',
        f'vim.g.colors_name = "{cs_name}"',
        '',
        'local hl = vim.api.nvim_set_hl',
        'local c = {',
        f'  bg           = "{p["bg"]}",',
        f'  bg_dim       = "{p["bg_dim"]}",',
        f'  bg_inactive  = "{p["bg_inactive"]}",',
        f'  bg_normal    = "{p["bg_normal"]}",',
        f'  bg_cursorline = "{p["bg_cursorline"]}",',
        f'  fg_cursorline = "{p["fg_cursorline"]}",',
        f'  bg_highlight  = "{p["bg_highlight"]}",',
        f'  fg_highlight  = "{p["fg_highlight"]}",',
        f'  fg           = "{p["fg"]}",',
        f'  grey         = "{p["grey"]}",',
        f'  white        = "{p["white"]}",',
        f'  pink         = "{p["pink"]}",',
        f'  blue         = "{p["blue"]}",',
        f'  green        = "{p["green"]}",',
        f'  yellow       = "{p["yellow"]}",',
        f'  purple       = "{p["purple"]}",',
        f'  orange       = "{p["orange"]}",',
        f'  black_bright  = "{p["black_bright"]}",',
        f'  pink_bright   = "{p["pink_bright"]}",',
        f'  green_bright  = "{p["green_bright"]}",',
        f'  yellow_bright = "{p["yellow_bright"]}",',
        f'  blue_bright   = "{p["blue_bright"]}",',
        f'  purple_bright = "{p["purple_bright"]}",',
        f'  orange_bright = "{p["orange_bright"]}",',
        f'  white_bright  = "{p["white_bright"]}",',
        f'  warn          = "{p["battery_warning"]}",',
        '}',
        '',
        '-- ── UI ─────────────────────────────────────────────────────────────────────',
        hl('Normal',          fg='fg',          bg='bg_normal'),
        hl('NormalFloat',     fg='fg',          bg='bg'),
        hl('NormalNC',        fg='grey',        bg='bg_normal'),
        hl('EndOfBuffer',     fg='black_bright'),
        hl('NonText',         fg='black_bright'),
        hl('SignColumn',      fg='grey',        bg='bg_normal'),
        hl('LineNr',          fg='black_bright'),
        hl('CursorLineNr',    fg='pink',        bold=True),
        hl('CursorLine',      fg='fg_cursorline', bg='bg_cursorline'),
        hl('CursorColumn',    fg='fg_cursorline', bg='bg_cursorline'),
        hl('ColorColumn',     bg='bg_dim'),
        hl('VertSplit',       fg='black_bright'),
        hl('WinSeparator',    fg='black_bright'),
        hl('Folded',          fg='grey',        bg='bg_inactive'),
        hl('FoldColumn',      fg='grey'),
        hl('Conceal',         fg='grey'),
        hl('SpecialKey',      fg='black_bright'),
        '',
        '-- ── Status / Tab ──────────────────────────────────────────────────────────',
        hl('StatusLine',      fg='fg',          bg='bg_cursorline'),
        hl('StatusLineNC',    fg='grey',        bg='bg_cursorline'),
        hl('TabLine',         fg='grey',        bg='bg_inactive'),
        hl('TabLineFill',     bg='bg'),
        hl('TabLineSel',      fg='bg',          bg='pink',        bold=True),
        '',
        '-- ── Selection / Search ─────────────────────────────────────────────────────',
        hl('Visual',          fg='fg_highlight', bg='bg_highlight'),
        hl('VisualNOS',       fg='fg_highlight', bg='bg_highlight'),
        hl('Search',          fg='bg',          bg='yellow'),
        hl('IncSearch',       fg='bg',          bg='pink'),
        hl('CurSearch',       fg='bg',          bg='blue'),
        hl('MatchParen',      fg='pink',        bold=True, underline=True),
        hl('QuickFixLine',    fg='bg',          bg='blue'),
        '',
        '-- ── Popup Menu ─────────────────────────────────────────────────────────────',
        hl('Pmenu',           fg='fg',          bg='bg_inactive'),
        hl('PmenuSel',        fg='bg',          bg='blue'),
        hl('PmenuSbar',       bg='bg_dim'),
        hl('PmenuThumb',      bg='grey'),
        hl('PmenuKind',       fg='purple',      bg='bg_inactive'),
        hl('PmenuKindSel',    fg='purple',      bg='blue'),
        hl('PmenuExtra',      fg='grey',        bg='bg_inactive'),
        hl('PmenuExtraSel',   fg='grey',        bg='blue'),
        '',
        '-- ── Messages / Misc ───────────────────────────────────────────────────────',
        hl('ErrorMsg',        fg='pink',        bold=True),
        hl('WarningMsg',      fg='warn'),
        hl('ModeMsg',         fg='fg',          bold=True),
        hl('MoreMsg',         fg='green'),
        hl('Question',        fg='blue'),
        hl('Title',           fg='pink',        bold=True),
        hl('Directory',       fg='blue'),
        hl('WildMenu',        fg='bg',          bg='blue'),
        hl('FloatBorder',     fg='black_bright'),
        hl('FloatTitle',      fg='pink',        bold=True),
        '',
        '-- ── Syntax ─────────────────────────────────────────────────────────────────',
        hl('Comment',         fg='grey',        italic=True),
        hl('Constant',        fg='orange'),
        hl('String',          fg='green'),
        hl('Character',       fg='green_bright'),
        hl('Number',          fg='orange'),
        hl('Float',           fg='orange'),
        hl('Boolean',         fg='orange',      bold=True),
        hl('Identifier',      fg='fg'),
        hl('Function',        fg='blue'),
        hl('Statement',       fg='pink'),
        hl('Keyword',         fg='pink',        bold=True),
        hl('Conditional',     fg='pink'),
        hl('Repeat',          fg='pink'),
        hl('Label',           fg='pink'),
        hl('Operator',        fg='blue_bright'),
        hl('Exception',       fg='pink_bright'),
        hl('PreProc',         fg='purple'),
        hl('Include',         fg='purple'),
        hl('Define',          fg='purple'),
        hl('Macro',           fg='purple'),
        hl('PreCondit',       fg='purple'),
        hl('Type',            fg='purple'),
        hl('StorageClass',    fg='purple'),
        hl('Structure',       fg='purple'),
        hl('Typedef',         fg='purple'),
        hl('Special',         fg='yellow'),
        hl('SpecialChar',     fg='yellow'),
        hl('Tag',             fg='blue'),
        hl('Delimiter',       fg='white'),
        hl('SpecialComment',  fg='grey',        italic=True),
        hl('Underlined',      underline=True),
        hl('Error',           fg='pink_bright', bold=True),
        hl('Todo',            fg='bg',          bg='yellow',      bold=True),
        hl('Debug',           fg='pink_bright'),
        '',
        '-- ── Treesitter ─────────────────────────────────────────────────────────────',
        hl('@comment',                   link='Comment'),
        hl('@string',                    link='String'),
        hl('@string.escape',             fg='yellow'),
        hl('@string.special',            fg='yellow'),
        hl('@string.special.url',        fg='blue',       underline=True),
        hl('@number',                    link='Number'),
        hl('@float',                     link='Float'),
        hl('@boolean',                   link='Boolean'),
        hl('@character',                 link='Character'),
        hl('@keyword',                   link='Keyword'),
        hl('@keyword.function',          fg='pink'),
        hl('@keyword.return',            fg='pink',       bold=True),
        hl('@keyword.operator',          fg='pink'),
        hl('@keyword.import',            fg='purple'),
        hl('@conditional',               link='Conditional'),
        hl('@repeat',                    link='Repeat'),
        hl('@exception',                 link='Exception'),
        hl('@operator',                  link='Operator'),
        hl('@function',                  link='Function'),
        hl('@function.call',             fg='blue'),
        hl('@function.builtin',          fg='blue_bright'),
        hl('@function.macro',            fg='purple'),
        hl('@method',                    fg='blue'),
        hl('@method.call',               fg='blue'),
        hl('@constructor',               fg='blue'),
        hl('@parameter',                 fg='white'),
        hl('@variable',                  fg='fg'),
        hl('@variable.builtin',          fg='orange_bright'),
        hl('@constant',                  link='Constant'),
        hl('@constant.builtin',          fg='orange_bright', bold=True),
        hl('@constant.macro',            fg='purple'),
        hl('@type',                      link='Type'),
        hl('@type.builtin',              fg='purple',     bold=True),
        hl('@type.qualifier',            fg='purple'),
        hl('@field',                     fg='blue_bright'),
        hl('@property',                  fg='blue_bright'),
        hl('@attribute',                 fg='yellow'),
        hl('@namespace',                 fg='purple'),
        hl('@punctuation.delimiter',     fg='white'),
        hl('@punctuation.bracket',       fg='white'),
        hl('@punctuation.special',       fg='yellow'),
        hl('@tag',                       fg='pink'),
        hl('@tag.attribute',             fg='blue'),
        hl('@tag.delimiter',             fg='white'),
        hl('@text',                      fg='fg'),
        hl('@text.strong',               bold=True),
        hl('@text.emphasis',             italic=True),
        hl('@text.underline',            underline=True),
        hl('@text.strike',               strikethrough=True),
        hl('@text.title',                fg='pink',       bold=True),
        hl('@text.literal',              fg='green'),
        hl('@text.uri',                  fg='blue',       underline=True),
        hl('@text.reference',            fg='blue'),
        hl('@text.todo',                 fg='bg',         bg='yellow',   bold=True),
        hl('@text.warning',              fg='warn'),
        hl('@text.danger',               fg='pink'),
        '-- nvim 0.10+ markup groups',
        hl('@markup.heading',            fg='pink',       bold=True),
        hl('@markup.raw',                fg='green'),
        hl('@markup.link',               fg='blue',       underline=True),
        hl('@markup.link.url',           fg='blue',       underline=True),
        hl('@markup.strong',             bold=True),
        hl('@markup.italic',             italic=True),
        hl('@markup.strikethrough',      strikethrough=True),
        '',
        '-- ── LSP / Diagnostics ──────────────────────────────────────────────────────',
        hl('DiagnosticError',            fg='pink'),
        hl('DiagnosticWarn',             fg='warn'),
        hl('DiagnosticInfo',             fg='blue'),
        hl('DiagnosticHint',             fg='green'),
        hl('DiagnosticOk',               fg='green'),
        hl('DiagnosticUnderlineError',   sp='pink',       undercurl=True),
        hl('DiagnosticUnderlineWarn',    sp='warn',       undercurl=True),
        hl('DiagnosticUnderlineInfo',    sp='blue',       undercurl=True),
        hl('DiagnosticUnderlineHint',    sp='green',      undercurl=True),
        hl('DiagnosticVirtualTextError', fg='pink',       italic=True),
        hl('DiagnosticVirtualTextWarn',  fg='warn',       italic=True),
        hl('DiagnosticVirtualTextInfo',  fg='blue',       italic=True),
        hl('DiagnosticVirtualTextHint',  fg='green',      italic=True),
        hl('DiagnosticSignError',        fg='pink'),
        hl('DiagnosticSignWarn',         fg='warn'),
        hl('DiagnosticSignInfo',         fg='blue'),
        hl('DiagnosticSignHint',         fg='green'),
        hl('LspReferenceText',           bg='bg_inactive'),
        hl('LspReferenceRead',           bg='bg_inactive'),
        hl('LspReferenceWrite',          bg='bg_inactive', underline=True),
        hl('LspInlayHint',               fg='grey',       italic=True),
        '',
        '-- ── Git / Diff ─────────────────────────────────────────────────────────────',
        hl('DiffAdd',         fg='green',   bg='bg_dim'),
        hl('DiffChange',      fg='yellow',  bg='bg_dim'),
        hl('DiffDelete',      fg='pink',    bg='bg_dim'),
        hl('DiffText',        fg='bg',      bg='yellow'),
        hl('Added',           fg='green'),
        hl('Changed',         fg='yellow'),
        hl('Removed',         fg='pink'),
        '',
        '-- ── Terminal palette ───────────────────────────────────────────────────────',
        'vim.g.terminal_color_0  = c.bg',
        'vim.g.terminal_color_1  = c.pink',
        'vim.g.terminal_color_2  = c.green',
        'vim.g.terminal_color_3  = c.yellow',
        'vim.g.terminal_color_4  = c.blue',
        'vim.g.terminal_color_5  = c.purple',
        'vim.g.terminal_color_6  = c.orange',
        'vim.g.terminal_color_7  = c.white',
        'vim.g.terminal_color_8  = c.black_bright',
        'vim.g.terminal_color_9  = c.pink_bright',
        'vim.g.terminal_color_10 = c.green_bright',
        'vim.g.terminal_color_11 = c.yellow_bright',
        'vim.g.terminal_color_12 = c.blue_bright',
        'vim.g.terminal_color_13 = c.purple_bright',
        'vim.g.terminal_color_14 = c.orange_bright',
        'vim.g.terminal_color_15 = c.white_bright',
    ]
    return '\n'.join(ln)


# ── Main ──────────────────────────────────────────────────────────────────────

OUTPUTS = {
    "kitty/theme.conf":   gen_kitty_theme,
    "wezterm/colors.lua": gen_wezterm_colors,
    "tmux-colors.conf":   gen_tmux_colors,
    "hypr/colors.conf":   gen_hypr_colors,
    "waybar/colors.css":  gen_waybar_css,
    "rofi-colors.rasi":   gen_rofi_colors,
}

NVIM_OUTPUTS = {
    "~/.config/nvim/colors/custom_autogen_nvim_colorscheme.lua": gen_nvim_colorscheme,
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
    for display, generator in NVIM_OUTPUTS.items():
        path = Path(display).expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(generator(p, palette_name))
        print(f"  wrote {display}")
    print("Done.")


if __name__ == "__main__":
    main()
