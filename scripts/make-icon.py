#!/usr/bin/env python3
"""Generate AppIcon.icns for ClaudeStats.

Design: squircle background with a subtle radial gradient, an ornamental
gauge ring progressing from green → orange, and a stylized sparkle/dot glyph
where the gauge needle points. Rendered at 1024×1024 then exported to every
required size for a macOS .iconset.
"""

import os, math, subprocess, shutil
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "Resources", "AppIcon.iconset")
ICNS_PATH = os.path.join(ROOT, "Resources", "AppIcon.icns")

SIZE = 1024
CORNER = 225  # macOS squircle ratio
MARGIN = 120


def squircle(size, radius):
    im = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(im)
    d.rounded_rectangle([0, 0, size, size], radius=radius, fill=255)
    return im


def radial_gradient(size, inner, outer):
    """Soft radial gradient from inner (center) to outer (edges)."""
    im = Image.new("RGB", (size, size))
    cx = cy = size / 2
    maxd = math.hypot(cx, cy)
    px = im.load()
    for y in range(size):
        for x in range(size):
            d = math.hypot(x - cx, y - cy) / maxd
            d = min(1, d)
            r = int(inner[0] * (1 - d) + outer[0] * d)
            g = int(inner[1] * (1 - d) + outer[1] * d)
            b = int(inner[2] * (1 - d) + outer[2] * d)
            px[x, y] = (r, g, b)
    return im


def arc_gradient_mask(size, thickness, start_deg, end_deg):
    """Return an RGBA arc with a colour gradient along its sweep (green→orange→red)."""
    arc = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(arc)
    # rainbow-like warm→cool sweep
    stops = [
        (0.00, (70, 210, 130)),    # green
        (0.55, (255, 190, 70)),    # amber
        (0.85, (240, 110, 60)),    # orange
        (1.00, (220, 60, 55)),     # red
    ]

    def lerp(a, b, t):
        return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

    def color_at(t):
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                return lerp(c0, c1, (t - t0) / (t1 - t0))
        return stops[-1][1]

    steps = 360
    for i in range(steps):
        t0 = i / steps
        t1 = (i + 1) / steps
        a0 = start_deg + (end_deg - start_deg) * t0
        a1 = start_deg + (end_deg - start_deg) * t1
        c = color_at(t0)
        d.arc(
            [MARGIN, MARGIN, size - MARGIN, size - MARGIN],
            start=a0,
            end=a1,
            fill=c + (255,),
            width=thickness,
        )
    return arc


def compose():
    # Background gradient — deep violet/navy
    bg = radial_gradient(SIZE, inner=(48, 55, 95), outer=(16, 18, 36))
    mask = squircle(SIZE, CORNER)

    base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    base.paste(bg, (0, 0), mask)

    # Inner darker track circle
    track = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    td = ImageDraw.Draw(track)
    td.ellipse([MARGIN, MARGIN, SIZE - MARGIN, SIZE - MARGIN], outline=(255, 255, 255, 40), width=30)
    base = Image.alpha_composite(base, track)

    # Gauge arc (start at 135°, end at 45° going clockwise = 270° sweep)
    # PIL arc: angles measured clockwise from 3 o'clock.
    arc = arc_gradient_mask(SIZE, thickness=48, start_deg=135, end_deg=135 + 270 * 0.72)
    # soften edges slightly
    arc = arc.filter(ImageFilter.GaussianBlur(radius=1.5))
    base = Image.alpha_composite(base, arc)

    # Centre glyph: sparkle-ish "C" ring + dot
    draw = ImageDraw.Draw(base)
    cx = cy = SIZE // 2
    r = 170
    draw.arc([cx - r, cy - r, cx + r, cy + r], start=130, end=50, fill=(255, 255, 255, 235), width=44)
    # Accent dot at tip
    dot_r = 30
    tip_angle = math.radians(50)
    tx = cx + int(r * math.cos(tip_angle))
    ty = cy + int(r * math.sin(tip_angle))
    draw.ellipse([tx - dot_r, ty - dot_r, tx + dot_r, ty + dot_r], fill=(255, 170, 80, 255))

    # Clip to squircle once more (in case any overshoot)
    final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    final.paste(base, (0, 0), mask)
    return final


def main():
    if os.path.isdir(OUT_DIR):
        shutil.rmtree(OUT_DIR)
    os.makedirs(OUT_DIR)

    master = compose()
    master.save(os.path.join(ROOT, "Resources", "AppIcon-1024.png"))

    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for s in sizes:
        scaled = master.resize((s, s), Image.LANCZOS)
        scaled.save(os.path.join(OUT_DIR, f"icon_{s}x{s}.png"))
        if s < 1024:
            scaled2 = master.resize((s * 2, s * 2), Image.LANCZOS)
            scaled2.save(os.path.join(OUT_DIR, f"icon_{s}x{s}@2x.png"))

    subprocess.run(["iconutil", "-c", "icns", OUT_DIR, "-o", ICNS_PATH], check=True)
    print(f"✓ Wrote {ICNS_PATH}")


if __name__ == "__main__":
    main()
