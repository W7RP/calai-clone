"""Draws the 1024x1024 app icon: a white flame on black.

Run from the repo root: python3 scripts/make_app_icon.py
Needs Pillow (pip install pillow).
"""
from pathlib import Path

from PIL import Image, ImageDraw

SIZE = 1024
SCALE = 4  # draw large, then downsample for smooth edges
S = SIZE * SCALE
OUT = Path("CalorieTracker/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

BACKGROUND = (0, 0, 0)
FLAME = (255, 255, 255)


def cubic(p0, p1, p2, p3, steps=64):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        u = 1 - t
        x = u**3 * p0[0] + 3 * u**2 * t * p1[0] + 3 * u * t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u**2 * t * p1[1] + 3 * u * t**2 * p2[1] + t**3 * p3[1]
        pts.append((x * S, y * S))
    return pts


def path(start, *segments, scale=0.9):
    # Shrink toward the centre so the flame sits inside the rounded-corner mask with some air.
    def fit(p):
        return tuple(0.5 + (v - 0.5) * scale for v in p)

    pts, cur = [], fit(start)
    for c1, c2, end in segments:
        pts += cubic(cur, fit(c1), fit(c2), fit(end))
        cur = fit(end)
    return pts


outer = path(
    (0.50, 0.84),
    ((0.32, 0.84), (0.22, 0.71), (0.22, 0.57)),
    ((0.22, 0.45), (0.29, 0.37), (0.34, 0.30)),
    ((0.36, 0.38), (0.39, 0.42), (0.43, 0.43)),
    ((0.41, 0.31), (0.46, 0.20), (0.57, 0.12)),
    ((0.56, 0.24), (0.78, 0.36), (0.78, 0.57)),
    ((0.78, 0.71), (0.68, 0.84), (0.50, 0.84)),
)
inner = path(
    (0.50, 0.79),
    ((0.42, 0.79), (0.38, 0.73), (0.38, 0.67)),
    ((0.38, 0.59), (0.45, 0.53), (0.52, 0.43)),
    ((0.55, 0.53), (0.62, 0.59), (0.62, 0.67)),
    ((0.62, 0.73), (0.58, 0.79), (0.50, 0.79)),
)

img = Image.new("RGB", (S, S), BACKGROUND)
draw = ImageDraw.Draw(img)
draw.polygon(outer, fill=FLAME)
draw.polygon(inner, fill=BACKGROUND)

OUT.parent.mkdir(parents=True, exist_ok=True)
img.resize((SIZE, SIZE), Image.LANCZOS).save(OUT, optimize=True)
print(f"wrote {OUT}")
