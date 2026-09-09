#!/usr/bin/env python3
"""Render the waybar custom/volume glyph: a speaker diaphragm with
quarter-circle sound-wave rings growing out of its tip to the right, same
visual language (and the same ring_segment math) as generate_wifi_icons.py.

Seventeen states:
  vol0.svg:   diaphragm alone, full white -- volume is unmuted but at 0%
  tier1..10:  diaphragm + one continuous white quarter-annulus, fixed
              inner radius, whose *outer* radius grows with the tier -- a
              single arc that extends outward rather than separate
              concentric rings, one tier per 10% band (0-10, 10-20, ...,
              90-100), matching the 10%-per-click scroll/button step in
              config.jsonc so every click visibly grows or shrinks it
  over1..5:   volume boosted past 100% (wpctl's --limit 1.5 allows up to
              150%) -- the same growing-arc shape as tier1..10, but red and
              restarting from RING_INNER, one per 10% band from 100-150%,
              so over5 ends up the same full size as tier10 (just red
              instead of white) rather than growing past the icon's edge
  muted.svg:  diaphragm dimmed (translucent white, no arc) + a short
              diagonal strike-through -- deliberately distinct from vol0,
              which is unmuted and just has nothing to emit

The diaphragm outline is Lucide's volume icon path (MIT licensed), used
filled instead of stroked to match the other bar icons' solid weight.

Output: waybar/icons/volume/{vol0,tier1..10,over1..5,muted}.svg, plus
waybar/volume-icons-generated.css, which style.css @imports, mapping
"vol0"/"tier1".."tier10"/"over1".."over5"/"muted" classes (set by
volume_color.py) to the matching background-image.

Run manually to regenerate: ./generate_volume_icons.py
"""
import math
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ICONS_DIR = ROOT / "icons" / "volume"
CSS_OUT = ROOT / "volume-icons-generated.css"

WHITE = "#ffffff"
RED = "#ff4444"
DIM_OPACITY = "0.3"

# Lucide's "volume" icon path (https://lucide.dev, MIT) -- box + cone,
# closed, so it can be filled directly instead of stroked.
DIAPHRAGM_PATH = (
    "M11 4.702a.705.705 0 0 0-1.203-.498L6.413 7.587A1.4 1.4 0 0 1 5.416 8H3a1 1 0 0 0-1 1v6"
    "a1 1 0 0 0 1 1h2.416a1.4 1.4 0 0 1 .997.413l3.383 3.384A.705.705 0 0 0 11 19.298z"
)

# Pivot at the cone's mouth (the path's rightmost edge, and the vertical
# midpoint between its top/bottom corners) -- rings sweep the 90 degrees
# centered on "straight right" out of it.
PIVOT_X, PIVOT_Y = 11.0, 12.0
START_DEG, END_DEG = -45, 45

# Reshapes the stock diaphragm taller/narrower, scaled around the pivot so
# the mouth it's anchored to (and the rings growing out of it) don't move.
DIAPHRAGM_SCALE_X, DIAPHRAGM_SCALE_Y = 1.2, 1.3


def _point(radius, deg):
    rad = math.radians(deg)
    return PIVOT_X + radius * math.cos(rad), PIVOT_Y + radius * math.sin(rad)


def diaphragm(opacity="1"):
    transform = (
        f"translate({PIVOT_X} {PIVOT_Y}) scale({DIAPHRAGM_SCALE_X} {DIAPHRAGM_SCALE_Y}) "
        f"translate({-PIVOT_X} {-PIVOT_Y})"
    )
    return f'<path d="{DIAPHRAGM_PATH}" fill="{WHITE}" fill-opacity="{opacity}" transform="{transform}"/>'


