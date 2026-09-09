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

The percentage number is baked in and, rather than drawn in a third color,
is knocked out as a transparent cutout wherever it crosses the white fill
(via an SVG mask) and drawn solid white wherever it's over the empty/
transparent area -- so it stays legible at every fill level using only the
two colors the rest of the icon uses.

Two parallel sets are rendered: "pct-N-<state>" (digit baked in, as above)
and "plain-N-<state>" (same outline/fill, no digit at all) -- clicking the
battery module (battery_toggle.sh) toggles which prefix battery_color.py
picks its class from.

Output: waybar/icons/battery/{pct,plain}-{0..100}-{discharging,charging}.svg
(within each prefix, charging/discharging are pixel-identical now that
color no longer distinguishes them -- kept as separate files so
battery_color.py's per-state class names still resolve to something), plus
waybar/battery-icons-generated.css, which style.css @imports, mapping each
"<prefix>-N-<state>" class to its background-image.

Run manually to regenerate: ./generate_battery_icons.py
"""
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ICONS_DIR = ROOT / "icons" / "battery"
CSS_OUT = ROOT / "battery-icons-generated.css"

WHITE = "#ffffff"

# Geometry, in a 22x11 viewBox -- outline body + right-hand nub, matching the
# proportions of the real macOS menu-bar battery glyph.
OUTLINE = f'<rect x="0.75" y="0.75" width="18.5" height="9.5" rx="2" fill="none" stroke="{WHITE}" stroke-width="1"/>'
NUB = f'<rect x="19.5" y="3.7" width="1.9" height="3.6" rx="0.6" fill="{WHITE}"/>'
INNER_X, INNER_Y = 2.35, 2.35
INNER_W, INNER_H = 18.5 - 2 * 1.6, 9.5 - 2 * 1.6
FONT_FAMILY = "SF Pro, DejaVu Sans, sans-serif"
TEXT_X = INNER_X + INNER_W / 2


def battery_svg(pct):
    pct = max(0, min(100, pct))
    fill_w = INNER_W * pct / 100

    # "100" is the only 3-digit value -- shrink it slightly so it doesn't
    # crowd the pill; everything else shares one size.
    font_size = 5.6 if pct == 100 else 7.2
    text_y = 8.3 if pct == 100 else 8.0
    num = str(pct)
    text_attrs = f'text-anchor="middle" font-size="{font_size}" font-weight="800" font-family="{FONT_FAMILY}"'

    def text_el(fill):
        return f'<text x="{TEXT_X:.2f}" y="{text_y}" {text_attrs} fill="{fill}">{num}</text>'

    # The fill is masked by itself-minus-the-digit: white where filled, black
    # (= knocked out to transparent) where the number sits on top of it.
    fill_mask = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" fill="white"/>'
        f'{text_el("black")}'
    )
    bar = (
        f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" '
        f'fill="{WHITE}" mask="url(#fm)"/>'
    )

    # The empty (non-fill) remainder of the interior gets the same number in
    # solid white, clipped to just that region -- together the two halves
    # read as one continuous digit that's a cutout over the fill and solid
    # over the empty area.
    empty_clip = (
        f'<path clip-rule="evenodd" d="M0 0H22V11H0Z '
        f'M{INNER_X} {INNER_Y}H{INNER_X + fill_w:.3f}V{INNER_Y + INNER_H}H{INNER_X}Z"/>'
    )
    light_number = f'<g clip-path="url(#ec)">{text_el(WHITE)}</g>'

    return (
        # width/height are the SVG's declared intrinsic size, separate from the
        # viewBox coordinate system below. GTK's background-image loader seems to
        # rasterize once at that intrinsic size and then stretch the bitmap to
        # fill whatever the CSS background-size box asks for -- at 24x12 that
        # stretch was a blurry ~2x bitmap upscale. Declaring a much larger
        # intrinsic size means that first raster already has plenty of
        # resolution, so the later stretch stays sharp.
        '<svg width="440" height="220" viewBox="0 0 22 11" xmlns="http://www.w3.org/2000/svg">'
        f'<defs><mask id="fm">{fill_mask}</mask><clipPath id="ec">{empty_clip}</clipPath></defs>'
        f'{OUTLINE}{NUB}{bar}{light_number}'
        '</svg>'
    )


def plain_battery_svg(pct):
    pct = max(0, min(100, pct))
    fill_w = INNER_W * pct / 100
    bar = f'<rect x="{INNER_X}" y="{INNER_Y}" width="{fill_w:.3f}" height="{INNER_H:.3f}" rx="1" fill="{WHITE}"/>'
    return (
        '<svg width="440" height="220" viewBox="0 0 22 11" xmlns="http://www.w3.org/2000/svg">'
        f'{OUTLINE}{NUB}{bar}'
        '</svg>'
    )


def main():
    if ICONS_DIR.exists():
        shutil.rmtree(ICONS_DIR)
    ICONS_DIR.mkdir(parents=True)

    css_rules = ["/* GENERATED by generate_battery_icons.py -- do not edit by hand */"]
    for pct in range(0, 101):
        renders = {"pct": battery_svg(pct), "plain": plain_battery_svg(pct)}
        for prefix, svg in renders.items():
            for state in ("discharging", "charging"):
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
