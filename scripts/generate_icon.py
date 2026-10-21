"""Draw the YueJi app icon and the notification thumbnails.

Original artwork drawn from shapes (no downloaded assets); needs Pillow and NumPy. Run
from the repo root:
    python scripts/generate_icon.py
Writes the single-size AppIcon set with Apple's three home-screen appearances (default,
dark and tinted, opaque RGB, 1024 px; Xcode derives every smaller size), the identical
YueJiLogo image, the YueJiIcon@2x/@3x fallbacks (the icon AltStore shows, read from
CFBundleIconFiles) and the four notification thumbnails.

The layout follows Apple's App Icon Template for iOS, iPadOS and watchOS 27: a full-bleed
1024 px square that the system masks (no corners or outer shadow baked in), one idea
centred on the template grid (eight 128 px steps; circles of 820, 512 and 204 px), built
from the template's layers, back to front:

    BG       Apple-blue gradient, the app tint (#0088FF), lighter at the top
    Layer 1  the moon (月): a 737 px frosted Liquid Glass disc inside the 820 px circle
    Layer 2  the ledger (记): three white entries on the glass
    Layer 3  the lit crescent of the moon, in gold, with rounded horns

The AppIcon set holds flattened images, which the system doesn't light the way it lights
a layered Icon Composer icon, so the glass edges and soft layer shadows are drawn here,
kept thin and crisp. Every shape is an exact signed distance, so edges are anti-aliased
at any size. Dark keeps the layers on graphite with the glass in the app blue; tinted is
grayscale on black with the crescent and entries in white, which the system recolours
with the user's tint, like Apple's own icons.
"""
from pathlib import Path
import json
import math

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[1]

# Apple blue, matching the app tint (iOS 27 system blue #0088FF), lighter at the top.
BLUE_TOP = (52, 170, 255)
BLUE_BOTTOM = (0, 100, 226)
APP_BLUE = (0, 136, 255)
SHEEN = (176, 222, 255)
FROST = (200, 230, 255)
GOLD_TOP = (255, 232, 170)
GOLD_BOTTOM = (238, 168, 74)
GRAPHITE_TOP = (40, 42, 52)
GRAPHITE_BOTTOM = (10, 10, 14)
SHADOW = (6, 26, 80)
WHITE = (255, 255, 255)
BLACK = (0, 0, 0)
LIGHT = (-0.5, -0.866)  # towards the light: from above, a little to the left

# The mark on the template grid, as fractions of the canvas (the crescent's as fractions
# of the moon's radius).
MOON_R = 0.36
CUT_R, CUT_OFFSET, CUT_ANGLE = 0.98, 0.45, 38  # the dark side: up and to the right
HORN_ROUNDING = 0.012
ENTRY_Y, ENTRY_STEP, ENTRY_WIDTH, ENTRY_GAP = 0.465, 0.11, 0.052, 0.06
ENTRY_LENGTHS = (0.34, 0.27, 0.20)
GLASS = {"default": (FROST, 0.28), "dark": (APP_BLUE, 0.62), "tinted": (WHITE, 0.24)}


class Canvas:
    """An n x n float RGB image with pixel-centre coordinates, painted back to front."""

    def __init__(self, n, top, bottom):
        self.n = n
        self.y, self.x = np.mgrid[0:n, 0:n].astype(np.float32) + 0.5
        self.rgb = self.gradient(top, bottom, 0, n)

    def gradient(self, top, bottom, y0, y1):
        t = np.clip((self.y - y0) / (y1 - y0), 0, 1)[..., None]
        return np.asarray(top, np.float32) * (1 - t) + np.asarray(bottom, np.float32) * t

    def paint(self, color, alpha):
        """Composite a colour, or an image the size of the canvas, with per-pixel alpha."""
        a = np.clip(alpha, 0, 1)[..., None]
        self.rgb = self.rgb * (1 - a) + np.asarray(color, np.float32) * a

    def blurred(self, radius):
        return np.asarray(self.image().filter(ImageFilter.GaussianBlur(radius)), np.float32)

    def image(self):
        return Image.fromarray(np.clip(self.rgb + 0.5, 0, 255).astype(np.uint8))


# Shapes, as signed distances in pixels (negative inside).

def circle(c, cx, cy, r):
    return np.hypot(c.x - cx, c.y - cy) - r


def crescent(c, cx, cy, r, cut, offset, angle, rounding):
    """A disc minus a disc of radius `cut` whose centre is `offset` away towards `angle`
    (degrees, anticlockwise from the right). Exact distance (after Inigo Quilez's sdMoon),
    so growing it by `rounding` rounds the horns cleanly."""
    r, cut = r - rounding, cut + rounding
    t = math.radians(angle)
    ux, uy = math.cos(t), -math.sin(t)
    dx, dy = c.x - cx, c.y - cy
    px, py = dx * ux + dy * uy, np.abs(dy * ux - dx * uy)
    a = (r * r - cut * cut + offset * offset) / (2 * offset)
    b = math.sqrt(max(r * r - a * a, 0.0))
    horn = offset * (px * b - py * a) > offset * offset * np.maximum(b - py, 0)
    body = np.maximum(np.hypot(px, py) - r, cut - np.hypot(px - offset, py))
    return np.where(horn, np.hypot(px - a, py - b), body) - rounding