def ring_segment(r_in, r_out, color=WHITE, opacity="1"):
    xi0, yi0 = _point(r_in, START_DEG)
    xi1, yi1 = _point(r_in, END_DEG)
    xo1, yo1 = _point(r_out, END_DEG)
    xo0, yo0 = _point(r_out, START_DEG)
    d = (
        f'M{xi0:.3f} {yi0:.3f} '
        f'A{r_in} {r_in} 0 0 1 {xi1:.3f} {yi1:.3f} '
        f'L{xo1:.3f} {yo1:.3f} '
        f'A{r_out} {r_out} 0 0 0 {xo0:.3f} {yo0:.3f} Z'
    )
    return f'<path d="{d}" fill="{color}" fill-opacity="{opacity}"/>'


N_TIERS = 10  # one per 10% band, matching the 10%-per-click scroll step
RING_INNER = 1.7  # fixed -- only the outer edge moves, so the arc grows continuously
RING_MAX_OUTER = 16.0
RING_OUTER_BY_TIER = {
    tier: RING_INNER + tier * (RING_MAX_OUTER - RING_INNER) / N_TIERS
    for tier in range(1, N_TIERS + 1)
}
SLASH = f'<line x1="1" y1="6" x2="13" y2="18" stroke="{WHITE}" stroke-opacity="{DIM_OPACITY}" stroke-width="1.8" stroke-linecap="round"/>'

N_OVER_TIERS = 5  # boosted volume, 100-150% in 10% bands
OVER_OUTER_BY_TIER = {
    tier: RING_INNER + tier * (RING_MAX_OUTER - RING_INNER) / N_OVER_TIERS
    for tier in range(1, N_OVER_TIERS + 1)
}

# Full-size dimmed track, same idea as the white base under over1..5 below --
# shows the full 0-100% extent so a partial white arc reads as "this much of
# the range", not just an arbitrarily-sized wedge.
GREY_TRACK = ring_segment(RING_INNER, RING_MAX_OUTER, opacity=DIM_OPACITY)

FILES = {"vol0": diaphragm() + GREY_TRACK, "muted": diaphragm(DIM_OPACITY) + SLASH}
FILES.update({
    f"tier{tier}": diaphragm() + GREY_TRACK + ring_segment(RING_INNER, outer)
    for tier, outer in RING_OUTER_BY_TIER.items()
})
FILES.update({
    # Full white arc stays underneath as a base -- red grows on top of it
    # from the same inner radius, so red only ever covers/replaces the
    # inner portion, leaving the rest showing through as white until over5
    # catches up to the same full outer edge.
    f"over{tier}": diaphragm() + ring_segment(RING_INNER, RING_MAX_OUTER) + ring_segment(RING_INNER, outer, color=RED)
    for tier, outer in OVER_OUTER_BY_TIER.items()
})


VIEW_W, VIEW_H = 30, 24  # a bit wider than tall -- 5 rings need more room to the right


def svg(shapes):
    # Large intrinsic width/height (vs. the viewBox) for the same reason as
    # generate_battery_icons.py: GTK's background-image loader rasterizes
    # once at the declared intrinsic size, then stretches that bitmap to
    # the CSS box, so a small intrinsic size makes for a blurry upscale
    # regardless of the eventual display size.
    return (
        f'<svg width="{VIEW_W * 16}" height="{VIEW_H * 16}" viewBox="0 0 {VIEW_W} {VIEW_H}" '
        f'xmlns="http://www.w3.org/2000/svg">{shapes}</svg>'
    )


def main():
    if ICONS_DIR.exists():
        shutil.rmtree(ICONS_DIR)
    ICONS_DIR.mkdir(parents=True)

    css_rules = ["/* GENERATED by generate_volume_icons.py -- do not edit by hand */"]
    for name, shapes in FILES.items():
        out_path = ICONS_DIR / f"{name}.svg"
        out_path.write_text(svg(shapes))
        css_rules.append(f'#custom-volume.{name} {{ background-image: url("file://{out_path}"); }}')

    CSS_OUT.write_text("\n".join(css_rules) + "\n")
    print(f"Wrote {len(list(ICONS_DIR.glob('*.svg')))} icons to {ICONS_DIR}")
    print(f"Wrote {CSS_OUT}")


if __name__ == "__main__":
    main()
