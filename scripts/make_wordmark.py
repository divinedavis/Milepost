#!/usr/bin/env python3
"""Milepost runner wordmark: heavy rounded italic caps where the M is drawn
as a striding runner's legs. The other letters are Arial Rounded Bold
outlines (stroke-matched), skewed for the italic; the M is a monoline path.

    ~/.venvs/spendcap/bin/python scripts/make_wordmark.py
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "marketing" / "logo"
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

NAVY = "#3D6BE0"
BG_DARK = "#0E0E0E"
BG_LIGHT = "#FFFFFF"

CAP = 100.0      # cap height in drawing units
STROKE = 20.0    # Arial Rounded Bold's stem at this cap height
SKEW = -12       # degrees, italic


def letters_path(text: str, x: float, baseline: float, tracking: float) -> tuple[str, float]:
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    scale = CAP / 1491          # Arial Rounded cap height in font units
    parts, pen_x = [], x
    for ch in text:
        g = glyphs[cmap[ord(ch)]]
        pen = SVGPathPen(glyphs)
        g.draw(TransformPen(pen, (scale, 0, 0, -scale, pen_x, baseline)))
        parts.append(pen.getCommands())
        pen_x += g.width * scale + tracking
    return " ".join(parts), pen_x


def runner_m(x: float, baseline: float, colour: str, leg_colour: str) -> tuple[str, float]:
    """The M. Left stem is a trailing leg: it bends back at the knee and ends
    in a foot. Returns (svg, advance)."""
    top = baseline - CAP
    r = STROKE / 2
    # Stems at x+10 and x+90, apex dips to 68% of cap height.
    lx, rx = x + 10, x + 90
    hip = baseline - 42
    knee = (lx - 16, baseline - 6)
    toe = (lx - 38, baseline - 12)
    body = (f'<path d="M {lx} {hip} L {lx} {top + r} L {lx + 40} {baseline - 26} L {rx} {top + r} L {rx} {baseline - r}" '
            f'fill="none" stroke="{colour}" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round"/>')
    leg = (f'<path d="M {lx} {hip} L {knee[0]} {knee[1]} L {toe[0]} {toe[1]}" '
           f'fill="none" stroke="{leg_colour}" stroke-width="{STROKE}" stroke-linecap="round" stroke-linejoin="round"/>')
    return leg + body, 100 + 8


def wordmark(ink: str, accent: str) -> tuple[str, float, float]:
    """Returns (svg body, width, height) for MILEPOST with the runner M."""
    baseline = CAP + 20
    x0 = 60
    m_svg, adv = runner_m(x0, baseline, ink, accent)
    rest, end = letters_path("ILEPOST", x0 + adv + 10, baseline, tracking=-6)
    body = f'<g transform="skewX({SKEW})">{m_svg}<path d="{rest}" fill="{ink}"/></g>'
    return body, end + 30, baseline + 24


def mark(ink: str, accent: str) -> tuple[str, float, float]:
    baseline = CAP + 24
    m_svg, adv = runner_m(60, baseline, ink, accent)
    return f'<g transform="skewX({SKEW})">{m_svg}</g>', 180, baseline + 26


def svg(w: float, h: float, body: str, bg: str | None) -> str:
    rect = f'<rect width="{w}" height="{h}" fill="{bg}"/>' if bg else ""
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}">{rect}{body}</svg>\n'


def build(name: str, content: str, png_width: int) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    p = OUT / f"{name}.svg"
    p.write_text(content)
    subprocess.run(["rsvg-convert", "-w", str(png_width), str(p), "-o", str(OUT / f"{name}.png")], check=True)


def main() -> None:
    for variant, ink, bg in (("dark", "#FFFFFF", BG_DARK), ("light", "#111111", BG_LIGHT)):
        body, w, h = wordmark(ink, NAVY)
        build(f"runner-wordmark-{variant}", svg(w, h, body, bg), 2400)
        build(f"runner-wordmark-{variant}-transparent", svg(w, h, body, None), 2400)
        body, w, h = mark(ink, NAVY)
        build(f"runner-mark-{variant}", svg(w, h, body, bg), 1024)
        build(f"runner-mark-{variant}-transparent", svg(w, h, body, None), 1024)
    # All-navy versions for one-colour placements.
    body, w, h = wordmark(NAVY, NAVY)
    build("runner-wordmark-navy-transparent", svg(w, h, body, None), 2400)
    body, w, h = mark(NAVY, NAVY)
    build("runner-mark-navy-transparent", svg(w, h, body, None), 1024)

    tiles = [("runner-wordmark-dark", 1400), ("runner-wordmark-light", 1400), ("runner-mark-dark", 400), ("runner-mark-light", 400)]
    imgs = []
    for name, w in tiles:
        im = Image.open(OUT / f"{name}.png").convert("RGB")
        imgs.append(im.resize((w, round(im.height * w / im.width)), Image.LANCZOS))
    gap = 40
    rows = [imgs[0:1], imgs[1:2], imgs[2:4]]
    W = 1400 + 2 * gap
    H = gap + sum(max(i.height for i in r) + gap for r in rows)
    sheet = Image.new("RGB", (W, H), (40, 40, 40))
    y = gap
    for r in rows:
        total = sum(i.width for i in r) + gap * (len(r) - 1)
        x = (W - total) // 2
        for im in r:
            sheet.paste(im, (x, y)); x += im.width + gap
        y += max(i.height for i in r) + gap
    sheet.save(OUT / "runner-preview.png")
    print("wrote runner wordmark set")


if __name__ == "__main__":
    main()
