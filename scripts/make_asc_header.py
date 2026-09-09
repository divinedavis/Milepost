#!/usr/bin/env python3
"""App Store "Header and Search Results" banner → marketing/asc-header/.

Style reference: Facebook's App Store header (flat brand-colour field, the
wordmark centred, small floating pieces of the product around it, no phone).
For Milepost: orange field, white runner wordmark, and around it a route
circle, a split tile, a pace chip, a mile badge, a clock chip and a Start pill.

Sizes: 5244x2950 (Apple's large size) and a 1280x720 downscale. The upload is
browser-only (Distribution → Product Page Information → Header and Search
Results). The App Store overlays a status bar and nav buttons on the top
~20%, so nothing important sits there.

    ~/.venvs/spendcap/bin/python scripts/make_asc_header.py
"""
from __future__ import annotations

import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc_make_screenshots import INK, ORANGE, WHITE, WORDMARK, font  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "asc-header"
W, H = 5244, 2950
ORANGE_TOP = (255, 112, 48)
ORANGE_BOTTOM = (242, 78, 14)
CARD = (22, 22, 22)
BLUE = (41, 112, 224)          # Theme.splitBlue
GREEN = (52, 199, 89)
RED = (255, 59, 48)
SOFT = (170, 170, 175)


def gradient() -> Image.Image:
    im = Image.new("RGB", (1, H))
    px = im.load()
    for y in range(H):
        t = y / (H - 1)
        px[0, y] = tuple(int(a + (b - a) * t) for a, b in zip(ORANGE_TOP, ORANGE_BOTTOM))
    return im.resize((W, H))


def shadow(canvas: Image.Image, layer: Image.Image, pos: tuple[int, int], blur: int = 40) -> None:
    """Paste a soft drop shadow under an RGBA layer, then the layer."""
    alpha = layer.split()[3]
    sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    sh.putalpha(alpha.point(lambda a: int(a * 0.35)))
    pad = blur * 3
    big = Image.new("RGBA", (layer.width + 2 * pad, layer.height + 2 * pad), (0, 0, 0, 0))
    big.paste(sh, (pad, pad + 30))
    big = big.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(big, (pos[0] - pad, pos[1] - pad), big)
    canvas.paste(layer, pos, layer)


def rounded(size: tuple[int, int], radius: int, fill: tuple) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    im = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, size[0] - 1, size[1] - 1), radius=radius, fill=fill)
    return im, d


