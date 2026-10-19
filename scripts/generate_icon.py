"""Draw the YueJi app icon and the notification thumbnails.

Original artwork drawn from shapes (no downloaded assets). Run from the repo root:
    python scripts/generate_icon.py
Writes every AppIcon size (opaque RGB), the identical YueJiLogo image, the
YueJiIcon@2x/@3x fallbacks (the icon AltStore shows, read from CFBundleIconFiles)
and the four notification thumbnails.

The mark is a champagne crescent (月, "moon") holding three ledger lines (记,
"record") in a twilight sky: night blue fading into plum, with moonlight in the top
corner and a warm glow on the horizon. The app's summary cards use the same sky.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json

ROOT = Path(__file__).resolve().parents[1]
SS = 4  # supersampling factor

SKY = [(0.0, (20, 24, 62)), (0.55, (42, 38, 96)), (1.0, (96, 58, 112))]
HORIZON = (250, 170, 140)
MOONLIGHT = (130, 140, 230)
CHAMPAGNE = (255, 233, 196)
GOLD = (232, 174, 98)
HALO = (255, 205, 150)
LINE = (255, 248, 236)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical(n, stops):
    """An n x n gradient running top to bottom through (position, colour) stops."""
    img = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(img)
    for y in range(n):
        t = y / (n - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                d.line((0, y, n, y), fill=lerp(c0, c1, (t - t0) / (t1 - t0)))
                break
    return img.convert("RGBA")


def glow(n, center, radius, color, alpha):
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def sky(n):
    img = vertical(n, SKY)
    img.alpha_composite(glow(n, (n * 0.50, n * 1.02), n * 0.55, HORIZON, 120))
    img.alpha_composite(glow(n, (n * 0.85, n * 0.08), n * 0.35, MOONLIGHT, 60))
    return img


def crescent_mask(n, cx, cy, r):
    """The crescent: a disc minus an offset disc (same proportions as CrescentShape in the app)."""
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    cut = Image.new("L", (n, n), 0)
    x, y, cr = cx + 0.42 * r, cy - 0.30 * r, 0.80 * r
    ImageDraw.Draw(cut).ellipse((x - cr, y - cr, x + cr, y + cr), fill=255)
    return ImageChops.subtract(mask, cut)


def moon(img, cx, cy, r):
    """A luminous champagne crescent with its halo."""
    n = img.size[0]
    img.alpha_composite(glow(n, (cx, cy), r * 1.2, (255, 214, 160), 45))
    mask = crescent_mask(n, cx, cy, r)
    halo = Image.new("RGBA", (n, n), HALO + (0,))
    halo.putalpha(mask.filter(ImageFilter.GaussianBlur(r * 0.16)).point(lambda v: int(v * 0.45)))
    img.alpha_composite(halo)
    fill = vertical(n, [(0, CHAMPAGNE), (1, GOLD)])
    fill.putalpha(mask)
    img.alpha_composite(fill)


def ledger_lines(img, cx, cy, r):
    """Three entries in the crescent's hollow: a champagne bullet and a line each."""
    d = ImageDraw.Draw(img)
    w = r * 0.085
    x0 = cx + r * 0.16
    for i, length in enumerate((0.42, 0.34, 0.24)):
        y = cy - r * 0.48 + i * r * 0.24
        d.ellipse((x0 - w * 0.75, y - w * 0.75, x0 + w * 0.75, y + w * 0.75), fill=CHAMPAGNE + (255,))
        x1 = x0 + w * 1.6
        d.rounded_rectangle((x1, y - w / 2, x1 + r * length, y + w / 2), radius=w / 2, fill=LINE + (240 - 30 * i,))


def mark(img, cx, cy, r):
    moon(img, cx, cy, r)
    ledger_lines(img, cx, cy, r)


def icon(size=1024):
    n = size * SS
    img = sky(n)
    mark(img, n * 0.46, n * 0.53, n * 0.31)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


