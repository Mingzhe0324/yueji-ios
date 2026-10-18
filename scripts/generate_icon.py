"""Draw the Moon Island cartoon app icon and notification mascot images.

Original artwork drawn from shapes (no downloaded assets). Run from the repo root:
    python scripts/generate_icon.py
Writes every AppIcon size (opaque RGB), the identical YueJiLogo image, the
YueJiIcon@2x/@3x fallbacks and the notification mascot thumbnails.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import json, math

ROOT = Path(__file__).resolve().parents[1]
SS = 4  # supersampling factor

INK = (41, 59, 56)
SUN = (255, 200, 82)
SUN_SHADE = (240, 168, 54)
OUTLINE = (150, 96, 40)
ACCENT = (31, 102, 79)
MINT = (122, 219, 176)
CREAM = (255, 246, 222)
SAND = (232, 196, 138)
PINK = (255, 140, 150)


def capsule(draw, box, fill, outline=None, width=0):
    x0, y0, x1, y1 = box
    r = min(x1 - x0, y1 - y0) / 2
    draw.rounded_rectangle(box, radius=r, fill=fill, outline=outline, width=width)


def rotated_layer(size, painter, angle, center):
    """Paint on a transparent layer, rotate it around `center`, return it."""
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    painter(ImageDraw.Draw(layer))
    return layer.rotate(angle, resample=Image.BICUBIC, center=center)


def draw_mascot(img, cx, cy, s, mood="happy"):
    """The companion: a rounded sun-yellow body with a leaf, arms and a face."""
    w, h = img.size
    lw = max(2, int(s * 0.035))
    # Soft ground shadow.
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((cx - s * 0.36, cy + s * 0.40, cx + s * 0.36, cy + s * 0.50), fill=(0, 0, 0, 60))
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(s * 0.02)))
    # Arms, behind the body.
    for side in (-1, 1):
        ax, ay = cx + side * s * 0.36, cy + s * 0.20
        def arm(d, ax=ax, ay=ay):
            capsule(d, (ax - s * 0.08, ay - s * 0.14, ax + s * 0.08, ay + s * 0.14), ACCENT, OUTLINE, lw)
        angle = 35 if side < 0 else -35
        if mood == "excited":
            angle = -50 if side < 0 else 50
            ay -= s * 0.18
        img.alpha_composite(rotated_layer(img.size, arm, angle, (ax, ay)))
    # Leaf on top.
    lx, ly = cx + s * 0.12, cy - s * 0.44
    def leaf(d):
        d.ellipse((lx - s * 0.08, ly - s * 0.16, lx + s * 0.08, ly + s * 0.16), fill=ACCENT, outline=OUTLINE, width=lw)
        d.line((lx, ly - s * 0.12, lx, ly + s * 0.14), fill=MINT, width=max(1, lw // 2))
    img.alpha_composite(rotated_layer(img.size, leaf, -30, (lx, ly)))
    d = ImageDraw.Draw(img)
    # Body with a shaded lower half and a thick cartoon outline.
    body = (cx - s * 0.40, cy - s * 0.40, cx + s * 0.40, cy + s * 0.42)
    d.rounded_rectangle(body, radius=s * 0.34, fill=SUN, outline=OUTLINE, width=lw)
    shade = Image.new("RGBA", img.size, (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    sd.rounded_rectangle(body, radius=s * 0.34, fill=SUN_SHADE + (255,))
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).ellipse((cx - s * 0.70, cy - s * 0.95, cx + s * 0.55, cy + s * 0.30), fill=255)
    shade.putalpha(Image.composite(Image.new("L", img.size, 0), shade.getchannel("A"), mask))
    img.alpha_composite(shade)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle(body, radius=s * 0.34, outline=OUTLINE, width=lw)
    # Glossy highlight.
    hl = Image.new("RGBA", img.size, (0, 0, 0, 0))
    def highlight(dd):
        dd.ellipse((cx - s * 0.30, cy - s * 0.33, cx - s * 0.02, cy - s * 0.22), fill=(255, 255, 255, 120))
    img.alpha_composite(rotated_layer(img.size, highlight, 25, (cx - s * 0.16, cy - s * 0.27)))
    d = ImageDraw.Draw(img)
    # Cheeks.
    cheek = Image.new("RGBA", img.size, (0, 0, 0, 0))
    cd = ImageDraw.Draw(cheek)
    for side in (-1, 1):
        x = cx + side * s * 0.24
        cd.ellipse((x - s * 0.07, cy + s * 0.05, x + s * 0.07, cy + s * 0.11), fill=PINK + (150 if mood == "excited" else 110,))
    img.alpha_composite(cheek)
    d = ImageDraw.Draw(img)
    # Eyes.
    ew = s * 0.035
    for side in (-1, 1):
        ex, ey = cx + side * s * 0.12, cy - s * 0.04
        if mood == "excited":
            d.arc((ex - s * 0.06, ey - s * 0.04, ex + s * 0.06, ey + s * 0.08), 200, 340, fill=INK, width=int(ew))
        elif mood == "sleepy":
            d.arc((ex - s * 0.06, ey - s * 0.08, ex + s * 0.06, ey + s * 0.04), 20, 160, fill=INK, width=int(ew))
        else:
            capsule(d, (ex - s * 0.032, ey - s * 0.06, ex + s * 0.032, ey + s * 0.06), INK)
            d.ellipse((ex - s * 0.004, ey - s * 0.045, ex + s * 0.020, ey - s * 0.021), fill=(255, 255, 255))
            if mood == "worried":
                bx, by = ex, ey - s * 0.11
                def brow(dd, bx=bx, by=by):
                    capsule(dd, (bx - s * 0.06, by - s * 0.014, bx + s * 0.06, by + s * 0.014), INK)
                # PIL rotates counter-clockwise: raise the inner ends for a worried look.
                img.alpha_composite(rotated_layer(img.size, brow, -18 * side, (bx, by)))
                d = ImageDraw.Draw(img)
    # Mouth.
    mw = int(s * 0.032)
    if mood == "excited":
        d.chord((cx - s * 0.10, cy + s * 0.04, cx + s * 0.10, cy + s * 0.22), 0, 180, fill=INK)
        d.ellipse((cx - s * 0.045, cy + s * 0.15, cx + s * 0.045, cy + s * 0.20), fill=PINK)
    elif mood == "worried":
        pts = [(cx - s * 0.08 + i * s * 0.016, cy + s * 0.15 + math.sin(i * 0.9) * s * 0.018) for i in range(11)]
        d.line(pts, fill=INK, width=mw, joint="curve")
    elif mood == "sleepy":
        d.ellipse((cx - s * 0.03, cy + s * 0.11, cx + s * 0.03, cy + s * 0.18), outline=INK, width=max(2, mw - 2))
    else:
        d.arc((cx - s * 0.08, cy + s * 0.04, cx + s * 0.08, cy + s * 0.17), 20, 160, fill=INK, width=mw)


def sparkle(d, x, y, r, fill):
    pts = []
    for i in range(8):
        a = i * math.pi / 4 - math.pi / 2
        rr = r if i % 2 == 0 else r * 0.32
        pts.append((x + math.cos(a) * rr, y + math.sin(a) * rr))
    d.polygon(pts, fill=fill)


def icon(size=1024):
    n = size * SS
    img = Image.new("RGBA", (n, n), (0, 0, 0, 255))
    d = ImageDraw.Draw(img)
    # Sky: vertical mint-to-teal gradient.
    top, bottom = (126, 222, 184), (38, 140, 112)
    for y in range(n):
        t = y / (n - 1)
        d.line((0, y, n, y), fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,))
    # Big soft sun glow behind the companion.
    glow = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((n * 0.12, n * 0.08, n * 0.88, n * 0.84), fill=(255, 236, 170, 120))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(n * 0.06)))
    d = ImageDraw.Draw(img)
    for x, y, r in ((0.16, 0.18, 0.045), (0.84, 0.22, 0.035), (0.80, 0.62, 0.028), (0.13, 0.58, 0.03)):
        sparkle(d, n * x, n * y, n * r, (255, 250, 225, 255))
    # Island: sand base with a grassy top, sitting in cartoon waves.
    d.ellipse((n * 0.16, n * 0.74, n * 0.84, n * 0.94), fill=SAND + (255,), outline=OUTLINE + (255,), width=int(n * 0.012))
    d.ellipse((n * 0.20, n * 0.72, n * 0.80, n * 0.86), fill=ACCENT + (255,))
    d.ellipse((n * 0.24, n * 0.72, n * 0.76, n * 0.82), fill=MINT + (255,))
    wave = [(0, n * 0.90)]
    for i in range(0, 101):
        x = n * i / 100
        wave.append((x, n * 0.905 + math.sin(i / 100 * math.pi * 6) * n * 0.012))
    wave += [(n, n), (0, n)]
    d.polygon(wave, fill=(30, 118, 96, 255))
    draw_mascot(img, n * 0.5, n * 0.49, n * 0.58, "happy")
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


def mascot_tile(mood, size=300):
    n = size * SS
    img = Image.new("RGBA", (n, n), CREAM + (255,))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, n - 1, n - 1), radius=n * 0.22, fill=(214, 244, 228, 255))
    draw_mascot(img, n * 0.5, n * 0.52, n * 0.70, mood)
    return img.convert("RGB").resize((size, size), Image.LANCZOS)


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
    for mood in ("happy", "worried", "sleepy"):
        mascot_tile(mood).save(ROOT / f"YueJi/YueJiMascot{mood.capitalize()}.png", optimize=True)
    print("Wrote app icons, logo, fallbacks and notification mascots.")


if __name__ == "__main__":
    main()
