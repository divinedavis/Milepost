#!/usr/bin/env python3
"""Compose the Apple Watch App Store screenshots from the raw watch captures.

Input:  marketing/asc-watch-screenshots/*.png — raw 368x448 captures from the
        Apple Watch SE 3 (44mm) simulator (see CLAUDE.md, "App Store submission").
Output: marketing/asc-watch-screenshots-navy/{1..3}.png at 368x448, the only
        size the APP_WATCH_SERIES_4 slot takes.

Why composed: iMessage's App Store link preview shows the FIRST WATCH
screenshot, not the iPhone one. A bare black watch screen read as a broken
preview, so the watch panels get the iPhone panels' navy field, wordmark and
headline. Drawn at 4x and downscaled so the small text stays crisp.

    ~/.venvs/spendcap/bin/python scripts/make_watch_screenshots.py
"""
from __future__ import annotations

import pathlib
import shutil
import sys

from PIL import Image, ImageDraw

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from asc_make_screenshots import NAVY, WHITE, WORDMARK, font  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
RAW_DIR = ROOT / "marketing" / "asc-watch-screenshots"
OUT_DIR = ROOT / "marketing" / "asc-watch-screenshots-navy"
SIZE = (368, 448)
SS = 4  # supersample

# (raw capture, headline) — order is the App Store order; 1 is the preview.
PANELS = [
    ("1-recording", "your run,\non your wrist."),
    ("3-summary",   "saved to\nyour phone."),
    ("2-controls",  "pause with\none tap."),
]


def composite(raw: Image.Image, headline: str, out: pathlib.Path) -> None:
    W, H = SIZE[0] * SS, SIZE[1] * SS
    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)

    wm = Image.open(WORDMARK).convert("RGBA")
    wm_w = 96 * SS
    wm = wm.resize((wm_w, int(wm.height * wm_w / wm.width)), Image.LANCZOS)
    x = 22 * SS
    canvas.paste(wm, (x, 20 * SS), wm)

    f = font(31 * SS)
    y = 20 * SS + wm.height + 8 * SS
    for line in headline.split("\n"):
        draw.text((x, y), line, fill=WHITE, font=f)
        y = draw.textbbox((x, y), line, font=f)[3] + 3 * SS

    # Watch: dark case with the screen inset, centred under the headline.
    screen_w = 222 * SS
    screen_h = int(raw.height * screen_w / raw.width)
    bezel = 9 * SS
    fw, fh = screen_w + 2 * bezel, screen_h + 2 * bezel
    frame = Image.new("RGBA", (fw, fh), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, fw, fh), radius=52 * SS, fill=(24, 24, 24))
    screen = raw.resize((screen_w, screen_h), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", (screen_w, screen_h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, screen_w, screen_h), radius=44 * SS, fill=255)
    screen.putalpha(mask)
    frame.paste(screen, (bezel, bezel), screen)
    top = max(y + 12 * SS, H - fh - 14 * SS)
    canvas.paste(frame, ((W - fw) // 2, top), frame)

    canvas.resize(SIZE, Image.LANCZOS).save(out, format="PNG", optimize=True)


def main() -> int:
    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True)
    for i, (key, headline) in enumerate(PANELS, start=1):
        out = OUT_DIR / f"{i}.png"
        composite(Image.open(RAW_DIR / f"{key}.png").convert("RGB"), headline, out)
        print(f"  ✓ {out.name}  ← {key}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
