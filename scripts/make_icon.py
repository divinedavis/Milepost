#!/usr/bin/env python3
"""Draw the Milepost app icon: near-black field, one orange route winding up
the tile, a white start dot and an orange milepost marker at the end.

    ~/.venvs/spendcap/bin/python scripts/make_icon.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Milepost" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
MARKETING = ROOT / "marketing"

FIELD = (0x0E, 0x0E, 0x0E)
FIELD_DEEP = (0x05, 0x05, 0x05)
ORANGE = (0xFF, 0x5B, 0x1A)
ORANGE_GLOW = (0xFF, 0x5B, 0x1A, 70)
WHITE = (0xFF, 0xFF, 0xFF)


def route(s: float) -> list[tuple[float, float]]:
    # A loose S-curve from bottom-left to upper-right.
    pts = [
        (0.20, 0.82), (0.30, 0.70), (0.44, 0.66), (0.56, 0.60),
        (0.60, 0.50), (0.52, 0.42), (0.48, 0.34), (0.58, 0.26),
        (0.72, 0.34),
    ]
    return [(x * s, y * s) for x, y in pts]


def render(size: int) -> Image.Image:
    s = size
    img = Image.new("RGB", (s, s), FIELD)
    px = img.load()
    for y in range(s):
        t = y / (s - 1)
        row = tuple(round(FIELD[i] + (FIELD_DEEP[i] - FIELD[i]) * t) for i in range(3))
        for x in range(s):
            px[x, y] = row

    # Super-sample the line work for smooth edges.
    k = 4
    big = Image.new("RGBA", (s * k, s * k), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    pts = route(s * k)
    glow_w = round(s * k * 0.11)
    line_w = round(s * k * 0.065)
    d.line(pts, fill=ORANGE_GLOW, width=glow_w, joint="curve")
    d.line(pts, fill=(*ORANGE, 255), width=line_w, joint="curve")
    for p in (pts[0], pts[-1]):
        r = line_w / 2
        d.ellipse((p[0] - r, p[1] - r, p[0] + r, p[1] + r), fill=(*ORANGE, 255))

    # Start dot.
    sx, sy = pts[0]
    r = s * k * 0.055
    d.ellipse((sx - r, sy - r, sx + r, sy + r), fill=(*WHITE, 255))
    r2 = s * k * 0.028
    d.ellipse((sx - r2, sy - r2, sx + r2, sy + r2), fill=(*ORANGE, 255))

    # Milepost marker at the end: a rounded post with a white band.
    ex, ey = pts[-1]
    pw, ph = s * k * 0.075, s * k * 0.22
    d.rounded_rectangle((ex - pw / 2, ey - ph, ex + pw / 2, ey), radius=pw / 2, fill=(*WHITE, 255))
    band_h = s * k * 0.05
    d.rectangle((ex - pw / 2, ey - ph * 0.62, ex + pw / 2, ey - ph * 0.62 + band_h), fill=(*ORANGE, 255))

    small = big.resize((s, s), Image.LANCZOS)
    return Image.alpha_composite(img.convert("RGBA"), small).convert("RGB")


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    MARKETING.mkdir(parents=True, exist_ok=True)
    icon = render(1024)
    icon.save(ICONSET / "icon-1024.png")
    mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=229, fill=255)
    rounded = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    rounded.paste(icon, mask=mask)
    rounded.save(MARKETING / "icon-rounded.png")
    print(f"wrote {ICONSET / 'icon-1024.png'}")


if __name__ == "__main__":
    main()
