#!/usr/bin/env python3
"""App Store art for Milepost's holiday in-app events (2026-10-22): the
day's bands from holidays.json `icon_bands`, the MILEPOST wordmark in white
with a soft shadow, and the day's line under it.

  card     3840x2160  (event card; Apple lays the event name over the lower
                       third, so the words sit above it)
  details  2160x3840  (event details page)
  header   3840x1646  (product page header while the theme is on; words in
                       the centre 60% x 70%, where Apple never crops)

    ~/.venvs/spendcap/bin/python scripts/holiday_event_art.py OUT_DIR [--id thanksgiving]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
HOLIDAYS = ROOT / "Milepost" / "Resources" / "holidays.json"
WORDMARK_SVG = ROOT / "marketing" / "logo" / "runner-wordmark-dark-transparent.svg"
FONT = "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf"

SIZES = {"card": (3840, 2160), "details": (2160, 3840), "header": (3840, 1646)}
# Where the words' centre sits, as a fraction of the height, and how wide the
# wordmark is, as a fraction of the width.
LAYOUT = {"card": (0.36, 0.46), "details": (0.34, 0.72), "header": (0.47, 0.40)}


def rgb(hex_: str) -> tuple[int, int, int]:
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def wordmark(width: int) -> Image.Image:
    svg = WORDMARK_SVG.read_text().replace("#3D6BE0", "#FFFFFF")
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "w.svg", Path(tmp) / "w.png"
        src.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(width), str(src), "-o", str(out)], check=True)
        return Image.open(out).convert("RGBA")


def shadowed(img: Image.Image, canvas: Image.Image, xy: tuple[int, int], blur: float) -> None:
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.putalpha(img.getchannel("A").point(lambda a: int(a * 0.4)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.alpha_composite(shadow, (xy[0], xy[1] + round(blur * 0.6)))
    canvas.alpha_composite(img, xy)


def spaced_text(text: str, size: int, tracking: float) -> Image.Image:
    font = ImageFont.truetype(FONT, size)
    widths = [font.getbbox(ch)[2] - font.getbbox(ch)[0] if ch != " " else size * 0.32 for ch in text]
    total = int(sum(widths) + tracking * (len(text) - 1)) + size
    img = Image.new("RGBA", (total, int(size * 1.4)), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    x = size // 2
    for ch, w in zip(text, widths):
        d.text((x, size * 0.1), ch, font=font, fill=(255, 255, 255, 255))
        x += w + tracking
    return img.crop(img.getbbox())


def art(h: dict, kind: str) -> Image.Image:
    w, ht = SIZES[kind]
    img = Image.new("RGBA", (w, ht))
    draw = ImageDraw.Draw(img)
    bands = h["icon_bands"]
    total = sum(x for _, x in bands)
    y = 0.0
    for colour, weight in bands:
        y2 = y + ht * weight / total
        draw.rectangle((0, round(y), w, round(y2)), fill=rgb(colour))
        y = y2
    centre, frac = LAYOUT[kind]
    wm = wordmark(round(w * frac))
    line = spaced_text(h["line"], round(wm.height * 0.30), wm.height * 0.06)
    if line.width > w * 0.86:
        line = line.resize((round(w * 0.86), round(line.height * w * 0.86 / line.width)), Image.LANCZOS)
    gap = round(wm.height * 0.28)
    block = wm.height + gap + line.height
    top = round(ht * centre - block / 2)
    shadowed(wm, img, ((w - wm.width) // 2, top), wm.height * 0.06)
    shadowed(line, img, ((w - line.width) // 2, top + wm.height + gap), line.height * 0.12)
    return img.convert("RGB")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--id")
    ap.add_argument("--year", default="")
    args = ap.parse_args()
    for h in json.loads(HOLIDAYS.read_text())["holidays"]:
        if args.id and h["id"] != args.id:
            continue
        d = args.out / args.year / h["id"] if args.year else args.out / h["id"]
        d.mkdir(parents=True, exist_ok=True)
        for kind, (w, ht) in SIZES.items():
            art(h, kind).save(d / f"{kind}-{w}x{ht}.png", optimize=True)
        print("art", h["id"])


if __name__ == "__main__":
    main()
