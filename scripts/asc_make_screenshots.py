#!/usr/bin/env python3
"""Compose the App Store screenshots from the UI-test captures.

Input:  build.nosync/screenshots-raw/*.png — the PNGs the XCUITests write when
        TEST_RUNNER_MILEPOST_SHOTS points at a directory (run on an iPhone 17
        Pro Max, 1320x2868, with TEST_RUNNER_MILEPOST_LONG_RUN=1 so the run is
        long enough to show a split).
Output: build/asc-screenshots/{1..5}.png at 1290x2796, the 6.7" slot the API
        accepts (APP_IPHONE_67).

Portfolio style: five panels alternating brand colour and white, one short
lowercase headline per panel, the screen inside a rounded device frame, the
wordmark small in the corner of the accent panels. Brand orange = Theme.orange.

    ~/.venvs/spendcap/bin/python scripts/asc_make_screenshots.py
"""
from __future__ import annotations

import pathlib
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "build.nosync" / "screenshots-raw"
OUT_DIR = ROOT / "build" / "asc-screenshots"
# "dark" = white ink for dark/orange fields; "light" = dark ink for white fields.
WORDMARK = ROOT / "marketing" / "logo" / "runner-wordmark-dark-transparent.png"
WORDMARK_DARK = ROOT / "marketing" / "logo" / "runner-wordmark-light-transparent.png"
CANVAS = (1290, 2796)
ORANGE = (255, 92, 26)          # Theme.orange (1.0, 0.36, 0.10)
INK = (14, 14, 14)              # Theme.background
WHITE = (255, 255, 255)
SOFT = (110, 110, 115)

# (capture name, headline, background, subline)
PANELS = [
    ("map-route",       "press start.\nthat's it.",      ORANGE, "Your route draws in as you go, screen on or off."),
    ("route-recording", "time. pace.\ndistance. live.",  WHITE,  "Numbers you can read mid-stride, and a splits bar."),
    ("route-detail",    "every run,\nmapped.",           ORANGE, "Route, distance, pace and each split, saved on your phone."),
    ("you-totals",      "this week.\nall time.",         WHITE,  "Totals in miles or kilometres. Voice cues if you want them."),
    ("activities-list", "nothing leaves\nyour phone.",   ORANGE, "No account. No upload. No ads. Just your runs."),
]


def font(size: int, bold: bool = True) -> ImageFont.FreeTypeFont:
    for p in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/HelveticaNeue.ttc"):
        if pathlib.Path(p).exists():
            f = ImageFont.truetype(p, size=size)
            try:
                f.set_variation_by_name("Heavy" if bold else "Regular")
            except Exception:
                try:
                    f.set_variation_by_name("Bold" if bold else "Regular")
                except Exception:
                    pass
            return f
    return ImageFont.load_default()


def composite(raw: Image.Image, headline: str, subline: str, bg: tuple, out: pathlib.Path) -> None:
    canvas = Image.new("RGB", CANVAS, bg)
    draw = ImageDraw.Draw(canvas)
    ink = WHITE if bg == ORANGE else INK
    sub_ink = (255, 226, 210) if bg == ORANGE else SOFT

    # Wordmark top-left on every panel (white on orange, dark on white).
    wm = Image.open(WORDMARK if bg == ORANGE else WORDMARK_DARK).convert("RGBA")
    wm_w = 300
    wm = wm.resize((wm_w, int(wm.height * wm_w / wm.width)), Image.LANCZOS)
    canvas.paste(wm, (96, 96), wm)

    f = font(150)
    x, y = 96, 96 + wm.height + 70
    for line in headline.split("\n"):
        draw.text((x, y), line, fill=ink, font=f)
        y = draw.textbbox((x, y), line, font=f)[3] + 8
    y += 30
    draw.text((x, y), subline, fill=sub_ink, font=font(44, bold=False))
    y += 44 + 80

    # Device frame: dark rounded rect with the screen inset; bottom runs off.
    side = 130
    frame_w = CANVAS[0] - 2 * side
    bezel = 20
    screen_w = frame_w - 2 * bezel
    scale = screen_w / raw.width
    screen_h = int(raw.height * scale)
    frame_h = screen_h + 2 * bezel
    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame_w, frame_h), radius=120,
                                            fill=(30, 30, 30) if bg == ORANGE else INK)
    screen = raw.resize((screen_w, screen_h), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_w, screen_h), radius=100, fill=255)
    screen.putalpha(mask)
    frame.paste(screen, (bezel, bezel), screen)
    canvas.paste(frame, (side, y), frame)
    canvas.save(out, format="PNG", optimize=True)


def main() -> int:
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True)
    made = 0
    for i, (key, headline, bg, subline) in enumerate(PANELS, start=1):
        src = RAW_DIR / f"{key}.png"
        if not src.exists():
            print(f"  ! no capture {src.name}; skipping panel {i}")
            continue
        out = OUT_DIR / f"{i}.png"
        composite(Image.open(src).convert("RGB"), headline, subline, bg, out)
        print(f"  ✓ {out.name}  ← {key}")
        made += 1
    print(f"{made} panel(s) in {OUT_DIR}")
    return 0 if made == len(PANELS) else 1


if __name__ == "__main__":
    sys.exit(main())
