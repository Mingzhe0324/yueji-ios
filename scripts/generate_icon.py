"""Draw the YueJi app icon and the notification thumbnails.

Original artwork drawn from shapes (no downloaded assets). Run from the repo root:
    python scripts/generate_icon.py
Writes every AppIcon size (opaque RGB), the identical YueJiLogo image, the
YueJiIcon@2x/@3x fallbacks (the icon AltStore shows, read from CFBundleIconFiles)
and the four notification thumbnails.

The mark is a champagne crescent (月, "moon") holding three ledger lines (记,
"record") on deep navy, with a soft warm glow: the same palette as the app.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json

ROOT = Path(__file__).resolve().parents[1]
SS = 4  # supersampling factor

NAVY_TOP = (40, 47, 92)
NAVY_BOTTOM = (13, 16, 37)
GOLD_LIGHT = (255, 231, 186)
GOLD_DEEP = (229, 176, 102)
PEACH = (250, 199, 158)
TEAL = (13, 153, 171)
MINT = (51, 158, 120)
CORAL = (230, 92, 84)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(n, top, bottom, diagonal=True):
    """An n x n RGB gradient from the top-left (or top) colour to the bottom-right (or bottom)."""
    img = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(img)
    if diagonal:
        # Draw anti-diagonal bands; t runs from the top-left corner to the bottom-right.
        for k in range(2 * n - 1):
            d.line((k, 0, 0, k) if k < n else (n - 1, k - n + 1, k - n + 1, n - 1), fill=lerp(top, bottom, k / (2 * n - 2)), width=2)
    else:
        for y in range(n):
            d.line((0, y, n, y), fill=lerp(top, bottom, y / (n - 1)))
    return img


def glow(n, center, radius, color, alpha):
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.55))


def crescent_mask(n, cx, cy, r, cut_dx, cut_dy, cut_r):
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    cut = Image.new("L", (n, n), 0)
    ImageDraw.Draw(cut).ellipse((cx + cut_dx - cut_r, cy + cut_dy - cut_r, cx + cut_dx + cut_r, cy + cut_dy + cut_r), fill=255)
    return ImageChops.subtract(mask, cut)


def rounded_line(d, x0, x1, y, width, fill):
    d.rounded_rectangle((x0, y - width / 2, x1, y + width / 2), radius=width / 2, fill=fill)


def draw_mark(img, cx, cy, r, lines=True):
    """The crescent with its ledger lines, centred on (cx, cy) with outer radius r."""
    n = img.size[0]
    mask = crescent_mask(n, cx, cy, r, r * 0.42, -r * 0.30, r * 0.80)
    # Luminous halo, then the champagne fill (light at the top, deeper towards the base).
    halo = Image.new("RGBA", (n, n), PEACH + (0,))
    halo.putalpha(mask.filter(ImageFilter.GaussianBlur(r * 0.16)).point(lambda v: int(v * 0.42)))
    img.alpha_composite(halo)
    fill = gradient(n, GOLD_LIGHT, GOLD_DEEP, diagonal=False).convert("RGBA")
    fill.putalpha(mask)
    img.alpha_composite(fill)
    if lines:
        # Three ledger lines inside the crescent's hollow, clear of the gold.
        d = ImageDraw.Draw(img)
        w = r * 0.10
        x0 = cx + r * 0.10
        for i, length in enumerate((0.50, 0.40, 0.27)):
            y = cy - r * 0.50 + i * r * 0.25
            rounded_line(d, x0, x0 + r * length, y, w, WHITE + (240 - i * 30,))
    return img


def icon(size=1024):
    n = size * SS
    img = gradient(n, NAVY_TOP, NAVY_BOTTOM).convert("RGBA")
    img.alpha_composite(glow(n, (n * 0.80, n * 0.12), n * 0.40, (120, 132, 214), 70))
    img.alpha_composite(glow(n, (n * 0.16, n * 0.94), n * 0.36, TEAL, 46))
    draw_mark(img, n * 0.46, n * 0.53, n * 0.31)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


# Notification thumbnails: a soft gradient tile with one white glyph, readable at a glance
# beside the system banner. Each matches a message kind sent by LedgerNotifications.

def tile(n, top, bottom):
    img = gradient(n, top, bottom).convert("RGBA")
    img.alpha_composite(glow(n, (n * 0.80, n * 0.12), n * 0.40, WHITE, 40))
    return img


def thumbnail_recorded(n):
    img = tile(n, (32, 178, 168), (14, 122, 128))
    d = ImageDraw.Draw(img)
    w = int(n * 0.085)
    pts = [(n * 0.30, n * 0.52), (n * 0.44, n * 0.66), (n * 0.71, n * 0.37)]
    d.line(pts, fill=WHITE + (255,), width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE + (255,))
    return img


def thumbnail_review(n):
    img = tile(n, (251, 178, 128), (226, 96, 86))
    d = ImageDraw.Draw(img)
    w = n * 0.10
    d.rounded_rectangle((n / 2 - w / 2, n * 0.25, n / 2 + w / 2, n * 0.58), radius=w / 2, fill=WHITE + (255,))
    d.ellipse((n / 2 - w * 0.62, n * 0.66, n / 2 + w * 0.62, n * 0.66 + w * 1.24), fill=WHITE + (255,))
    return img


def thumbnail_reminder(n):
    img = tile(n, NAVY_TOP, NAVY_BOTTOM)
    draw_mark(img, n * 0.45, n * 0.53, n * 0.30)
    return img


def thumbnail_budget(n):
    img = tile(n, (36, 66, 110), (12, 96, 112))
    d = ImageDraw.Draw(img)
    w = int(n * 0.075)
    box = (n * 0.22, n * 0.30, n * 0.78, n * 0.86)
    d.arc(box, 180, 360, fill=(255, 255, 255, 90), width=w)
    d.arc(box, 180, 315, fill=PEACH + (255,), width=w)
    cx, cy = n * 0.50, n * 0.58
    d.ellipse((cx - w * 0.75, cy - w * 0.75, cx + w * 0.75, cy + w * 0.75), fill=WHITE + (255,))
    d.line((cx, cy, n * 0.66, n * 0.42), fill=WHITE + (255,), width=int(w * 0.6))
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
