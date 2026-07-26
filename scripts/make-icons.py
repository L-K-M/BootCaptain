#!/usr/bin/env python3
"""Generate the macOS AppIcon asset catalog from media-sources/icon.png.

macOS app icons supply their own shape: Apple's template is a rounded
rectangle occupying ~80% of the canvas with transparent margins. This script
squares the source, masks it to the macOS rounded-rect, adds the margin, and
emits every size slot of an AppIcon.appiconset.

Usage: python3 scripts/make-icons.py
Requires: Pillow
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "media-sources", "icon.png")
OUT = os.path.join(ROOT, "App", "Assets.xcassets", "AppIcon.appiconset")

# (points, scale) slots required for a macOS AppIcon set.
SLOTS = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (512, 1), (512, 2)]

CANVAS = 1024          # master canvas, px
CONTENT = 824          # Apple template: icon grid is 824 px on a 1024 canvas
RADIUS = 185.4         # Apple template corner radius at 1024 px


def build_master(src_path: str) -> Image.Image:
    src = Image.open(src_path).convert("RGBA")
    # Square-crop around the center, then fit to the content size.
    side = min(src.size)
    left = (src.width - side) // 2
    top = (src.height - side) // 2
    src = src.crop((left, top, left + side, top + side)).resize(
        (CONTENT, CONTENT), Image.LANCZOS
    )

    # Rounded-rect alpha mask (4x supersampled for clean corners).
    ss = 4
    mask = Image.new("L", (CONTENT * ss, CONTENT * ss), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, CONTENT * ss - 1, CONTENT * ss - 1),
        radius=RADIUS * (CONTENT / CANVAS) * ss,
        fill=255,
    )
    mask = mask.resize((CONTENT, CONTENT), Image.LANCZOS)
    src.putalpha(mask)

    master = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    margin = (CANVAS - CONTENT) // 2
    master.paste(src, (margin, margin), src)
    return master


def main() -> int:
    if not os.path.exists(SOURCE):
        print(f"source icon not found: {SOURCE}", file=sys.stderr)
        return 1
    os.makedirs(OUT, exist_ok=True)
    master = build_master(SOURCE)

    images = []
    for points, scale in SLOTS:
        px = points * scale
        name = f"icon_{points}x{points}{'@2x' if scale == 2 else ''}.png"
        master.resize((px, px), Image.LANCZOS).save(os.path.join(OUT, name))
        images.append(
            {
                "filename": name,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{points}x{points}",
            }
        )

    contents = {"images": images, "info": {"author": "xcode", "version": 1}}
    with open(os.path.join(OUT, "Contents.json"), "w") as fh:
        json.dump(contents, fh, indent=2)
        fh.write("\n")
    print(f"wrote {len(images)} icons to {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