def segment(c, ax, ay, bx, by, r):
    """A stroke from a to b with round caps."""
    px, py, vx, vy = c.x - ax, c.y - ay, bx - ax, by - ay
    h = np.clip((px * vx + py * vy) / (vx * vx + vy * vy), 0, 1)
    return np.hypot(px - vx * h, py - vy * h) - r


def arc(c, cx, cy, r, start, end, w):
    """A stroke along a circle between two angles (degrees, anticlockwise from the right)."""
    angle = np.degrees(np.arctan2(cy - c.y, c.x - cx))
    ring = np.abs(np.hypot(c.x - cx, c.y - cy) - r) - w
    caps = [np.hypot(c.x - cx - r * math.cos(math.radians(a)), c.y - cy + r * math.sin(math.radians(a))) - w
            for a in (start, end)]
    inside = (angle >= min(start, end)) & (angle <= max(start, end))
    return np.where(inside, ring, np.minimum(*caps))


def coverage(sdf):
    """Anti-aliased fill: one pixel of ramp across the edge."""
    return np.clip(0.5 - sdf, 0, 1)


# Layers.

def shadow(c, cover, radius, dx, dy, alpha, color):
    """A soft drop shadow: the shape blurred and moved down (and right)."""
    soft = Image.fromarray(np.clip(cover * 255 + 0.5, 0, 255).astype(np.uint8))
    soft = np.asarray(soft.filter(ImageFilter.GaussianBlur(radius)), np.float32) / 255
    dx, dy = int(round(dx)), int(round(dy))
    moved = np.zeros_like(soft)
    moved[dy:, dx:] = soft[:c.n - dy, :c.n - dx]
    c.paint(color, moved * alpha)


def edge_light(c, sdf, width, strength, back=0.4):
    """Liquid Glass edges: a thin specular rim where the edge faces the light, fainter opposite."""
    gy, gx = np.gradient(sdf)
    facing = (gx * LIGHT[0] + gy * LIGHT[1]) / (np.hypot(gx, gy) + 1e-6)
    rim = np.clip(1 + sdf / width, 0, 1) ** 2 * coverage(sdf)
    c.paint(WHITE, rim * strength * (np.clip(facing, 0, 1) ** 1.5 + back * np.clip(-facing, 0, 1) ** 1.5))


def glass(c, sdf, mode, ink, top_light=0.12):
    """A frosted Liquid Glass shape: soft shadow, the background seen through it, a light
    from above fading towards the middle, and bright edges."""
    n = c.n
    tint, alpha = GLASS[mode]
    cover = coverage(sdf)
    behind = c.blurred(n * 0.03)  # the glass shows the background, not its own shadow
    shadow(c, cover, n * 0.03, 0, n * 0.022, 0.30 if mode == "default" else 0.55, ink)
    c.paint(behind * (1 - alpha) + np.asarray(tint, np.float32) * alpha, cover)
    rows = np.nonzero(cover.max(axis=1))[0]
    fade = np.clip(1 - (c.y - rows[0]) / (0.55 * (rows[-1] - rows[0])), 0, 1) ** 1.6
    c.paint(WHITE, cover * top_light * fade)
    edge_light(c, sdf, n * 0.012, 0.85 if mode == "default" else 0.6)


def solid(c, sdf, color, ink, alpha=0.96):
    """A flat foreground shape lifted by a small shadow."""
    cover = coverage(sdf)
    shadow(c, cover, c.n * 0.008, 0, c.n * 0.006, 0.18, ink)
    c.paint(color, cover * alpha)


def background(n, mode="default"):
    if mode == "tinted":
        return Canvas(n, BLACK, BLACK)
    dark = mode == "dark"
    c = Canvas(n, *((GRAPHITE_TOP, GRAPHITE_BOTTOM) if dark else (BLUE_TOP, BLUE_BOTTOM)))
    sheen = np.exp(-((c.x - n * 0.30) ** 2 + (c.y - n * 0.05) ** 2) / (2 * (n * 0.42) ** 2))
    c.paint(BLUE_TOP if dark else SHEEN, sheen * (40 if dark else 70) / 255)
    return c


