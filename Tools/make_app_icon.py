#!/usr/bin/env python3
"""Generates the macOS app icon for ISS Tracker.

Draws a stylized ISS over the night side of Earth on the classic macOS
rounded-square plate, then writes every size required by AppIcon.appiconset
into Resources/Assets.xcassets.

Re-run with:  python3 Tools/make_app_icon.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
ASSET_DIR = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"

RENDER = 2048          # render 2x the 1024 master for clean anti-aliasing
U = RENDER / 1024.0    # 1 unit == 1 px on the 1024-point grid

# macOS plate: 824x824, corner radius 185.4, centered on the 1024 canvas
PLATE = int(824 * U)
PLATE_X = int((RENDER - PLATE) / 2)
RADIUS = int(185.4 * U)

SPACE_TOP = (18, 30, 62)      # deep night blue
SPACE_BOTTOM = (5, 10, 24)    # near black
GOLD = (245, 180, 58)
GOLD_DARK = (188, 128, 28)
GREY_LIGHT = (235, 240, 247)
GREY = (172, 182, 196)
GREY_DARK = (110, 122, 140)

CX = 512 * U   # station center X
CY = 468 * U   # station center Y


def space_gradient(img):
    d = ImageDraw.Draw(img)
    for y in range(PLATE_X, PLATE_X + PLATE):
        t = (y - PLATE_X) / PLATE
        color = tuple(int(a + (b - a) * t) for a, b in zip(SPACE_TOP, SPACE_BOTTOM))
        d.line([(PLATE_X, y), (PLATE_X + PLATE, y)], fill=color)


def stars(img, rng):
    layer = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    margin = int(40 * U)
    for _ in range(170):
        x = rng.uniform(PLATE_X + margin, PLATE_X + PLATE - margin)
        y = rng.uniform(PLATE_X + margin, RENDER * 0.64)
        r = rng.choice([1.2, 1.6, 2.2, 3.0]) * U
        a = rng.randint(60, 215)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    # a couple of 4-point sparkle stars
    for sx, sy, s in [(318, 238, 11), (704, 158, 8), (760, 380, 6)]:
        x, y, z = sx * U, sy * U, s * U
        for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            d.line([(x, y), (x + dx * z, y + dy * z)], fill=(255, 255, 255, 210),
                   width=int(2.4 * U))
    img.alpha_composite(layer)


def earth(img):
    """Earth limb across the bottom of the plate."""
    d = ImageDraw.Draw(img)
    cx, cy, r = 512 * U, 1130 * U, 480 * U

    # atmosphere glow
    glow = int(36 * U)
    for i in range(glow, 0, -1):
        a = int(42 * (1 - i / glow))
        d.ellipse([cx - r - i, cy - r - i, cx + r + i, cy + r + i],
                  outline=(110, 185, 240, a), width=int(1.8 * U))

    # ocean + land on a disc-clipped layer
    disc = Image.new("L", (RENDER, RENDER), 0)
    ImageDraw.Draw(disc).ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    ground = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(27, 76, 116))
    rng = random.Random(7)
    for _ in range(26):
        ex = rng.uniform(cx - r * 0.9, cx + r * 0.9)
        ey = rng.uniform(r + cy - r - 352 * U * 4, cy - r + 470 * U)  # keep near the limb
        w, h = rng.uniform(46, 150) * U, rng.uniform(24, 74) * U
        blob = Image.new("RGBA", (int(w * 2.2), int(h * 2.2)), (0, 0, 0, 0))
        ImageDraw.Draw(blob).ellipse([0, 0, w * 1.7, h * 1.7], fill=(62, 148, 112, 170))
        ground.alpha_composite(
            blob.rotate(rng.uniform(-24, 24), resample=Image.BICUBIC,
                        center=(int(w * 0.85), int(h * 0.85))),
            (int(ex - w * 0.85), int(ey - h * 0.85)))
    for _ in range(14):  # cloud streaks
        clx = rng.uniform(cx - r * 0.8, cx + r * 0.8)
        cly = rng.uniform(cy - r, cy - r + 400 * U)
        cw = rng.uniform(60, 190) * U
        gd.rounded_rectangle([clx, cly, clx + cw, cly + 11 * U], radius=int(5.5 * U),
                             fill=(255, 255, 255, 30))
    img.paste(ground, (0, 0), disc)

    # crisp limb line on top of everything
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(125, 205, 250), width=int(5 * U))


def orbit(img):
    """Dashed flight path arcing beneath the station."""
    d = ImageDraw.Draw(img)
    pts = []
    for t in range(0, 181, 3):
        a = math.radians(t)
        x = 512 * U + 430 * U * math.cos(a)
        y = 640 * U - 210 * U * math.sin(a) + 70 * U * math.sin(a) ** 2
        pts.append((x, y))
    for i in range(len(pts) - 1):
        if (i // 3) % 2 == 0:
            d.line([pts[i], pts[i + 1]], fill=(255, 255, 255, 105),
                   width=int(5 * U), joint="curve")


def _panel(d, x, y, w, h):
    lw = int(4.5 * U)
    d.rounded_rectangle([x, y, x + w, y + h], radius=int(6 * U), fill=GOLD,
                        outline=GOLD_DARK, width=lw)
    for i in range(1, 4):
        sx = x + w * i / 4
        d.line([(sx, y + lw), (sx, y + h - lw)], fill=GOLD_DARK, width=lw)


def _truss(d, x0, y0, x1, y1):
    lw = int(4.5 * U)
    d.rounded_rectangle([x0, y0, x1, y1], radius=int(7 * U), fill=GREY,
                        outline=GREY_DARK, width=lw)
    for i in range(1, 13):
        sx = x0 + (x1 - x0) * i / 13
        d.line([(sx, y0 + lw * 0.5), (sx - 6 * U, y1 - lw * 0.5)],
               fill=GREY_DARK, width=max(2, lw - 2))


def _module(d, x, y, w, h, color=GREY_LIGHT):
    lw = int(4.5 * U)
    d.rounded_rectangle([x, y, x + w, y + h], radius=int(h * 0.42), fill=color,
                        outline=GREY_DARK, width=lw)
    d.rounded_rectangle([x + w * 0.30, y - 14 * U, x + w * 0.70, y + 9 * U],
                        radius=int(8 * U), fill=(196, 152, 106))  # docking collar
    for i in range(1, 3):
        sx = x + w * i / 3
        d.line([(sx, y + lw), (sx, y + h - lw)], fill=GREY_DARK, width=max(2, lw - 2))


def iss(img):
    """"Flat, centered station, tilted a touch for motion."""
    station = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    sd = ImageDraw.Draw(station)

    dx = CX
    dy = CY
    # solar array pairs stacked on each truss end
    _panel(sd, dx - 428 * U, dy - 152 * U, 176 * U, 100 * U)
    _panel(sd, dx - 428 * U, dy + 30 * U, 176 * U, 100 * U)
    _panel(sd, dx + 252 * U, dy - 152 * U, 176 * U, 100 * U)
    _panel(sd, dx + 252 * U, dy + 30 * U, 176 * U, 100 * U)
    # long truss
    _truss(sd, dx - 252 * U, dy - 13 * U, dx + 252 * U, dy + 13 * U)
    # pressurized modules running perpendicular to the truss
    _module(sd, dx - 46 * U, dy - 118 * U, 92 * U, 122 * U)
    _module(sd, dx - 62 * U, dy - 22 * U, 124 * U, 50 * U)
    _module(sd, dx - 34 * U, dy + 32 * U, 68 * U, 80 * U)
    # cupola at the top
    sd.rounded_rectangle([dx - 26 * U, dy - 158 * U, dx + 26 * U, dy - 116 * U],
                         radius=int(12 * U), fill=(214, 224, 238),
                         outline=GREY_DARK, width=int(4.5 * U))
    sd.ellipse([dx - 12 * U, dy - 150 * U, dx + 12 * U, dy - 130 * U],
               fill=(96, 160, 212))  # window

    rot = station.rotate(8, resample=Image.BICUBIC, center=(dx, dy))

    # soft shadow for lift against the globe
    sh = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([dx - 280 * U, 690 * U, dx + 280 * U, 780 * U],
                               fill=(0, 0, 0, 110))
    img.alpha_composite(sh.filter(ImageFilter.GaussianBlur(int(16 * U))))
    img.alpha_composite(rot)