# Notification thumbnails: the icon's sky with one champagne glyph, so every message
# looks like it comes from the same app. Each matches a kind sent by LedgerNotifications.

def champagne_layer(n, mask):
    fill = vertical(n, [(0, CHAMPAGNE), (1, GOLD)])
    fill.putalpha(mask)
    return fill


def thumbnail_recorded(n):
    img = sky(n)
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    w = int(n * 0.085)
    pts = [(n * 0.29, n * 0.52), (n * 0.44, n * 0.67), (n * 0.72, n * 0.37)]
    d.line(pts, fill=255, width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=255)
    img.alpha_composite(glow(n, (n * 0.5, n * 0.52), n * 0.30, (255, 214, 160), 40))
    img.alpha_composite(champagne_layer(n, mask))
    return img


def thumbnail_review(n):
    img = sky(n)
    mask = Image.new("L", (n, n), 0)
    d = ImageDraw.Draw(mask)
    w = n * 0.10
    d.rounded_rectangle((n / 2 - w / 2, n * 0.24, n / 2 + w / 2, n * 0.58), radius=w / 2, fill=255)
    d.ellipse((n / 2 - w * 0.62, n * 0.66, n / 2 + w * 0.62, n * 0.66 + w * 1.24), fill=255)
    img.alpha_composite(glow(n, (n * 0.5, n * 0.5), n * 0.30, (255, 214, 160), 40))
    img.alpha_composite(champagne_layer(n, mask))
    return img


def thumbnail_reminder(n):
    img = sky(n)
    mark(img, n * 0.46, n * 0.53, n * 0.31)
    return img


def thumbnail_budget(n):
    img = sky(n)
    d = ImageDraw.Draw(img)
    w = int(n * 0.075)
    box = (n * 0.22, n * 0.30, n * 0.78, n * 0.86)
    d.arc(box, 180, 360, fill=(255, 255, 255, 70), width=w)
    arc = Image.new("L", (n, n), 0)
    ImageDraw.Draw(arc).arc(box, 180, 318, fill=255, width=w)
    img.alpha_composite(champagne_layer(n, arc))
    cx, cy = n * 0.50, n * 0.58
    d = ImageDraw.Draw(img)
    d.line((cx, cy, n * 0.66, n * 0.43), fill=CHAMPAGNE + (255,), width=int(w * 0.6))
    d.ellipse((cx - w * 0.75, cy - w * 0.75, cx + w * 0.75, cy + w * 0.75), fill=CHAMPAGNE + (255,))
    return img


THUMBNAILS = {"Recorded": thumbnail_recorded, "Review": thumbnail_review,
              "Reminder": thumbnail_reminder, "Budget": thumbnail_budget}


def render(painter, size=300):
    return painter(size * SS).convert("RGB").resize((size, size), Image.LANCZOS)


def main():
    master = icon(1024)
    icons = ROOT / "YueJi/Assets.xcassets/AppIcon.appiconset"
    for entry in json.loads((icons / "Contents.json").read_text())["images"]:
        px = round(float(entry["size"].split("x")[0]) * int(entry["scale"][0]))
        out = master if px == 1024 else master.resize((px, px), Image.LANCZOS)
        out.save(icons / entry["filename"], optimize=True)
    # The opening logo must be byte-identical to the 1024 icon.
    (ROOT / "YueJi/Assets.xcassets/YueJiLogo.imageset/YueJiLogo.png").write_bytes((icons / "Icon.png").read_bytes())
    for scale in (2, 3):
        master.resize((60 * scale, 60 * scale), Image.LANCZOS).save(ROOT / f"YueJi/YueJiIcon@{scale}x.png", optimize=True)
    for name, painter in THUMBNAILS.items():
        render(painter).save(ROOT / f"YueJi/YueJiNotice{name}.png", optimize=True)
    print("Wrote app icons, logo, IPA/AltStore fallbacks and notification thumbnails.")


if __name__ == "__main__":
    main()