def route_circle(diameter: int) -> Image.Image:
    """A dark disc with a route polyline, start and end dots, like an avatar."""
    im = Image.new("RGBA", (diameter, diameter), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse((0, 0, diameter - 1, diameter - 1), fill=CARD)
    d.ellipse((0, 0, diameter - 1, diameter - 1), outline=WHITE, width=int(diameter * 0.03))
    s = diameter
    pts = [(0.30, 0.68), (0.36, 0.42), (0.50, 0.30), (0.62, 0.40), (0.58, 0.58), (0.70, 0.72)]
    pts = [(int(x * s), int(y * s)) for x, y in pts]
    d.line(pts, fill=ORANGE, width=int(s * 0.055), joint="curve")
    r = int(s * 0.05)
    for (x, y), c in ((pts[0], GREEN), (pts[-1], RED)):
        d.ellipse((x - r, y - r, x + r, y + r), fill=c, outline=WHITE, width=int(r * 0.35))
    return im


def split_tile(size: tuple[int, int]) -> Image.Image:
    """The splits bar: one filled blue column with its pace above, two idle."""
    im, d = rounded(size, int(size[1] * 0.14), CARD)
    w, h = size
    d.text((int(w * 0.09), int(h * 0.07)), "Splits (mi)", fill=SOFT, font=font(int(h * 0.10), bold=False))
    base = int(h * 0.86)
    col_w = int(w * 0.22)
    gap = int(w * 0.06)
    x = int(w * 0.09)
    heights = (0.30, 0.46, 0.26)
    for i, hh in enumerate(heights):
        top = base - int(h * hh)
        fill = BLUE if i == 1 else (58, 58, 58)
        d.rounded_rectangle((x, top, x + col_w, base), radius=int(col_w * 0.12), fill=fill)
        if i == 1:
            d.text((x + int(col_w * 0.16), top - int(h * 0.15)), "7:40", fill=WHITE, font=font(int(h * 0.11)))
            d.rectangle((x, base + int(h * 0.02), x + col_w, base + int(h * 0.045)), fill=ORANGE)
        x += col_w + gap
    return im


def chip(text: str, sub: str | None, h: int, fill: tuple, ink: tuple, sub_ink: tuple) -> Image.Image:
    f = font(int(h * (0.42 if sub else 0.5)))
    fs = font(int(h * 0.2), bold=False)
    tw = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), text, font=f)[2]
    sw = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), sub, font=fs)[2] if sub else 0
    w = max(tw, sw) + int(h * 0.7)
    im, d = rounded((w, h), h // 2 if not sub else int(h * 0.28), fill)
    if sub:
        d.text((int(h * 0.35), int(h * 0.12)), text, fill=ink, font=f)
        d.text((int(h * 0.35), int(h * 0.64)), sub, fill=sub_ink, font=fs)
    else:
        d.text((int(h * 0.35), int(h * 0.19)), text, fill=ink, font=f)
    return im


def start_pill(h: int) -> Image.Image:
    f = font(int(h * 0.44))
    tw = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox((0, 0), "Start", font=f)[2]
    w = tw + int(h * 1.5)
    im, d = rounded((w, h), h // 2, WHITE)
    # play triangle
    cx, cy, r = int(h * 0.5), h // 2, int(h * 0.17)
    d.polygon([(cx - r, cy - r), (cx - r, cy + r), (cx + r, cy)], fill=ORANGE)
    d.text((int(h * 0.85), int(h * 0.22)), "Start", fill=ORANGE, font=f)
    return im


def tilt(im: Image.Image, deg: float) -> Image.Image:
    return im.rotate(deg, resample=Image.BICUBIC, expand=True)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    canvas = gradient().convert("RGBA")

    # Wordmark, centred, a touch below the middle so the overlaid nav bar
    # at the top never touches it.
    wm = Image.open(WORDMARK).convert("RGBA")
    wm_w = int(W * 0.40)
    wm = wm.resize((wm_w, int(wm.height * wm_w / wm.width)), Image.LANCZOS)
    wm_pos = ((W - wm_w) // 2, int(H * 0.47) - wm.height // 2)
    shadow(canvas, wm, wm_pos, blur=60)

    # Left: route circle (avatar position) with a mile badge on its rim.
    circle = route_circle(int(H * 0.32))
    cpos = (int(W * 0.045), int(H * 0.46))
    shadow(canvas, circle, cpos)
    badge = chip("1 mi", None, int(H * 0.085), WHITE, ORANGE, ORANGE)
    # Top-right rim: the route's start and end dots sit low on the disc.
    canvas.paste(badge, (cpos[0] + circle.width - badge.width + int(H * 0.02),
                         cpos[1] - int(H * 0.005)), badge)

    # Right: split tile, tilted like the photo tiles in the reference.
    tile = tilt(split_tile((int(H * 0.36), int(H * 0.30))), -8)
    tpos = (W - tile.width - int(W * 0.035), int(H * 0.50))
    shadow(canvas, tile, tpos)

    # Top-left: pace chip, tilted the other way.
    pace = tilt(chip("7:40", "avg. pace /mi", int(H * 0.19), CARD, WHITE, SOFT), 8)
    shadow(canvas, pace, (int(W * 0.15), int(H * 0.10)))

    # Top-right: clock chip.
    clock = tilt(chip("00:09:23", None, int(H * 0.15), CARD, WHITE, SOFT), -6)
    shadow(canvas, clock, (int(W * 0.66), int(H * 0.12)))

    # Bottom centre: the Start pill (the one button the app is about).
    pill = start_pill(int(H * 0.16))
    shadow(canvas, pill, ((W - pill.width) // 2, int(H * 0.73)))

    out = canvas.convert("RGB")
    out.save(OUT / "header-5244x2950.png", optimize=True)
    out.resize((1280, 720), Image.LANCZOS).save(OUT / "header-1280x720.png", optimize=True)
    print(f"wrote {OUT}/header-5244x2950.png and header-1280x720.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
