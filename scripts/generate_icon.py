"""Draw the YueJi app icon and the notification thumbnails.

Original artwork drawn from shapes (no downloaded assets). Run from the repo root:
    python scripts/generate_icon.py
Writes every AppIcon size (opaque RGB), the identical YueJiLogo image, the
YueJiIcon@2x/@3x fallbacks (the icon AltStore shows, read from CFBundleIconFiles)
and the four notification thumbnails.

The icon follows Apple's iOS 26/27 Liquid Glass icon style: a vivid indigo gradient,
a frosted glass ledger card (记, "record") with three entries and bright glass edges,
and a gold crescent moon (月, "moon") layered in front with a soft shadow.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFilter
import json

ROOT = Path(__file__).resolve().parents[1]
SS = 3  # supersampling factor

INDIGO_TOP = (104, 100, 248)
INDIGO_BOTTOM = (58, 44, 178)
SHEEN = (170, 176, 255)
GOLD_TOP = (255, 232, 170)
GOLD_BOTTOM = (238, 168, 74)
WHITE = (255, 255, 255)


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def vertical(n, top, bottom):
    img = Image.new("RGBA", (n, n))
    d = ImageDraw.Draw(img)
    for y in range(n):
        d.line((0, y, n, y), fill=lerp(top, bottom, y / (n - 1)) + (255,))
    return img


def glow(n, center, radius, color, alpha):
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    x, y = center
    ImageDraw.Draw(layer).ellipse((x - radius, y - radius, x + radius, y + radius), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.6))


def background(n):
    img = vertical(n, INDIGO_TOP, INDIGO_BOTTOM)
    img.alpha_composite(glow(n, (n * 0.30, n * 0.05), n * 0.55, SHEEN, 70))
    return img


def card_mask(n, box, radius, angle=0.0, center=None):
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).rounded_rectangle(box, radius=radius, fill=255)
    return mask.rotate(angle, resample=Image.BICUBIC, center=center) if angle else mask


def crescent_mask(n, cx, cy, r):
    """A disc minus an offset disc: the crescent from the earlier icons, same proportions."""
    mask = Image.new("L", (n, n), 0)
    ImageDraw.Draw(mask).ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
    cut = Image.new("L", (n, n), 0)
    x, y, cr = cx + 0.42 * r, cy - 0.30 * r, 0.80 * r
    ImageDraw.Draw(cut).ellipse((x - cr, y - cr, x + cr, y + cr), fill=255)
    return ImageChops.subtract(mask, cut)


def shadow(img, mask, blur, dy, alpha):
    n = img.size[0]
    layer = Image.new("RGBA", (n, n), (16, 12, 60, 0))
    soft = mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda v: int(v * alpha))
    layer.putalpha(ImageChops.offset(soft, 0, int(dy)))
    img.alpha_composite(layer)


def rim(img, mask, width, strength=1.0):
    """A specular edge, brightest at the top-left, like light catching glass."""
    n = img.size[0]
    inner = mask.filter(ImageFilter.MinFilter(int(width) * 2 + 1))
    edge = ImageChops.subtract(mask, inner).filter(ImageFilter.GaussianBlur(width * 0.4))
    light = Image.new("L", (n, n))
    d = ImageDraw.Draw(light)
    for k in range(2 * n - 1):
        v = int(255 * strength * max(0.15, 1 - (k / (2 * n - 2)) * 1.3))
        d.line((k, 0, 0, k) if k < n else (n - 1, k - n + 1, k - n + 1, n - 1), fill=v, width=2)
    layer = Image.new("RGBA", (n, n), WHITE + (0,))
    layer.putalpha(ImageChops.multiply(edge, light))
    img.alpha_composite(layer)


def frosted(img, mask, alpha=0.30, blur=0.03):
    """Frosted glass: the background blurred and lightened inside the mask."""
    n = img.size[0]
    behind = img.filter(ImageFilter.GaussianBlur(n * blur))
    behind.alpha_composite(Image.new("RGBA", (n, n), WHITE + (int(255 * alpha),)))
    behind.putalpha(mask)
    img.alpha_composite(behind)


def fill(img, mask, top, bottom):
    layer = vertical(img.size[0], top, bottom)
    layer.putalpha(mask)
    img.alpha_composite(layer)


def highlight(img, mask, cx, cy, r, alpha):
    n = img.size[0]
    spot = Image.new("L", (n, n), 0)
    ImageDraw.Draw(spot).ellipse((cx - r, cy - r, cx + r, cy + r), fill=int(255 * alpha))
    layer = Image.new("RGBA", (n, n), WHITE + (0,))
    layer.putalpha(ImageChops.multiply(spot.filter(ImageFilter.GaussianBlur(r * 0.5)), mask))
    img.alpha_composite(layer)


def entries(n, x0, y0, gap, w, lengths):
    """Ledger entries: a bullet and a line each, in white."""
    layer = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, length in enumerate(lengths):
        y = y0 + i * gap
        d.ellipse((x0 - w * 0.75, y - w * 0.75, x0 + w * 0.75, y + w * 0.75), fill=WHITE + (240,))
        x1 = x0 + w * 1.7
        d.rounded_rectangle((x1, y - w / 2, x1 + length, y + w / 2), radius=w / 2, fill=WHITE + (240,))
    return layer


def glass_card(img, box, radius, angle=0.0, center=None):
    n = img.size[0]
    mask = card_mask(n, box, radius, angle, center)
    shadow(img, mask, n * 0.035, n * 0.03, 0.40)
    frosted(img, mask, alpha=0.30)
    rim(img, mask, n * 0.007)
    return mask


def gold_moon(img, cx, cy, r):
    n = img.size[0]
    mask = crescent_mask(n, cx, cy, r)
    shadow(img, mask, n * 0.025, n * 0.02, 0.45)
    fill(img, mask, GOLD_TOP, GOLD_BOTTOM)
    highlight(img, mask, cx - r * 0.42, cy - r * 0.47, r * 0.53, 0.6)
    rim(img, mask, n * 0.005, 0.9)


def icon(size=1024):
    n = size * SS
    img = background(n)
    center = (n * 0.53, n * 0.50)
    glass_card(img, (n * 0.25, n * 0.20, n * 0.81, n * 0.80), n * 0.115, -7, center)
    img.alpha_composite(entries(n, n * 0.40, n * 0.43, n * 0.09, n * 0.032, (n * 0.25, n * 0.20, n * 0.14))
                       .rotate(-7, resample=Image.BICUBIC, center=center))
    gold_moon(img, n * 0.33, n * 0.69, n * 0.17)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


# Notification thumbnails: the icon's indigo and glass card carrying one white glyph,
# so every message looks like it comes from the same app.

def thumbnail_base(n):
    img = background(n)
    glass_card(img, (n * 0.18, n * 0.18, n * 0.82, n * 0.82), n * 0.13)
    return img


def thumbnail_recorded(n):
    img = thumbnail_base(n)
    d = ImageDraw.Draw(img)
    w = int(n * 0.07)
    pts = [(n * 0.33, n * 0.51), (n * 0.45, n * 0.63), (n * 0.68, n * 0.39)]
    d.line(pts, fill=WHITE + (250,), width=w, joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=WHITE + (250,))
    return img


def thumbnail_review(n):
    img = thumbnail_base(n)
    d = ImageDraw.Draw(img)
    w = n * 0.085
    d.rounded_rectangle((n / 2 - w / 2, n * 0.30, n / 2 + w / 2, n * 0.57), radius=w / 2, fill=WHITE + (250,))
    d.ellipse((n / 2 - w * 0.6, n * 0.63, n / 2 + w * 0.6, n * 0.63 + w * 1.2), fill=WHITE + (250,))
    return img


def thumbnail_reminder(n):
    img = background(n)
    center = (n * 0.53, n * 0.50)
    glass_card(img, (n * 0.25, n * 0.20, n * 0.81, n * 0.80), n * 0.115, -7, center)
    img.alpha_composite(entries(n, n * 0.40, n * 0.43, n * 0.09, n * 0.032, (n * 0.25, n * 0.20, n * 0.14))
                       .rotate(-7, resample=Image.BICUBIC, center=center))
    gold_moon(img, n * 0.33, n * 0.69, n * 0.17)
    return img


def thumbnail_budget(n):
    img = thumbnail_base(n)
    d = ImageDraw.Draw(img)
    w = int(n * 0.06)
    box = (n * 0.29, n * 0.34, n * 0.71, n * 0.76)
    d.arc(box, 180, 360, fill=WHITE + (90,), width=w)
    d.arc(box, 180, 318, fill=GOLD_TOP + (255,), width=w)
    cx, cy = n * 0.50, n * 0.55
    d.line((cx, cy, n * 0.62, n * 0.43), fill=WHITE + (250,), width=int(w * 0.6))
    d.ellipse((cx - w * 0.7, cy - w * 0.7, cx + w * 0.7, cy + w * 0.7), fill=WHITE + (250,))
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
