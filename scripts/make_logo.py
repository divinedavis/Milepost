#!/usr/bin/env python3
"""Milepost logo: a milepost mark (rounded post, orange band, route arriving
at its foot) and the wordmark in Avenir Next Heavy, outlined to paths so the
SVGs need no font installed.

    ~/.venvs/spendcap/bin/python scripts/make_logo.py

Writes marketing/logo/*.svg + *.png and a preview sheet.
Needs fonttools (venv) and rsvg-convert (brew librsvg).
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTCollection
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "logo"

ORANGE = "#FF5B1A"
INK_DARK = "#FFFFFF"     # post + wordmark on a dark ground
INK_LIGHT = "#111111"    # post + wordmark on a light ground
BG_DARK = "#0E0E0E"
BG_LIGHT = "#FFFFFF"

FONT = "/System/Library/Fonts/Avenir Next.ttc"
FACE = 8  # Avenir Next Heavy


# ---------------------------------------------------------------- wordmark

def wordmark_path(text: str, size: float, x: float, baseline: float, tracking: float = 0) -> tuple[str, float]:
    font = TTCollection(FONT).fonts[FACE]
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    parts: list[str] = []
    pen_x = x
    for ch in text:
        glyph = glyphs[cmap[ord(ch)]]
        pen = SVGPathPen(glyphs)
        glyph.draw(TransformPen(pen, (scale, 0, 0, -scale, pen_x, baseline)))
        parts.append(pen.getCommands())
        pen_x += glyph.width * scale + tracking
    return " ".join(parts), pen_x


# -------------------------------------------------------------------- mark

def mark_svg(ink: str, x: float = 0, y: float = 0, s: float = 1) -> str:
    """The mark in a 100x100 box at (x, y) scaled by s."""
    return f"""<g transform="translate({x} {y}) scale({s})">
  <path d="M 14 84 C 32 84, 34 60, 50 64 C 58 66, 62 74, 66 82"
        fill="none" stroke="{ORANGE}" stroke-width="10" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 56 20 A 10 10 0 0 1 76 20 V 90 H 56 Z" fill="{ink}"/>
  <rect x="56" y="28" width="20" height="11" fill="{ORANGE}"/>
  <circle cx="14" cy="84" r="8" fill="{ink}"/>
  <circle cx="14" cy="84" r="3.6" fill="{ORANGE}"/>
</g>"""


def svg(width: float, height: float, body: str, bg: str | None) -> str:
    rect = f'<rect width="{width}" height="{height}" fill="{bg}"/>' if bg else ""
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" '
            f'width="{width}" height="{height}">{rect}\n{body}\n</svg>\n')


def build(name: str, content: str, png_width: int) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{name}.svg"
    path.write_text(content)
    subprocess.run(["rsvg-convert", "-w", str(png_width), str(path), "-o", str(OUT / f"{name}.png")], check=True)


def main() -> None:
    for variant, ink, bg in (("dark", INK_DARK, BG_DARK), ("light", INK_LIGHT, BG_LIGHT)):
        # Mark only, on its ground and on nothing.
        build(f"mark-{variant}", svg(100, 100, mark_svg(ink), bg), 1024)
        build(f"mark-{variant}-transparent", svg(100, 100, mark_svg(ink), None), 1024)

        # Horizontal lockup: mark 100 tall, wordmark cap-aligned beside it.
        size = 78
        text, end = wordmark_path("Milepost", size, 122, 82, tracking=-1.5)
        w = round(end + 24)
        body = mark_svg(ink) + f'\n<path d="{text}" fill="{ink}"/>'
        build(f"lockup-horizontal-{variant}", svg(w, 100, body, bg), 2400)
        build(f"lockup-horizontal-{variant}-transparent", svg(w, 100, body, None), 2400)

        # Stacked lockup for square slots.
        text, end = wordmark_path("Milepost", 60, 0, 0, tracking=-1)
        tw = end
        W = 320
        body = mark_svg(ink, x=(W - 140) / 2, y=24, s=1.4) + \
            f'\n<g transform="translate({(W - tw) / 2} 232)"><path d="{text}" fill="{ink}"/></g>'
        build(f"lockup-stacked-{variant}", svg(W, 280, body, bg), 1600)

    # Preview sheet.
    tiles = [
        ("lockup-horizontal-dark", 1400), ("lockup-horizontal-light", 1400),
        ("lockup-stacked-dark", 600), ("lockup-stacked-light", 600),
        ("mark-dark", 400), ("mark-light", 400),
    ]
    imgs = []
    for name, w in tiles:
        im = Image.open(OUT / f"{name}.png").convert("RGB")
        imgs.append(im.resize((w, round(im.height * w / im.width)), Image.LANCZOS))
    gap = 40
    sheet_w = 1400 + 2 * gap
    rows = [imgs[0:1], imgs[1:2], imgs[2:4], imgs[4:6]]
    sheet_h = gap + sum(max(i.height for i in r) + gap for r in rows)
    sheet = Image.new("RGB", (sheet_w, sheet_h), (40, 40, 40))
    y = gap
    for r in rows:
        total = sum(i.width for i in r) + gap * (len(r) - 1)
        x = (sheet_w - total) // 2
        for im in r:
            sheet.paste(im, (x, y))
            x += im.width + gap
        y += max(i.height for i in r) + gap
    sheet.save(OUT / "preview.png")
    print(f"wrote {len(list(OUT.glob('*')))} files to {OUT}")


if __name__ == "__main__":
    main()
