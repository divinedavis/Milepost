#!/usr/bin/env python3
"""Holiday app icons: the day's colours in horizontal bands behind the
runner-M, at the everyday icon's size (same rule as Marracat's, owner
2026-10-20). Bands come from holidays.json `icon_bands` ([colour, weight]).
The whole mark is white with a soft shadow.

    ~/.venvs/spendcap/bin/python scripts/holiday_icons.py --out DIR [--size 360]
    ~/.venvs/spendcap/bin/python scripts/holiday_icons.py --xcassets   # AppIcon-<id> alternates
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
HOLIDAYS = ROOT / "Milepost" / "Resources" / "holidays.json"
ASSETS = ROOT / "Milepost" / "Resources" / "Assets.xcassets"
MARK_SVG = ROOT / "marketing" / "logo" / "runner-mark-dark-transparent.svg"


def rgb(hex_: str) -> tuple[int, int, int]:
    h = hex_.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def distance(a, b) -> float:
    return sum((x - y) ** 2 for x, y in zip(a, b)) ** 0.5


def mark(width: int, leg: str) -> Image.Image:
    svg = MARK_SVG.read_text().replace("#3D6BE0", leg)
    with tempfile.TemporaryDirectory() as tmp:
        src, out = Path(tmp) / "m.svg", Path(tmp) / "m.png"
        src.write_text(svg)
        subprocess.run(["rsvg-convert", "-w", str(width), str(src), "-o", str(out)], check=True)
        return Image.open(out).convert("RGBA")


def icon(h: dict, size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(img)
    bands = h["icon_bands"]
    total = sum(w for _, w in bands)
    y = 0.0
    for colour, weight in bands:
        y2 = y + size * weight / total
        draw.rectangle((0, round(y), size, round(y2)), fill=rgb(colour))
        y = y2
    # All white, like Marracat's holiday icons: a coloured leg vanished into
    # bands of its own colour. A soft shadow keeps it off white flag stripes.
    m = mark(round(size * 0.80), "#FFFFFF")
    x, y0 = (size - m.width) // 2, (size - m.height) // 2 - round(size * 0.02)
    shadow = Image.new("RGBA", m.size, (0, 0, 0, 0))
    shadow.putalpha(m.getchannel("A").point(lambda a: int(a * 0.45)))
    shadow = shadow.filter(ImageFilter.GaussianBlur(size * 0.018))
    img.alpha_composite(shadow, (x, y0 + round(size * 0.012)))
    img.alpha_composite(m, (x, y0))
    return img.convert("RGB")


def rounded(img: Image.Image) -> Image.Image:
    s = img.width
    mask = Image.new("L", (s, s), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, s - 1, s - 1), radius=round(s * 0.2237), fill=255)
    out = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    out.paste(img, mask=mask)
    return out


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path)
    ap.add_argument("--size", type=int, default=360)
    ap.add_argument("--xcassets", action="store_true")
    args = ap.parse_args()
    holidays = json.loads(HOLIDAYS.read_text())["holidays"]
    for h in holidays:
        big = icon(h)
        if args.out:
            args.out.mkdir(parents=True, exist_ok=True)
            rounded(big.resize((args.size, args.size), Image.LANCZOS)).save(args.out / f"{h['id']}.png", optimize=True)
        if args.xcassets:
            folder = ASSETS / f"{h['icon']}.appiconset"
            folder.mkdir(parents=True, exist_ok=True)
            big.save(folder / "icon-1024.png")
            (folder / "Contents.json").write_text(json.dumps({
                "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
                "info": {"author": "xcode", "version": 1}}, indent=2))
    print(f"{len(holidays)} holiday icons")


if __name__ == "__main__":
    main()