def sheen(img):
    """Classic macOS top-light."""
    top = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    td = ImageDraw.Draw(top)
    for i in range(int(PLATE * 0.55)):
        a = max(0, int(30 * (1 - i / (PLATE * 0.55))))
        td.line([(PLATE_X, PLATE_X + i), (PLATE_X + PLATE, PLATE_X + i)],
                fill=(255, 255, 255, a))
    img.alpha_composite(top)


def border(img):
    ImageDraw.Draw(img).rounded_rectangle(
        [PLATE_X, PLATE_X, PLATE_X + PLATE, PLATE_X + PLATE],
        radius=RADIUS, outline=(255, 255, 255, 42), width=int(3 * U))


def write_asset_catalog(master):
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    (ASSET_DIR.parent / "Contents.json").write_text(
        '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')

    # size -> filenames (1x and 2x); sizes in points, rendered edge length in px
    table = [
        (16, ["icon_16x16.png", "icon_16x16@2x.png"]),
        (32, ["icon_32x32.png", "icon_32x32@2x.png"]),
        (128, ["icon_128x128.png", "icon_128x128@2x.png"]),
        (256, ["icon_256x256.png", "icon_256x256@2x.png"]),
        (512, ["icon_512x512.png", "icon_512x512@2x.png"]),
    ]
    entries = []
    for points, names in table:
        for name in names:
            px = points * (2 if "@2x" in name else 1)
            master.resize((px, px), Image.LANCZOS).save(ASSET_DIR / name)
            entries.append(
                '{\n      "filename" : "%s",\n      "idiom" : "mac",\n'
                '      "scale" : "%s",\n      "size" : "%dx%d"\n    }'
                % (name, "2x" if "@2x" in name else "1x", points, points))
    (ASSET_DIR / "Contents.json").write_text(
        '{\n  "images" : [\n    ' + ",\n    ".join(entries) + '\n  ],\n'
        '  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n')
    print("Wrote", len(entries), "icon files to", ASSET_DIR)


def main():
    rng = random.Random(42)

    icon = Image.new("RGBA", (RENDER, RENDER), (0, 0, 0, 0))
    space_gradient(icon)
    stars(icon, rng)
    earth(icon)
    orbit(icon)
    iss(icon)
    sheen(icon)
    border(icon)

    # clip to the plate
    mask = Image.new("L", (RENDER, RENDER), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [PLATE_X, PLATE_X, PLATE_X + PLATE, PLATE_X + PLATE], radius=RADIUS, fill=255)
    icon = Image.composite(icon, Image.new("RGBA", icon.size, (0, 0, 0, 0)), mask)

    master = icon.resize((1024, 1024), Image.LANCZOS)
    master.save(ROOT / "Tools" / "AppIcon-master.png")
    write_asset_catalog(master)


if __name__ == "__main__":
    main()
