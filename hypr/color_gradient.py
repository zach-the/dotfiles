#!/usr/bin/env python3
"""Shared OKLab color-mixing helpers for waybar custom modules that color
their text along a percentage gradient (battery_color.py, volume_color.py).
Mixing happens in OKLab (Björn Ottosson,
https://bottosson.github.io/posts/oklab/) rather than plain sRGB so the
gradient stays perceptually smooth instead of drifting through the muddy
tones a plain lerp produces between unrelated hues.
"""


def hex_to_srgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return c * 12.92 if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def linear_to_oklab(r, g, b):
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    return (
        0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
        1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
        0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_,
    )


def oklab_to_linear(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    return (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    )


def hex_to_oklab(h):
    return linear_to_oklab(*(srgb_to_linear(c) for c in hex_to_srgb(h)))


def oklab_to_hex(lab):
    r, g, b = (linear_to_srgb(c) for c in oklab_to_linear(*lab))
    return "#{:02x}{:02x}{:02x}".format(
        round(max(0.0, min(1.0, r)) * 255),
        round(max(0.0, min(1.0, g)) * 255),
        round(max(0.0, min(1.0, b)) * 255),
    )


def mix(hex_a, hex_b, t):
    a, b = hex_to_oklab(hex_a), hex_to_oklab(hex_b)
    return oklab_to_hex(tuple(x + (y - x) * t for x, y in zip(a, b)))


def smoothstep(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def gradient_color(value, stops):
    """OKLab-mix `value` along a piecewise gradient defined by `stops`, a
    list of (threshold, hex_color) pairs ascending by threshold. Each
    segment between consecutive stops is smoothstep-eased; values outside
    the range clamp to the first/last stop's color."""
    value = max(stops[0][0], min(stops[-1][0], value))
    for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
        if value <= t1:
            t = (value - t0) / (t1 - t0) if t1 != t0 else 1.0
            return mix(c0, c1, smoothstep(t))
    return stops[-1][1]
