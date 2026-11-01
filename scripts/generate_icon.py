#!/usr/bin/env python3
"""Renders the Dreamsign app icon (1024x1024) — default + tinted variants.

Crescent moon (the dream) with a small dawn star (the sign / the wake) over a
night gradient and a faint horizon glow. Supersampled 2x for clean edges.

    python3 scripts/generate_icon.py
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 2048  # supersampled canvas
OUT = os.path.join(os.path.dirname(__file__), "..", "Dreamsign", "Resources",
                   "Assets.xcassets", "AppIcon.appiconset")


def hex_rgb(h):
    return np.array([(h >> 16) & 255, (h >> 8) & 255, h & 255], dtype=np.float32)


def lerp(a, b, t):
    return a + (b - a) * t


def background():
    y, x = np.mgrid[0:S, 0:S].astype(np.float32) / S
    top, mid, bottom = hex_rgb(0x221B52), hex_rgb(0x0F0D26), hex_rgb(0x07070F)
    t = y[..., None]
    img = np.where(t < 0.55, lerp(top, mid, t / 0.55), lerp(mid, bottom, (t - 0.55) / 0.45))
    # iris bloom behind the moon
    d = np.sqrt((x - 0.47) ** 2 + (y - 0.42) ** 2)[..., None]
    img += hex_rgb(0x6F5CFF) * np.exp(-(d / 0.30) ** 2) * 0.42
    # dawn horizon: a huge circle whose upper rim glows warm at the bottom
    cx, cy, r = 0.5, 1.62, 0.78
    rim = np.abs(np.sqrt((x - cx) ** 2 + (y - cy) ** 2) - r)[..., None]
    img += hex_rgb(0xFF9F7A) * np.exp(-(rim / 0.018) ** 2) * 0.55
    below = 1.0 / (1.0 + np.exp(-(y[..., None] - 0.86) / 0.025))  # smooth, no seam
    img += hex_rgb(0xFF8A6B) * np.exp(-(rim / 0.07) ** 2) * 0.20 * below
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8), "RGB")


def stars(img, seed=7):
    rng = np.random.default_rng(seed)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for _ in range(70):
        x, y = rng.uniform(0.06, 0.94) * S, rng.uniform(0.05, 0.70) * S
        # keep stars off the moon
        if (x / S - 0.47) ** 2 + (y / S - 0.42) ** 2 < 0.075:
            continue
        r = rng.uniform(1.5, 4.2)
        a = int(rng.uniform(40, 150))
        d.ellipse([x - r, y - r, x + r, y + r], fill=(235, 232, 255, a))
    img.alpha_composite(layer)


def crescent_mask(cx, cy, r, ox, oy, rr):
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=255)
    d.ellipse([cx + ox - rr, cy + oy - rr, cx + ox + rr, cy + oy + rr], fill=0)
    return m


def sparkle_mask(cx, cy, size, waist):
    """Four-point star: two thin diamonds."""
    m = Image.new("L", (S, S), 0)
    d = ImageDraw.Draw(m)
    d.polygon([(cx, cy - size), (cx + waist, cy), (cx, cy + size), (cx - waist, cy)], fill=255)
    d.polygon([(cx - size, cy), (cx, cy - waist), (cx + size, cy), (cx, cy + waist)], fill=255)
    return m.filter(ImageFilter.GaussianBlur(1.2))


def render(tinted=False):
    if tinted:
        img = Image.new("RGBA", (S, S), (0, 0, 0, 255))
    else:
        img = background().convert("RGBA")
        stars(img)

    cx, cy, r = 0.47 * S, 0.42 * S, 0.255 * S
    moon = crescent_mask(cx, cy, r, 0.155 * S, -0.085 * S, 0.225 * S)

    # glow
    glow_color = (200, 190, 255) if not tinted else (255, 255, 255)
    glow = Image.new("RGBA", (S, S), glow_color + (0,))
    glow.putalpha(moon.filter(ImageFilter.GaussianBlur(70)).point(lambda v: int(v * (0.55 if not tinted else 0.35))))
    img.alpha_composite(glow)

    # moon body with a soft vertical gradient
    y = np.linspace(0, 1, S, dtype=np.float32)[:, None, None]
    top = np.array([248, 246, 255], np.float32) if not tinted else np.array([255, 255, 255], np.float32)
    bot = np.array([196, 186, 255], np.float32) if not tinted else np.array([205, 205, 205], np.float32)
    shade = np.broadcast_to(lerp(top, bot, np.clip((y - 0.18) / 0.5, 0, 1)), (S, S, 3))
    body = Image.fromarray(shade.astype(np.uint8), "RGB").convert("RGBA")
    body.putalpha(moon)
    img.alpha_composite(body)

    # the dream sign: a dawn-coloured four-point star in the crescent's mouth
    sx, sy = 0.655 * S, 0.335 * S
    star_color = (255, 196, 160) if not tinted else (255, 255, 255)
    halo = Image.new("RGBA", (S, S), star_color + (0,))
    halo_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(halo_mask).ellipse([sx - 60, sy - 60, sx + 60, sy + 60], fill=255)
    halo.putalpha(halo_mask.filter(ImageFilter.GaussianBlur(40)).point(lambda v: int(v * 0.6)))
    img.alpha_composite(halo)
    spark = Image.new("RGBA", (S, S), star_color + (0,))
    spark.putalpha(sparkle_mask(sx, sy, 0.062 * S, 0.012 * S))
    img.alpha_composite(spark)
    small = Image.new("RGBA", (S, S), star_color + (0,))
    small.putalpha(sparkle_mask(0.735 * S, 0.445 * S, 0.026 * S, 0.006 * S).point(lambda v: int(v * 0.8)))
    img.alpha_composite(small)

    return img.convert("RGB").resize((1024, 1024), Image.LANCZOS)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    render().save(os.path.join(OUT, "AppIcon.png"), optimize=True)
    render(tinted=True).convert("L").save(os.path.join(OUT, "AppIcon-Tinted.png"), optimize=True)
    print("wrote", os.path.abspath(OUT))
