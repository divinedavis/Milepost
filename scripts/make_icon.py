#!/usr/bin/env python3
"""Draw the Milepost app icon: near-black field with the runner-M mark.
Depends on marketing/logo/runner-mark-dark-transparent.svg from
make_wordmark.py.

    ~/.venvs/spendcap/bin/python scripts/make_icon.py
"""
from __future__ import annotations

import subprocess
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Milepost" / "Resources" / "Assets.xcassets"
ICONSET = ASSETS / "AppIcon.appiconset"
MARK_SVG = ROOT / "marketing" / "logo" / "runner-mark-dark-transparent.svg"
WORDMARK_SVG = ROOT / "marketing" / "logo" / "runner-wordmark-dark-transparent.svg"
MARKETING = ROOT / "marketing"

FIELD = (0x0E, 0x0E, 0x0E)
FIELD_DEEP = (0x05, 0x05, 0x05)


def render_svg(svg: Path, width: int) -> Image.Image:
    out = ROOT / "build" / f"{svg.stem}-{width}.png"
    out.parent.mkdir(exist_ok=True)
    subprocess.run(["rsvg-convert", "-w", str(width), str(svg), "-o", str(out)], check=True)
    return Image.open(out).convert("RGBA")


def field(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), FIELD)
    px = img.load()
    for y in range(size):
        t = y / (size - 1)
        row = tuple(round(FIELD[i] + (FIELD_DEEP[i] - FIELD[i]) * t) for i in range(3))
        for x in range(size):
            px[x, y] = row
    return img


def icon(size: int = 1024) -> Image.Image:
    img = field(size).convert("RGBA")
    mark = render_svg(MARK_SVG, round(size * 0.80))
    x = (size - mark.width) // 2
    y = (size - mark.height) // 2 - round(size * 0.02)
    img.alpha_composite(mark, (x, y))
    return img.convert("RGB")


def image_set(name: str, svg: Path, base_height: int) -> None:
    """A 1x/2x/3x PNG image set sized by height."""
    folder = ASSETS / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    probe = render_svg(svg, 1000)
    ratio = probe.width / probe.height
    images = []
    for scale in (1, 2, 3):
        h = base_height * scale
        im = render_svg(svg, round(h * ratio))
        fname = f"{name}@{scale}x.png"
        im.save(folder / fname)
        images.append({"filename": fname, "idiom": "universal", "scale": f"{scale}x"})
    import json
    (folder / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2))


def main() -> None:
    ICONSET.mkdir(parents=True, exist_ok=True)
    MARKETING.mkdir(parents=True, exist_ok=True)
    im = icon()
    im.save(ICONSET / "icon-1024.png")
    mask = Image.new("L", (1024, 1024), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1023, 1023), radius=229, fill=255)
    rounded = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    rounded.paste(im, mask=mask)
    rounded.save(MARKETING / "icon-rounded.png")
    image_set("LaunchLogo", MARK_SVG, 120)
    image_set("Wordmark", WORDMARK_SVG, 22)
    print("wrote icon, LaunchLogo and Wordmark image sets")


if __name__ == "__main__":
    main()