def icon(size=1024, mode="default"):
    """The icon in one of Apple's home-screen appearances: default, dark or tinted."""
    n = size
    c = background(n, mode)
    ink = SHADOW if mode == "default" else BLACK
    cx = cy = n / 2
    r = n * MOON_R
    cut, offset, t = r * CUT_R, r * CUT_OFFSET, math.radians(CUT_ANGLE)
    ccx, ccy = cx + offset * math.cos(t), cy - offset * math.sin(t)

    # Layer 1: the moon, a frosted glass disc.
    glass(c, circle(c, cx, cy, r), mode, ink)

    # Layer 2: the ledger, three entries left-aligned just clear of the crescent.
    w = n * ENTRY_WIDTH
    ys = [n * (ENTRY_Y + (i - 1) * ENTRY_STEP) for i in range(3)]
    x0 = max(ccx - math.sqrt(max(0.0, cut * cut - (y - ccy) ** 2)) for y in ys) + n * ENTRY_GAP + w / 2
    entries = np.min([segment(c, x0, y, x0 + n * length - w, y, w / 2) for y, length in zip(ys, ENTRY_LENGTHS)], axis=0)
    solid(c, entries, WHITE, ink)

    # Layer 3: the lit crescent.
    moon = crescent(c, cx, cy, r, cut, offset, CUT_ANGLE, n * HORN_ROUNDING)
    cover = coverage(moon)
    shadow(c, cover, n * 0.018, n * 0.010, n * 0.018, 0.35, ink)
    top, bottom = (WHITE, (210, 210, 210)) if mode == "tinted" else (GOLD_TOP, GOLD_BOTTOM)
    c.paint(c.gradient(top, bottom, cy - r, cy + r), cover)
    edge_light(c, moon, n * 0.012, 1.0, back=0.3)

    out = c.image()
    # Tinted icons are grayscale: the system maps their brightness to the user's tint.
    return out.convert("L").convert("RGB") if mode == "tinted" else out


# Notification thumbnails: the icon's blue background and glass moon carrying one white
# glyph, so every message looks like it comes from the same app.

def thumbnail_base(n):
    c = background(n)
    glass(c, circle(c, n / 2, n / 2, n * 0.34), "default", SHADOW)
    return c


def thumbnail_recorded(n):
    c = thumbnail_base(n)
    w = n * 0.036
    a, b, d = (n * 0.385, n * 0.515), (n * 0.465, n * 0.595), (n * 0.625, n * 0.425)
    solid(c, np.minimum(segment(c, *a, *b, w), segment(c, *b, *d, w)), WHITE, SHADOW)
    return c.image()


def thumbnail_review(n):
    c = thumbnail_base(n)
    w = n * 0.040
    solid(c, np.minimum(segment(c, n / 2, n * 0.355, n / 2, n * 0.53, w), circle(c, n / 2, n * 0.625, w * 1.15)),
          WHITE, SHADOW)
    return c.image()


def thumbnail_reminder(n):
    return icon(n)


def thumbnail_budget(n):
    c = thumbnail_base(n)
    cx, cy, r, w = n / 2, n * 0.56, n * 0.17, n * 0.032
    c.paint(WHITE, coverage(arc(c, cx, cy, r, 0, 180, w)) * 0.35)
    solid(c, arc(c, cx, cy, r, 180, 40, w), (255, 214, 120), SHADOW, alpha=1.0)
    t = math.radians(40)
    needle = segment(c, cx, cy, cx + n * 0.115 * math.cos(t), cy - n * 0.115 * math.sin(t), w * 0.55)
    solid(c, np.minimum(needle, circle(c, cx, cy, w * 1.05)), WHITE, SHADOW)
    return c.image()


THUMBNAILS = {"Recorded": thumbnail_recorded, "Review": thumbnail_review,
              "Reminder": thumbnail_reminder, "Budget": thumbnail_budget}

APPEARANCES = {"default": ("Icon.png", None), "dark": ("Icon-dark.png", "dark"), "tinted": ("Icon-tinted.png", "tinted")}


def main():
    master = icon(1024)
    icons = ROOT / "YueJi/Assets.xcassets/AppIcon.appiconset"
    images = []
    for mode, (filename, appearance) in APPEARANCES.items():
        (master if mode == "default" else icon(1024, mode)).save(icons / filename, optimize=True)
        entry = {"filename": filename, "idiom": "universal", "platform": "ios", "size": "1024x1024"}
        if appearance:
            entry = {"appearances": [{"appearance": "luminosity", "value": appearance}], **entry}
        images.append(entry)
    (icons / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    # The opening logo must be byte-identical to the 1024 icon.
    (ROOT / "YueJi/Assets.xcassets/YueJiLogo.imageset/YueJiLogo.png").write_bytes((icons / "Icon.png").read_bytes())
    for scale in (2, 3):
        master.resize((60 * scale, 60 * scale), Image.LANCZOS).save(ROOT / f"YueJi/YueJiIcon@{scale}x.png", optimize=True)
    for name, painter in THUMBNAILS.items():
        painter(300).save(ROOT / f"YueJi/YueJiNotice{name}.png", optimize=True)
    print("Wrote app icons, logo, IPA/AltStore fallbacks and notification thumbnails.")


if __name__ == "__main__":
    main()
