#!/usr/bin/env python3
"""Render a macOS-style battery gauge for the waybar custom/battery module.

Unlike icon themes (Adwaita, WhiteSur, ...) that swap between ~11 discrete
pre-drawn shapes, real macOS draws one outline with an inner bar that
continuously widens with charge % -- this draws that same shape in pure SVG
(original artwork, no external assets) at every integer percent so the fill
looks continuous as the battery drains.

No stroked outline -- just the uncharged remainder of the interior and the
charged fill, both white at two opacities: the uncharged remainder is the
same translucent-white "dimmed" track the wifi/volume gauges use (see
DIM_OPACITY in generate_wifi_icons.py / generate_volume_icons.py), and the
charged fill sits on top of it at full white -- the track's own rounded
shape is what reads as the pill's edge. The percentage digit and the
charging bolt are drawn as a low-opacity black overlay on top of that (see
CUTOUT_OPACITY) -- not a full transparent cutout -- so they read as a
faint dark tint over whatever's beneath (track or fill) rather than a hole
straight through to the bar's background.

The nub is part of that same continuous fill, not a separate always-on
shape: it shows the same dimmed track as the body until the fill extends
past the main body and into it, at which point it fills solid white just
like the body does -- so it only lights up fully in the last stretch
before 100%.

The bolt sits left of the digit (not centered) so a full-size bolt and
"100" (the widest digit, at the same font size as every other value) both
fit -- the pill's width is sized to that, with the digit's x-position a
fixed offset from the bolt rather than the pill's horizontal center, so
there's no dead space mirrored on the right. Those numbers were picked
empirically: see the PIL measurement of the actual SF Pro glyphs in the git
history of this file if the font or sizes change and it needs re-deriving,
rather than guessing at character-width ratios.

Output: waybar/icons/battery/level-{0..100}-{discharging,charging}.svg,
plus waybar/battery-icons-generated.css, which style.css @imports, mapping
each "level-N-<state>" class (set by battery_color.py) to its
background-image.

Run manually to regenerate: ./generate_battery_icons.py
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ICONS_DIR = ROOT / "icons" / "battery"
CSS_OUT = ROOT / "battery-icons-generated.css"

WHITE = "#ffffff"
DIM_OPACITY = "0.3"  # matches generate_wifi_icons.py / generate_volume_icons.py
CUTOUT_OPACITY = "0.66"  # digit/bolt: faint dark tint, not a full transparent hole

# Geometry, in a viewBox -- outline body + right-hand nub, matching the
# proportions of the real macOS menu-bar battery glyph. No stroked outline
# rect -- the track/fill's own rounded shape (below) is the pill's visible
# edge. OUTLINE_H/OUTLINE_W are still used purely as layout dimensions (the
# nub and viewBox sizing key off them) even with nothing actually drawn at
# those coordinates.
OUTLINE_H = 9.5
NUB_W, NUB_H, NUB_R = 1.9, 3.6, 1.2
NUB_Y = 0.75 + (OUTLINE_H - NUB_H) / 2
INNER_X, INNER_Y = 1.25, 1.25
# A radius of 1 barely registered at the icon's actual on-screen size (a
# few physical pixels), reading as sharp corners -- this is picked to
# still look clearly rounded once rasterized that small.
BODY_R = 2.4
INNER_H = OUTLINE_H - 2 * 0.5
FONT_FAMILY = "SF Pro, DejaVu Sans, sans-serif"
FONT_SIZE = 7.2
TEXT_Y = 8.0

# A lightning-bolt silhouette (Lucide's "zap" icon shape), sized generously
# -- comfortably bigger than the pill's own height needs, so it reads
# clearly rather than looking like an afterthought next to the digit.
BOLT_W, BOLT_H = 5.0, 7.0
_sx, _sy = BOLT_W / 18, BOLT_H / 20
BOLT_LOCAL = [(x * _sx, y * _sy) for x, y in [(10, 0), (0, 12), (9, 12), (8, 20), (18, 8), (9, 8)]]
BOLT_X = INNER_X + 1.8
BOLT_Y = INNER_Y + (INNER_H - BOLT_H) / 2

# The digit sits a fixed distance right of the bolt (not centered on the
# pill), and the pill is only as wide as it needs to be to clear "100" (the
# widest value, half-width 7.08 at FONT_SIZE=7.2 in SF Pro Heavy) on the
# right with a small margin -- rather than mirroring the bolt's space on
# both sides, which leaves a wide empty gap after "100".
_DIGIT_GAP, _DIGIT_HALF_W_MAX, _RIGHT_MARGIN = 0.6, 7.08, 0.6
TEXT_X = BOLT_X + BOLT_W + _DIGIT_GAP + _DIGIT_HALF_W_MAX
INNER_W = (TEXT_X - INNER_X) + _DIGIT_HALF_W_MAX + _RIGHT_MARGIN
OUTLINE_W = INNER_W + 2 * 0.5
NUB_GAP = 0.25  # transparent gap between the main body and the nub, always empty
NUB_X = 0.75 + OUTLINE_W + NUB_GAP
VIEW_W = NUB_X + NUB_W + 0.6
VIEW_H = 0.75 * 2 + OUTLINE_H

# Total span the continuous fill divides up: the main body, then the gap
# (never fills -- it's the physical notch between the cell and the nub),
# then the nub itself.
TOTAL_FILLABLE_W = INNER_W + NUB_GAP + NUB_W


def bolt_polygon():
    pts = " ".join(f"{BOLT_X + x:.3f},{BOLT_Y + y:.3f}" for x, y in BOLT_LOCAL)
    return f'<polygon points="{pts}" fill="black" fill-opacity="{CUTOUT_OPACITY}"/>'


def fill_shape(x, y, h, width, radius, attrs):
    # Rounded on the left (against the shape's own resting rounded corner)
    # but square on the right -- the right edge is the fill's moving
    # boundary, not an actual corner, so rounding it looked like a stray
    # notch partway across the icon instead of matching the outline.
    d = (
        f'M{x + width:.3f} {y} L{x + radius} {y} A{radius} {radius} 0 0 0 {x} {y + radius} '
        f'L{x} {y + h - radius} A{radius} {radius} 0 0 0 {x + radius} {y + h} '
        f'L{x + width:.3f} {y + h} Z'
    )
    return f'<path d="{d}" {attrs}/>'


def nub_shape(fill_w):
    # Same dimmed track as the main body, always drawn, with the bright
    # fill layered on top of it once the fill reaches this far.
    track = f'<rect x="{NUB_X:.3f}" y="{NUB_Y:.3f}" width="{NUB_W}" height="{NUB_H}" rx="{NUB_R}" fill="{WHITE}" fill-opacity="{DIM_OPACITY}"/>'
    if fill_w <= 0:
        return track
    if fill_w >= NUB_W - 1e-6:
        # Fully filled: a plain rounded rect matching the nub's own resting
        # shape, rather than fill_shape's square-right edge (which would be
        # a visible seam right where the nub's true rounded tip is).
        fill = f'<rect x="{NUB_X:.3f}" y="{NUB_Y:.3f}" width="{NUB_W}" height="{NUB_H}" rx="{NUB_R}" fill="{WHITE}"/>'
    else:
        fill = fill_shape(NUB_X, NUB_Y, NUB_H, fill_w, NUB_R, f'fill="{WHITE}"')
    return track + fill


def battery_svg(pct, charging):
    pct = max(0, min(100, pct))
    # A literal 0-100% linear width made the fill vanish to nothing at the
    # low end, thinner than the body's own rounded corner could show
    # cleanly. So 0% starts at a 5%-wide sliver, and the remaining 95% of
    # the width is what 0-100% actually divides up -- every percent still
    # gets its own distinct width (unlike a flat floor/clamp), just all
    # shifted up by that 5% baseline. This is computed over the *combined*
    # body+gap+nub span (see nub_shape) -- the nub only starts filling once
    # the body itself is full, since the gap between them never fills.
    fill_extent = TOTAL_FILLABLE_W * (5 + 0.95 * pct) / 100
    body_fill_w = min(fill_extent, INNER_W)
    nub_fill_w = max(0.0, min(NUB_W, fill_extent - INNER_W - NUB_GAP))

    num = str(pct)
    text_attrs = f'text-anchor="middle" font-size="{FONT_SIZE}" font-weight="800" font-family="{FONT_FAMILY}"'
    # Charging: digit stays at its fixed offset right of the bolt. Not
    # charging: there's no bolt to share the pill with, so center the digit
    # in the pill instead of leaving it sitting off to one side.
    text_x = TEXT_X if charging else (INNER_X + INNER_W / 2)
    digit_overlay = f'<text x="{text_x:.2f}" y="{TEXT_Y}" {text_attrs} fill="black" fill-opacity="{CUTOUT_OPACITY}">{num}</text>'
    bolt_overlay = bolt_polygon() if charging else ""

    # Track (dimmed, full width) + fill (bright, current charge width) on
    # top of it -- same "grey track under a bright fill" idea as the
    # volume/wifi gauges, just white-at-two-opacities instead of white/grey.
    track = f'<rect x="{INNER_X}" y="{INNER_Y}" width="{INNER_W:.3f}" height="{INNER_H:.3f}" rx="{BODY_R}" fill="{WHITE}" fill-opacity="{DIM_OPACITY}"/>'
    fill = fill_shape(INNER_X, INNER_Y, INNER_H, body_fill_w, BODY_R, f'fill="{WHITE}"')
    nub = nub_shape(nub_fill_w)

    return (
        # width/height are the SVG's declared intrinsic size, separate from the
        # viewBox coordinate system below. GTK's background-image loader seems to
        # rasterize once at that intrinsic size and then stretch the bitmap to
        # fill whatever the CSS background-size box asks for -- at 24x12 that
        # stretch was a blurry ~2x bitmap upscale. Declaring a much larger
        # intrinsic size means that first raster already has plenty of
        # resolution, so the later stretch stays sharp.
        f'<svg width="{VIEW_W * 20:.0f}" height="{VIEW_H * 20:.0f}" viewBox="0 0 {VIEW_W:.3f} {VIEW_H:.3f}" xmlns="http://www.w3.org/2000/svg">'
        f'{nub}{track}{fill}{digit_overlay}{bolt_overlay}'
        '</svg>'
    )


def main():
    if ICONS_DIR.exists():
        shutil.rmtree(ICONS_DIR)
    ICONS_DIR.mkdir(parents=True)

    css_rules = ["/* GENERATED by generate_battery_icons.py -- do not edit by hand */"]
    for pct in range(0, 101):
        for state, charging in (("discharging", False), ("charging", True)):
            out_path = ICONS_DIR / f"level-{pct}-{state}.svg"
            out_path.write_text(battery_svg(pct, charging))
            css_rules.append(
                f'#custom-battery.level-{pct}-{state} {{ background-image: url("file://{out_path}"); }}'
            )

    CSS_OUT.write_text("\n".join(css_rules) + "\n")
    print(f"Wrote {len(list(ICONS_DIR.glob('*.svg')))} icons to {ICONS_DIR}")
    print(f"Wrote {CSS_OUT}")


if __name__ == "__main__":
    main()
