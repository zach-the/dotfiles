#!/usr/bin/env python3
"""Render a macOS-style battery gauge for the waybar custom/battery module.

Unlike icon themes (Adwaita, WhiteSur, ...) that swap between ~11 discrete
pre-drawn shapes, real macOS draws one outline with an inner bar that
continuously widens with charge % -- this draws that same shape in pure SVG
(original artwork, no external assets) at every integer percent so the fill
looks continuous as the battery drains.

The whole icon is strictly two-tone: white and transparent, nothing else --
outline, nub and fill are all solid white, and everything outside them
(including the "empty" remainder of the pill) is fully transparent, so it
sits cleanly on any wallpaper/bar background without needing a backing plate.

The percentage number (pct-prefix icons only) and the charging bolt (both
prefixes) are baked in the same way: knocked out as a transparent cutout
wherever they cross the white fill (via an SVG mask), and drawn solid white
wherever they're over the empty/transparent area -- so they stay legible at
every fill level using only the two colors the rest of the icon uses.

All digits share one font size, including "100". The digit's x-position is
a fixed offset from the fill's left edge (not the pill's horizontal center)
-- picked so a full-height bolt fits to its left with a small gap, and the
pill's width is then sized to just clear "100" (the widest value) on the
right with a small margin, instead of mirroring the bolt's space on both
sides. Those numbers were picked empirically: see the PIL measurement of
the actual SF Pro glyphs in the git history of this file if the font or
sizes change and it needs re-deriving, rather than guessing at
character-width ratios.

Two parallel sets are rendered: "pct-N-<state>" (digit baked in) and
"plain-N-<state>" (same outline/fill, no digit) -- clicking the battery
module (battery_toggle.sh) toggles which prefix battery_color.py picks its
class from. Within each, "charging" adds the bolt and "discharging" doesn't.

Output: waybar/icons/battery/{pct,plain}-{0..100}-{discharging,charging}.svg,
plus waybar/battery-icons-generated.css, which style.css @imports, mapping
each "<prefix>-N-<state>" class to its background-image.

Run manually to regenerate: ./generate_battery_icons.py
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ICONS_DIR = ROOT / "icons" / "battery"
CSS_OUT = ROOT / "battery-icons-generated.css"

WHITE = "#ffffff"

# Geometry, in a viewBox at the original height (9.5 outline, matching the
# proportions of the real macOS menu-bar battery glyph) but only as wide as
# it needs to be -- see the note on TEXT_X/INNER_W below.
OUTLINE_H = 9.5
NUB_W, NUB_H = 1.9, 3.6
OUTLINE = f'<rect x="0.75" y="0.75" width="{{outline_w:.3f}}" height="{OUTLINE_H}" rx="2" fill="none" stroke="{WHITE}" stroke-width="1"/>'
NUB_Y = 0.75 + (OUTLINE_H - NUB_H) / 2
NUB = f'<rect x="{{nub_x:.3f}}" y="{NUB_Y:.3f}" width="{NUB_W}" height="{NUB_H}" rx="0.6" fill="{WHITE}"/>'
INNER_X, INNER_Y = 2.35, 2.35
INNER_H = OUTLINE_H - 2 * 1.6
FONT_FAMILY = "SF Pro, DejaVu Sans, sans-serif"
FONT_SIZE = 7.2
TEXT_Y = INNER_Y + 5.65

# A proper lightning-bolt silhouette (Lucide's "zap" icon shape), scaled to
# the same height as the digits -- measured from the actual SF Pro Heavy
# glyphs at FONT_SIZE, not guessed -- but narrower than that shape's native
# aspect ratio, as a local point list. Sits near the fill's left edge,
# comfortably clear of the digit.
BOLT_H = 5.35  # SF Pro Text Heavy digit height at FONT_SIZE=7.2
BOLT_W = 3.4  # narrower than Lucide's native 18:20 aspect (would be 4.815)
_sx, _sy = BOLT_W / 18, BOLT_H / 20
BOLT_LOCAL = [(x * _sx, y * _sy) for x, y in [(10, 0), (0, 12), (9, 12), (8, 20), (18, 8), (9, 8)]]
BOLT_X = INNER_X + 1.15  # nudged right ~1-2 screen px from the fill's edge
BOLT_Y = INNER_Y + (INNER_H - BOLT_H) / 2

# The digit sits a fixed distance right of the bolt (not centered on the
# pill), and the pill is only as wide as it needs to be to clear "100" (the
# widest value, half-width 7.08 at FONT_SIZE=7.2 in SF Pro Heavy) on the
# right with a small margin -- rather than mirroring the bolt's space on
# both sides, which is what left a wide empty gap after "100" before.
_DIGIT_GAP, _DIGIT_HALF_W_MAX, _RIGHT_MARGIN = 0.6, 7.08, 0.6
TEXT_X = BOLT_X + BOLT_W + _DIGIT_GAP + _DIGIT_HALF_W_MAX
INNER_W = (TEXT_X - INNER_X) + _DIGIT_HALF_W_MAX + _RIGHT_MARGIN
OUTLINE_W = INNER_W + 2 * 1.6
NUB_X = 0.75 + OUTLINE_W + 0.25
VIEW_W = NUB_X + NUB_W + 0.6
VIEW_H = 0.75 * 2 + OUTLINE_H

OUTLINE = OUTLINE.format(outline_w=OUTLINE_W)
NUB = NUB.format(nub_x=NUB_X)


def bolt_polygon(fill):
    pts = " ".join(f"{BOLT_X + x:.3f},{BOLT_Y + y:.3f}" for x, y in BOLT_LOCAL)
    return f'<polygon points="{pts}" fill="{fill}"/>'


def battery_svg(pct, charging):
    pct = max(0, min(100, pct))
    fill_w = INNER_W * pct / 100
    num = str(pct)
    text_attrs = f'text-anchor="middle" font-size="{FONT_SIZE}" font-weight="800" font-family="{FONT_FAMILY}"'

    def text_el(fill):
        return f'<text x="{TEXT_X:.2f}" y="{TEXT_Y}" {text_attrs} fill="{fill}">{num}</text>'

    cutout = text_el("black") + (bolt_polygon("black") if charging else "")
    overlay = text_el(WHITE) + (bolt_polygon(WHITE) if charging else "")

    # The fill is masked by itself-minus-the-cutouts: white where filled,
    # black (= knocked out to transparent) where the digit/bolt sit on it.
    fill_mask = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" fill="white"/>'
        f'{cutout}'
    )
    bar = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" '
        f'fill="{WHITE}" mask="url(#fm)"/>'
    )

    # The empty (non-fill) remainder of the interior gets the same shapes in
    # solid white, clipped to just that region -- together the two halves
    # read as continuous digit/bolt that are a cutout over the fill and
    # solid over the empty area.
    empty_clip = (
        f'<path clip-rule="evenodd" d="M0 0H{VIEW_W:.3f}V{VIEW_H:.3f}H0Z '
        f'M{INNER_X} {INNER_Y}H{INNER_X + fill_w:.3f}V{INNER_Y + INNER_H}H{INNER_X}Z"/>'
    )
    light_overlay = f'<g clip-path="url(#ec)">{overlay}</g>'

    return (
        # width/height are the SVG's declared intrinsic size, separate from the
        # viewBox coordinate system below. GTK's background-image loader seems to
        # rasterize once at that intrinsic size and then stretch the bitmap to
        # fill whatever the CSS background-size box asks for -- at 24x12 that
        # stretch was a blurry ~2x bitmap upscale. Declaring a much larger
        # intrinsic size means that first raster already has plenty of
        # resolution, so the later stretch stays sharp.
        f'<svg width="{VIEW_W * 20:.0f}" height="{VIEW_H * 20:.0f}" viewBox="0 0 {VIEW_W:.3f} {VIEW_H:.3f}" xmlns="http://www.w3.org/2000/svg">'
        f'<defs><mask id="fm">{fill_mask}</mask><clipPath id="ec">{empty_clip}</clipPath></defs>'
        f'{OUTLINE}{NUB}{bar}{light_overlay}'
        '</svg>'
    )


def plain_battery_svg(pct, charging):
    pct = max(0, min(100, pct))
    fill_w = INNER_W * pct / 100

    if not charging:
        bar = f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" fill="{WHITE}"/>'
        return (
            f'<svg width="{VIEW_W * 20:.0f}" height="{VIEW_H * 20:.0f}" viewBox="0 0 {VIEW_W:.3f} {VIEW_H:.3f}" xmlns="http://www.w3.org/2000/svg">'
            f'{OUTLINE}{NUB}{bar}'
            '</svg>'
        )

    # Same cutout/overlay bolt technique as battery_svg, just without a digit.
    fill_mask = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" fill="white"/>'
        f'{bolt_polygon("black")}'
    )
    bar = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" '
        f'fill="{WHITE}" mask="url(#fm)"/>'
    )
    empty_clip = (
        f'<path clip-rule="evenodd" d="M0 0H{VIEW_W:.3f}V{VIEW_H:.3f}H0Z '
        f'M{INNER_X} {INNER_Y}H{INNER_X + fill_w:.3f}V{INNER_Y + INNER_H}H{INNER_X}Z"/>'
    )
    light_bolt = f'<g clip-path="url(#ec)">{bolt_polygon(WHITE)}</g>'

    return (
        f'<svg width="{VIEW_W * 20:.0f}" height="{VIEW_H * 20:.0f}" viewBox="0 0 {VIEW_W:.3f} {VIEW_H:.3f}" xmlns="http://www.w3.org/2000/svg">'
        f'<defs><mask id="fm">{fill_mask}</mask><clipPath id="ec">{empty_clip}</clipPath></defs>'
        f'{OUTLINE}{NUB}{bar}{light_bolt}'
        '</svg>'
    )


def main():
    if ICONS_DIR.exists():
        shutil.rmtree(ICONS_DIR)
    ICONS_DIR.mkdir(parents=True)

    css_rules = ["/* GENERATED by generate_battery_icons.py -- do not edit by hand */"]
    for pct in range(0, 101):
        for state, charging in (("discharging", False), ("charging", True)):
            renders = {"pct": battery_svg(pct, charging), "plain": plain_battery_svg(pct, charging)}
            for prefix, svg in renders.items():
                out_path = ICONS_DIR / f"{prefix}-{pct}-{state}.svg"
                out_path.write_text(svg)
                css_rules.append(
                    f'#custom-battery.{prefix}-{pct}-{state} {{ background-image: url("file://{out_path}"); }}'
                )

    CSS_OUT.write_text("\n".join(css_rules) + "\n")
    print(f"Wrote {len(list(ICONS_DIR.glob('*.svg')))} icons to {ICONS_DIR}")
    print(f"Wrote {CSS_OUT}")


if __name__ == "__main__":
    main()
