#!/usr/bin/env python3
"""
Promo video for MagnetBoard: 1080x1920, 30 fps, ~15 s, WebM (VP9 + Opus).

Renders the app's board as motion graphics with Pillow (same palette and the
same pull maths as `MagneticTile.swift`), synthesises the clicky sound design
with numpy, then pipes the frames through ffmpeg.

    python3 tools/make_promo.py                 # -> promo/magnetboard-promo.webm
    python3 tools/make_promo.py --stills        # -> promo/stills/*.png for review

Requires: ffmpeg, pillow, numpy.
"""

import argparse
import math
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

# ----------------------------------------------------------------- config ---

W, H = 1080, 1920
FPS = 30
DURATION = 15.0
S = 2  # sprite supersampling factor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROMO_DIR = os.path.join(ROOT, "promo")

FONT_DISPLAY = "/usr/share/fonts/Adwaita/AdwaitaSans-Regular.ttf"
FONT_MONO = "/usr/share/fonts/noto/NotoSansMono-Bold.ttf"

# Theme.swift, 1:1
INK_DEEP = (5, 8, 15)
INK = (10, 15, 26)
SURFACE = (14, 22, 34)
STROKE = (255, 255, 255, 20)
TEXT = (235, 240, 250)
TEXT_DIM = (108, 122, 145)
ACCENT = (89, 222, 250)
ACCENT_ALT = (140, 115, 255)
MINT = (107, 245, 176)
WARM = (255, 130, 97)

# board geometry (1x)
PAD = 48
TILE_W = 477
COL2 = PAD + TILE_W + 30
ROW1_Y, ROW1_H = 300, 330
BRI_Y, BRI_H = 660, 240
MODE_Y, MODE_H = 930, 240
COUNT_Y, COUNT_H = 1200, 200
HUD_Y, HUD_H = 1430, 300
SENSOR = (194, 238)  # MagnetSupport.sensorPosition (70, 86) pt, scaled

REACH = 950.0
TRAVEL = 46.0
TILT = 4.5

TAP_T = 8.0
YANK_T = 10.2
OUTRO_T = 11.05

TILES = [
    ("power", PAD, ROW1_Y, TILE_W, ROW1_H),
    ("level", COL2, ROW1_Y, TILE_W, ROW1_H),
    ("bright", PAD, BRI_Y, 984, BRI_H),
    ("mode", PAD, MODE_Y, 984, MODE_H),
    ("counter", PAD, COUNT_Y, 984, COUNT_H),
]

# ------------------------------------------------------------------ maths ---


def clamp(x, lo=0.0, hi=1.0):
    return lo if x < lo else hi if x > hi else x


def smooth(t):
    t = clamp(t)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def mix(c1, c2, t):
    return tuple(int(round(lerp(c1[i], c2[i], t))) for i in range(3))


def rgba(c, a):
    return (c[0], c[1], c[2], int(clamp(a, 0, 1) * 255))


def blend_on(c1, c2, t):
    """A solid colour that looks like c2 at alpha t over c1 (sprite-safe)."""
    return mix(c1, c2, t)


PUCK_KEYS = [
    (2.10, 120.0, 150.0),
    (2.70, 250.0, 330.0),
    (3.50, 830.0, 380.0),
    (4.20, 610.0, 640.0),
    (4.90, 235.0, 780.0),
    (5.60, 300.0, 1030.0),
    (6.30, 840.0, 1080.0),
    (7.00, 620.0, 1300.0),
    (7.55, 540.0, 1460.0),
    (8.00, 610.0, 980.0),
    (8.13, 610.0, 980.0),
    (8.70, 770.0, 700.0),
    (9.30, 430.0, 870.0),
    (9.70, 940.0, 800.0),
    (9.95, 1120.0, 730.0),
    (10.20, 1120.0, 730.0),
    (10.70, 900.0, 190.0),
    (11.00, 1010.0, 40.0),
]


def catmull(p0, p1, p2, p3, u):
    m1 = ((p2[0] - p0[0]) * 0.5, (p2[1] - p0[1]) * 0.5)
    m2 = ((p3[0] - p1[0]) * 0.5, (p3[1] - p1[1]) * 0.5)
    u2, u3 = u * u, u * u * u
    h00 = 2 * u3 - 3 * u2 + 1
    h10 = u3 - 2 * u2 + u
    h01 = -2 * u3 + 3 * u2
    h11 = u3 - u2
    return (
        h00 * p1[0] + h10 * m1[0] + h01 * p2[0] + h11 * m2[0],
        h00 * p1[1] + h10 * m1[1] + h01 * p2[1] + h11 * m2[1],
    )


def puck_pos(t):
    if t <= PUCK_KEYS[0][0]:
        return PUCK_KEYS[0][1], PUCK_KEYS[0][2]
    if t >= PUCK_KEYS[-1][0]:
        return PUCK_KEYS[-1][1], PUCK_KEYS[-1][2]
    for i in range(len(PUCK_KEYS) - 1):
        t0, x0, y0 = PUCK_KEYS[i]
        t1, x1, y1 = PUCK_KEYS[i + 1]
        if t0 <= t <= t1:
            span = max(1e-6, t1 - t0)
            u = (t - t0) / span
            p0 = (PUCK_KEYS[i - 1][1], PUCK_KEYS[i - 1][2]) if i > 0 else (x0, y0)
            p3 = (PUCK_KEYS[i + 2][1], PUCK_KEYS[i + 2][2]) if i + 2 < len(PUCK_KEYS) else (x1, y1)
            return catmull(p0, (x0, y0), (x1, y1), p3, u)
    return PUCK_KEYS[-1][1], PUCK_KEYS[-1][2]


def presence(t):
    if t < 2.10:
        return 0.0
    if t < 2.75:
        return smooth((t - 2.10) / 0.65)
    if t < YANK_T:
        return 1.0
    if t < 10.75:
        return 1.0 - smooth((t - YANK_T) / 0.55)
    return 0.0


def closeness(t, pos=None):
    x, y = pos or puck_pos(t)
    d = math.hypot(x - SENSOR[0], y - SENSOR[1])
    return clamp(1 - d / 900.0) ** 1.4


def pull(t):
    return presence(t) * (0.25 + 0.75 * closeness(t))


def distance_cm(t):
    return 2.0 + 9.5 * (1 - closeness(t))


BOARD_TOP, BOARD_BOTTOM = 150.0, 1840.0


def gather_state(t):
    """Same rule as EdgeGather.swift: nearest edge, strength from near/outside."""
    x, y = puck_pos(t)
    pres = presence(t)
    if pres <= 0.02:
        return 0.0, None, None

    left, right = PAD, W - PAD
    d_left = x - left
    d_right = right - x
    d_top = y - BOARD_TOP
    d_bottom = BOARD_BOTTOM - y

    outside = max(0.0, -min(d_left, d_right, d_top, d_bottom))
    near = max(0.0, 1 - min(d_left, d_right, d_top, d_bottom) / 150)
    strength = min(1.0, max(near * near * 0.72, outside / 70)) * pres
    if strength < 0.03:
        return 0.0, None, None

    edge = min((("left", d_left), ("right", d_right), ("top", d_top), ("bottom", d_bottom)),
               key=lambda item: item[1])[0]

    ax = min(max(x, left + 44), right - 44)
    ay = min(max(y, BOARD_TOP + 44), BOARD_BOTTOM - 44)
    if edge == "left":
        ax = left
    elif edge == "right":
        ax = right
    elif edge == "top":
        ay = BOARD_TOP
    else:
        ay = BOARD_BOTTOM

    return strength, (ax, ay), edge


def focus_point(t):
    """Where particles pile: the magnet clamped inside the screen."""
    x, y = puck_pos(t)
    px = min(max(x, 14), W - 14)
    py = min(max(y, 14), H - 14)
    piled = abs(px - x) > 0.5 or abs(py - y) > 0.5
    return px, py, piled


def height_cm(t):
    return 0.5 + 2.6 * (1 - closeness(t))


# ------------------------------------------------------------------ fonts ---


def display(size, weight="ExtraBold"):
    f = ImageFont.truetype(FONT_DISPLAY, size)
    try:
        f.set_variation_by_name(weight)
    except Exception:
        pass
    return f


def mono(size):
    return ImageFont.truetype(FONT_MONO, size)


def text_w(draw, text, font, tracking=0.0):
    if not text:
        return 0.0
    return sum(draw.textlength(ch, font=font) for ch in text) + tracking * (len(text) - 1)


def tracked(draw, xy, text, font, fill, tracking=0.0, anchor="ls"):
    x, y = xy
    if "m" in anchor:  # centred horizontally
        x -= text_w(draw, text, font, tracking) / 2
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill, anchor=anchor)
        x += draw.textlength(ch, font=font) + tracking


# ---------------------------------------------------------------- sprites ---

RADIUS = 52
SHEEN = (255, 255, 255, 12)


def power_icon(d, cx, cy, r, color, width):
    d.arc([cx - r, cy - r, cx + r, cy + r], start=300, end=240, fill=color, width=width)
    d.line([cx, cy - r - width * 0.4, cx, cy + r * 0.05], fill=color, width=width)


def tap_icon(d, cx, cy, r, color, width):
    d.arc([cx - r, cy - r, cx + r, cy + r], start=205, end=335, fill=color, width=width)
    d.ellipse([cx - r * 0.22, cy - r * 0.22 + r * 0.25, cx + r * 0.22, cy + r * 0.22 + r * 0.25], fill=color)
    d.arc([cx - r * 1.5, cy - r * 1.5 + r * 0.25, cx + r * 1.5, cy + r * 1.5 + r * 0.25], 215, 325,
           fill=blend_on(SURFACE, color, 0.35), width=max(1, width - 2))


def card_sprite(w, h, painter, active=False):
    """A frosted tile at 2x with a baked shadow. Returns (image, margin)."""
    margin = 46
    cw, ch = w * S + margin * 2, h * S + margin * 2
    img = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))

    shadow = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [margin, margin + 12 * S, margin + w * S, margin + h * S + 12 * S],
        radius=RADIUS, fill=(0, 0, 0, 165),
    )
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(24)))

    d = ImageDraw.Draw(img)
    box = [margin, margin, margin + w * S, margin + h * S]
    d.rounded_rectangle(box, radius=RADIUS, fill=SURFACE + (255,),
                        outline=blend_on(SURFACE, ACCENT, 0.34) if active
                        else blend_on(SURFACE, (255, 255, 255), 0.09),
                        width=1 * S)

    painter(d, margin, margin, w * S, h * S)
    return img, margin


def paint_power(d, x, y, w, h):
    power_icon(d, x + 44 * S, y + 58 * S, 22 * S, MINT, 5 * S)
    d.rounded_rectangle([x + w - 128 * S, y + 46 * S, x + w - 44 * S, y + 72 * S],
                        radius=13 * S, fill=MINT)
    tracked(d, (x + 44 * S, y + 232 * S), "ON", display(66 * S), TEXT, 0)
    tracked(d, (x + 46 * S, y + 282 * S), "BOARD POWER", display(15 * S, "SemiBold"), TEXT_DIM, 2.6 * S)


def paint_level(d, x, y, w, h):
    tracked(d, (x + 44 * S, y + 56 * S), "LEVEL", display(15 * S, "SemiBold"), TEXT_DIM, 2.6 * S)
    r = 30 * S
    for cx, plus in ((x + 44 * S + r, False), (x + w - 44 * S - r, True)):
        d.ellipse([cx - r, y + 204 * S - r, cx + r, y + 204 * S + r],
                  fill=blend_on(SURFACE, (255, 255, 255), 0.08))
        d.line([cx - 10 * S, y + 204 * S, cx + 10 * S, y + 204 * S], fill=TEXT, width=3 * S)
        if plus:
            d.line([cx, y + 194 * S, cx, y + 214 * S], fill=TEXT, width=3 * S)
    f = mono(84 * S)
    d.text((x + w / 2 - d.textlength("3", font=f) / 2, y + 236 * S), "3", font=f, fill=TEXT,
           anchor="ls")


def paint_bright(d, x, y, w, h):
    tracked(d, (x + 44 * S, y + 52 * S), "BRIGHTNESS", display(15 * S, "SemiBold"), TEXT_DIM, 2.6 * S)
    pct = "64%"
    f = mono(24 * S)
    d.text((x + w - 44 * S - d.textlength(pct, font=f), y + 34 * S), pct, font=f, fill=ACCENT)

    ty, tx0, tx1 = y + 138 * S, x + 44 * S, x + w - 44 * S
    d.rounded_rectangle([tx0, ty - 5 * S, tx1, ty + 5 * S], radius=5 * S,
                        fill=blend_on(SURFACE, (255, 255, 255), 0.16))
    fill_x = tx0 + (tx1 - tx0) * 0.64
    d.rounded_rectangle([tx0, ty - 5 * S, fill_x, ty + 5 * S], radius=5 * S, fill=ACCENT)
    d.ellipse([fill_x - 24 * S, ty - 24 * S, fill_x + 24 * S, ty + 24 * S],
              fill=blend_on(SURFACE, ACCENT, 0.20))
    d.ellipse([fill_x - 14 * S, ty - 14 * S, fill_x + 14 * S, ty + 14 * S], fill=(255, 255, 255))


def paint_mode(d, x, y, w, h):
    tracked(d, (x + 44 * S, y + 52 * S), "FIELD MODE", display(15 * S, "SemiBold"), TEXT_DIM, 2.6 * S)
    labels = ["CALM", "FOCUS", "FLUX"]
    gap = 14 * S
    pw = (w - 88 * S - gap * 2) / 3
    for i, label in enumerate(labels):
        px = x + 44 * S + i * (pw + gap)
        box = [px, y + 96 * S, px + pw, y + 172 * S]
        if i == 0:
            d.rounded_rectangle(box, radius=38 * S, fill=ACCENT)
            col = INK
        else:
            d.rounded_rectangle(box, radius=38 * S, fill=blend_on(SURFACE, (255, 255, 255), 0.07))
            col = (200, 210, 225)
        tracked(d, ((box[0] + box[2]) / 2, y + 143 * S), label,
                display(18 * S, "Bold"), col, 2.4 * S, anchor="ms")


def paint_counter(d, x, y, w, h, value=0):
    r = 34 * S
    cx, cy = x + 44 * S + r, y + h / 2
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=blend_on(SURFACE, ACCENT, 0.16))
    d.ellipse([cx - r, cy - r, cx + r, cy + r],
              outline=blend_on(SURFACE, (255, 255, 255), 0.10), width=1 * S)
    tap_icon(d, cx, cy, 17 * S, ACCENT, 3 * S)

    tx = cx + r + 30 * S
    d.text((tx, cy + 6 * S), str(value), font=mono(56 * S), fill=TEXT, anchor="ls")
    tracked(d, (tx, cy + 46 * S), "AIR TAPS — DIP THE MAGNET TO THE GLASS",
            display(13 * S, "Medium"), TEXT_DIM, 1.2 * S)


PAINTERS = {
    "power": (paint_power, True),
    "level": (paint_level, False),
    "bright": (paint_bright, False),
    "mode": (paint_mode, False),
    "counter": (paint_counter, False),
}


def build_assets():
    tiles, tiles_1x = {}, {}
    for key, _, _, w, h in TILES:
        painter, active = PAINTERS[key]
        sprite, _ = card_sprite(w, h, painter, active=active)
        tiles[key] = sprite
        tiles_1x[key] = sprite.resize((sprite.width // S, sprite.height // S),
                                      Image.Resampling.LANCZOS)

    big, _ = card_sprite(984, COUNT_H,
                         lambda d, x, y, w, h: paint_counter(d, x, y, w, h, 1))
    tiles["counter_1"] = big
    tiles_1x["counter_1"] = big.resize((big.width // S, big.height // S),
                                       Image.Resampling.LANCZOS)

    dots = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dots)
    for gy in range(0, H + 40, 40):
        for gx in range(0, W + 40, 40):
            dd.ellipse([gx, gy, gx + 2, gy + 2], fill=(255, 255, 255, 16))

    # soft halo drawn behind the puck
    size = 520
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    for i in range(70, 0, -1):
        r = i * size / 140
        a = int(88 * (1 - i / 70) ** 2)
        hd.ellipse([size / 2 - r, size / 2 - r, size / 2 + r, size / 2 + r],
                   fill=rgba(ACCENT, a / 255))

    return tiles_1x, dots, halo


def background(pull_amount):
    """Dark board with two drifting glows, matching the app's background."""
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    grad = np.linspace(0.0, 1.0, H, dtype=np.float32)[:, None, None]
    top = np.array([12, 19, 33], np.float32)
    base = top * (1 - grad) + np.array(INK_DEEP, np.float32) * grad
    img = Image.fromarray(np.repeat(base, W, axis=1).astype(np.uint8), "RGB")

    for cx, cy, rad, colour, amount in (
        (W * 0.16, H * 0.07, 780, ACCENT, 0.14 + 0.22 * pull_amount),
        (W * 0.88, H * 0.80, 720, ACCENT_ALT, 0.10 + 0.12 * pull_amount),
    ):
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / rad
        a = np.clip(1 - d, 0, 1) ** 2.1 * amount
        layer = np.zeros((H, W, 4), np.uint8)
        layer[..., 0], layer[..., 1], layer[..., 2] = colour
        layer[..., 3] = (a * 255).astype(np.uint8)
        img.paste(Image.fromarray(layer, "RGBA"), (0, 0), Image.fromarray(layer, "RGBA"))
        del layer

    return img


# -------------------------------------------------------------- particles ---

_PARTICLES = None


def particle_seeds():
    global _PARTICLES
    if _PARTICLES is None:
        rng = np.random.default_rng(7)
        _PARTICLES = [
            (
                float(rng.random()), float(rng.random()),
                2.4 + float(rng.random()) * 3.4,
                float(rng.random()) * 0.52,
                float(rng.random()) * math.tau,
                0.22 + float(rng.random()) * 0.75,
            )
            for _ in range(88)
        ]
    return _PARTICLES


def draw_particles(d, t, presence_value):
    fx, fy, piled = focus_point(t)
    for (sx, sy, size, delay, phase, speed) in particle_seeds():
        hx = sx * W + math.sin(t * 0.35 + phase) * 14
        hy = sy * H + math.cos(t * 0.29 + phase * 1.7) * 11

        if presence_value <= 0.01:
            d.ellipse([hx - size * 0.55, hy - size * 0.55, hx + size * 0.55, hy + size * 0.55],
                      fill=rgba(ACCENT, 0.22))
            continue

        span = max(0.05, 1 - delay)
        u = min(1.0, max(0.0, (presence_value - delay) / span))
        u = u * u * (3 - 2 * u)

        spread = (46.0 if piled else 30.0) + 26.0 * (1 - delay)
        angle = phase + t * speed
        nx = fx + math.cos(angle) * spread
        ny = fy + math.sin(angle) * spread * 0.82

        px = hx + (nx - hx) * u
        py = hy + (ny - hy) * u
        radius = size * (0.85 + 0.95 * u)

        # Trail from where the particle was a moment ago (along the orbit, not
        # radially), so the stream reads as dust rather than a star burst.
        if u > 0.30:
            past = angle - 0.22 * speed
            qx = hx + (fx + math.cos(past) * spread - hx) * u
            qy = hy + (fy + math.sin(past) * spread * 0.82 - hy) * u
            d.line([qx, qy, px, py], fill=rgba(ACCENT, 0.22 * u), width=2)

        d.ellipse([px - radius, py - radius, px + radius, py + radius],
                  fill=rgba(mix(ACCENT, (255, 255, 255), 0.55 * u), 0.14 + 0.66 * u))


# ------------------------------------------------------------------ scene ---

def draw_pill(d, x, y, text, colour, font):
    w = text_w(d, text, font, 1.6) + 44
    d.rounded_rectangle([x, y, x + w, y + 42], radius=21, fill=rgba(colour, 0.13),
                        outline=rgba(colour, 0.30), width=1)
    d.ellipse([x + 17, y + 17, x + 27, y + 27], fill=colour + (255,))
    tracked(d, (x + 35, y + 27), text, font, colour, 1.6, anchor="ls")
    return w


def draw_header(d, presence_value):
    tracked(d, (PAD, 176), "MAGNET BOARD", display(46, "ExtraBold"), TEXT, 2.0)

    if presence_value > 0.05:
        subtitle = "MAGNET DETECTED · MOVE IT AROUND"
    else:
        subtitle = "HOLD A MAGNET NEAR THE TOP-LEFT OF THE PHONE"
    tracked(d, (PAD + 2, 214), subtitle, display(13, "SemiBold"), TEXT_DIM, 2.2)

    if presence_value > 0.55:
        label, colour = "MAGNET LOCKED", MINT
    elif presence_value > 0.05:
        label, colour = "TRACKING", ACCENT
    else:
        label, colour = "SEARCHING", TEXT_DIM

    font = display(11, "Bold")
    w = text_w(d, label, font, 1.6) + 44
    draw_pill(d, W - PAD - 52 - w, 132, label, colour, font)

    gx, gy, gr = W - PAD - 26, 153, 26
    d.ellipse([gx - gr, gy - gr, gx + gr, gy + gr], fill=(255, 255, 255, 16),
              outline=STROKE, width=1)
    for dy in (-7, 0, 7):
        d.line([gx - 11, gy + dy, gx + 11, gy + dy], fill=TEXT, width=2)


def draw_meter(d, presence_value):
    x0, x1, y = PAD, W - PAD, 252
    d.rounded_rectangle([x0, y - 3, x1, y + 3], radius=3, fill=(255, 255, 255, 16))
    if presence_value > 0.01:
        d.rounded_rectangle([x0, y - 3, x0 + (x1 - x0) * presence_value, y + 3],
                            radius=3, fill=ACCENT)


def dashed_line(d, p0, p1, width=2, dash=9, gap=9, alpha0=0.0, alpha1=0.55):
    x0, y0 = p0
    x1, y1 = p1
    length = math.hypot(x1 - x0, y1 - y0)
    if length < 1:
        return
    ux, uy = (x1 - x0) / length, (y1 - y0) / length
    pos = 0.0
    while pos < length:
        end = min(pos + dash, length)
        a = lerp(alpha0, alpha1, pos / length)
        d.line([x0 + ux * pos, y0 + uy * pos, x0 + ux * end, y0 + uy * end],
               fill=rgba(ACCENT, a), width=width)
        pos = end + gap


def dashed_circle(d, cx, cy, r, colour, alpha, dashes=18, width=1):
    if r <= 0:
        return
    step = 360.0 / dashes
    for i in range(dashes):
        start = i * step
        d.arc([cx - r, cy - r, cx + r, cy + r], start=start, end=start + step * 0.55,
              fill=rgba(colour, alpha), width=width)


_GLOW_MASK = None


def glow_mask():
    """A smooth radial falloff, resized per use: faster and smoother than rings."""
    global _GLOW_MASK
    if _GLOW_MASK is None:
        n = 192
        yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
        c = (n - 1) / 2
        r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / (n / 2)
        a = np.clip(1 - r, 0, 1) ** 2.0
        _GLOW_MASK = Image.fromarray((a * 255).astype(np.uint8), "L")
    return _GLOW_MASK


def blit_glow(img, cx, cy, rx, ry, colour, strength):
    if strength <= 0.01:
        return
    w, h = max(2, int(rx * 2)), max(2, int(ry * 2))
    mask = glow_mask().resize((w, h), Image.BILINEAR)
    mask = mask.point(lambda v: int(v * min(1.0, strength) * 0.5))
    layer = Image.new("RGB", (w, h), colour)
    img.paste(layer, (int(cx - w / 2), int(cy - h / 2)), mask)


def draw_beam_and_puck(img, d, pos, presence_value, halo, t):
    if presence_value <= 0.01:
        return
    x = min(max(pos[0], 14.0), W - 14.0)
    y = min(max(pos[1], 14.0), H - 14.0)

    halo_size = int(460 * (0.75 + 0.35 * presence_value))
    h = halo.resize((halo_size, halo_size), Image.BILINEAR)
    img.paste(h, (int(x - halo_size / 2), int(y - halo_size / 2)), h)

    dashed_line(d, SENSOR, (x, y), alpha1=0.5 * presence_value)
    dashed_circle(d, x, y, 46, ACCENT, 0.22 * presence_value, dashes=16)
    dashed_circle(d, x, y, 92, ACCENT, 0.10 * presence_value, dashes=22)

    pulse = 1 + 0.10 * math.sin(t * 6.0)
    d.ellipse([x - 21 * pulse, y - 21 * pulse, x + 21 * pulse, y + 21 * pulse],
              outline=rgba(ACCENT, 0.9 * presence_value), width=2)
    d.ellipse([x - 10, y - 10, x + 10, y + 10],
              fill=rgba((255, 255, 255), 0.95 * presence_value))

    d.text((x + 34, y - 30), f"{height_cm(t):.1f} cm", font=mono(15),
           fill=rgba(ACCENT, 0.95 * presence_value))


def draw_ripples(d, pos, age):
    if age < 0 or age > 1.2:
        return
    for delay in (0.0, 0.12, 0.24):
        a = age - delay
        if a <= 0 or a > 0.85:
            continue
        u = a / 0.85
        r = 26 + 220 * smooth(u)
        d.ellipse([pos[0] - r, pos[1] - r, pos[0] + r, pos[1] + r],
                  outline=rgba(ACCENT, (1 - u) ** 1.2 * 0.95), width=4)


def draw_tiles(img, d, pos, presence_value, tiles, t):
    for key, x, y, w, h in TILES:
        cx, cy = x + w / 2, y + h / 2
        dx, dy = pos[0] - cx, pos[1] - cy
        dist = max(1.0, math.hypot(dx, dy))
        near = max(0.0, 1 - dist / REACH)
        influence = presence_value * near * near
        ux, uy = dx / dist, dy / dist

        ox, oy = ux * influence * TRAVEL, uy * influence * TRAVEL
        lean = ux * TILT * influence

        blit_glow(img, cx + ox, cy + oy, w * 0.72, h * 0.95, ACCENT, influence)

        sprite_key = "counter_1" if (key == "counter" and t >= TAP_T) else key
        sprite = tiles[sprite_key]
        if abs(lean) > 0.05:
            rotated = sprite.rotate(-lean, resample=Image.Resampling.BICUBIC, expand=True)
        else:
            rotated = sprite
        img.paste(rotated, (int(cx + ox - rotated.width / 2),
                            int(cy + oy - rotated.height / 2)), rotated)


def draw_hud(d, t, presence_value, pull_value):
    x, y, w, h = PAD, HUD_Y, 984, HUD_H
    d.rounded_rectangle([x, y, x + w, y + h], radius=26, fill=SURFACE + (236,),
                        outline=STROKE, width=1)

    spread = 9 + (1 - presence_value) * 16
    cols = [
        ("PRESENCE", f"{presence_value * 100:.0f}", "%"),
        ("DISTANCE", f"{distance_cm(t):.1f}", "cm"),
        ("HEIGHT", f"{height_cm(t):.1f}", "cm"),
        ("SPREAD", f"{spread:.0f}", "pt"),
    ]
    colw = (w - 56) / 4
    for i, (label, value, unit) in enumerate(cols):
        cx = x + 28 + i * colw
        vf, uf, lf = mono(30), display(11, "SemiBold"), display(9, "Bold")
        d.text((cx, y + 30), value, font=vf, fill=TEXT)
        d.text((cx + d.textlength(value, font=vf) + 5, y + 46), unit, font=uf, fill=TEXT_DIM)
        tracked(d, (cx, y + 76), label, lf, TEXT_DIM, 1.6)

    py, px0, px1 = y + 118, x + 28, x + w - 28
    tracked(d, (px0, py + 5), "PULL", display(9, "Bold"), TEXT_DIM, 1.6)
    bar0, bar1 = px0 + 52, px1 - 56
    d.rounded_rectangle([bar0, py, bar1, py + 6], radius=3, fill=(255, 255, 255, 18))
    d.rounded_rectangle([bar0, py, bar0 + (bar1 - bar0) * pull_value, py + 6], radius=3, fill=ACCENT)
    pct = f"{pull_value * 100:.0f}%"
    d.text((px1 - d.textlength(pct, font=mono(13)), py - 5), pct, font=mono(13), fill=TEXT)

    ey = y + 176
    tracked(d, (x + 28, ey), "EVENT", display(9, "Bold"), TEXT_DIM, 1.6)
    if t >= YANK_T:
        event, colour = "PULLED AWAY", WARM
    elif t >= TAP_T:
        event, colour = "AIR TAP", ACCENT
    else:
        event, colour = "—", TEXT_DIM
    tracked(d, (x + 92, ey), event, display(12, "Bold"), colour, 1.4)

    badge = "LOCKED" if presence_value > 0.5 else "SEARCHING"
    badge_colour = MINT if presence_value > 0.5 else TEXT_DIM
    bf = display(9, "Bold")
    bw = text_w(d, badge, bf, 1.4) + 24
    d.rounded_rectangle([x + w - 28 - bw, ey - 13, x + w - 28, ey + 9], radius=11,
                        fill=rgba(badge_colour, 0.14))
    tracked(d, (x + w - 28 - bw + 12, ey), badge, bf, badge_colour, 1.4)

    tracked(d, (x + 28, y + h - 34), "MAGNET.MFXL · ON DEVICE · NO NETWORK",
            display(8.5, "Medium"), (90, 104, 126), 1.6)


def draw_banner(d, label, detail, alpha):
    if alpha <= 0.01:
        return
    lf, df = display(13, "ExtraBold"), display(11, "Medium")
    tw = text_w(d, label, lf, 2.0)
    dw = text_w(d, detail, df, 0.6)
    bw = max(tw, dw) + 76
    x0 = (W - bw) / 2
    y0, y1 = 1770, 1832
    d.rounded_rectangle([x0, y0, x0 + bw, y1], radius=31,
                        fill=rgba(INK, 0.92 * alpha), outline=rgba(ACCENT, 0.35 * alpha), width=1)
    d.ellipse([x0 + 24, y0 + 26, x0 + 36, y0 + 38], fill=rgba(ACCENT, alpha))
    tracked(d, (x0 + 50, y0 + 28), label, lf, rgba(ACCENT, alpha), 2.0)
    tracked(d, (x0 + 50, y0 + 48), detail, df, rgba((200, 214, 232), 0.8 * alpha), 0.6)


def draw_intro(img, d, t):
    if t > 2.45:
        return
    scrim = 1 - smooth((t - 1.72) / 0.62)
    if scrim > 0.002:
        veil = Image.new("RGBA", (W, H), (3, 5, 10, int(255 * scrim)))
        img.paste(veil, (0, 0), veil)

    fade_in = smooth(t / 0.45)
    fade_out = 1 - smooth((t - 1.42) / 0.34)
    a = fade_in * fade_out
    if a <= 0.01:
        return

    rise = (1 - fade_in) * 26
    blit_glow(img, W / 2, 830, 420, 240, ACCENT, 0.45 * a)

    tracked(d, (W / 2, 880 - rise), "MAGNET BOARD", display(72, "ExtraBold"),
            rgba(TEXT, a), 3.4, anchor="ms")
    tracked(d, (W / 2, 952 - rise), "AN INTERFACE THAT FEELS A MAGNET",
            display(16, "SemiBold"), rgba(TEXT_DIM, a), 3.0, anchor="ms")

    d.rounded_rectangle([W / 2 - 60, 1010 - rise, W / 2 + 60, 1014 - rise], radius=2,
                        fill=rgba(ACCENT, 0.55 * a))

    tracked(d, (W / 2, 1070 - rise), "SWIFTUI · IOS 17 · MAGNETKIT",
            display(12, "Medium"), rgba((120, 136, 160), a), 2.4, anchor="ms")


OUTRO = [
    ("MAGNET BOARD", display(64, "ExtraBold"), TEXT, 3.0, 872, 0.0),
    ("AN INTERFACE THAT FEELS A MAGNET", display(17, "SemiBold"), TEXT_DIM, 3.0, 940, 0.06),
    ("MAGNETIC UI · MAGNETKIT BY LIBRARIES.DEV", display(13, "Medium"), (132, 148, 172), 2.4, 1032, 0.16),
    ("GITHUB.COM/1UCENT/MAGNETBOARD", mono(15), ACCENT, 0.8, 1074, 0.22),
    ("CODE MIT · MODEL UNDER THE LIBRARIES.DEV MODEL LICENSE", display(11, "Medium"),
     (96, 110, 134), 1.8, 1126, 0.30),
]


def draw_outro(img, d, t):
    if t < OUTRO_T:
        return
    scrim = 0.94 * smooth((t - OUTRO_T) / 0.5)
    if scrim > 0.002:
        veil = Image.new("RGBA", (W, H), (3, 5, 10, int(255 * scrim)))
        img.paste(veil, (0, 0), veil)

    if t < OUTRO_T + 0.25:
        return
    blit_glow(img, W / 2, 840, 460, 250, ACCENT, 0.55 * scrim * 0.9)

    for text, font, colour, tracking, y, delay in OUTRO:
        a = smooth((t - (OUTRO_T + 0.15 + delay)) / 0.42)
        if a <= 0.01:
            continue
        rise = (1 - a) * 22
        fill = colour + (int(255 * a),) if len(colour) == 3 else colour
        tracked(d, (W / 2, y - rise), text, font, fill, tracking, anchor="ms")

    # thin accent rule between the tagline and the credits
    a = smooth((t - (OUTRO_T + 0.3)) / 0.4)
    if a > 0.01:
        d.rounded_rectangle([W / 2 - 56, 980, W / 2 + 56, 983], radius=1,
                            fill=rgba(ACCENT, 0.5 * a))

    if t > 14.35:
        veil = Image.new("RGBA", (W, H), (2, 4, 8, int(255 * smooth((t - 14.35) / 0.62))))
        img.paste(veil, (0, 0), veil)


# ------------------------------------------------------------------ frame ---

def banner_alpha(t, start, length=1.15):
    u = t - start
    if u < 0 or u > length:
        return 0.0
    return smooth(u / 0.10) * (1 - smooth((u - (length - 0.28)) / 0.28))


def render_frame(t, ctx):
    pos = puck_pos(t)
    pres = presence(t)
    pull_value = pull(t)

    bucket = max(0, min(len(ctx["bg"]) - 1, int(round(pull_value * (len(ctx["bg"]) - 1)))))
    img = ctx["bg"][bucket].copy()
    img.paste(ctx["dots"], (0, 0), ctx["dots"])

    d = ImageDraw.Draw(img, "RGBA")

    if t > 1.72:
        board = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        bd = ImageDraw.Draw(board, "RGBA")
        draw_header(bd, pres)
        draw_meter(bd, pres)
        draw_tiles(board, bd, pos, pres, ctx["tiles"], t)
        bd = ImageDraw.Draw(board, "RGBA")
        draw_hud(bd, t, pres, pull_value)

        strength, anchor, edge = gather_state(t)
        if strength > 0.01 and anchor:
            scale = 1 - 0.38 * strength
            small = board.resize((max(1, int(W * scale)), max(1, int(H * scale))),
                                 Image.BILINEAR)
            ox = anchor[0] - anchor[0] * scale
            oy = anchor[1] - anchor[1] * scale
            if edge == "left":
                ox -= 16 * strength
            elif edge == "right":
                ox += 16 * strength
            elif edge == "top":
                oy -= 14 * strength
            else:
                oy += 14 * strength
            img.paste(small, (int(ox), int(oy)), small)
        else:
            img.paste(board, (0, 0), board)

        d = ImageDraw.Draw(img, "RGBA")
        draw_particles(d, t, pres)

    draw_beam_and_puck(img, d, pos, pres, ctx["halo"], t)
    draw_ripples(d, pos, t - TAP_T)

    tap_a = banner_alpha(t, TAP_T, 1.1)
    if tap_a > 0:
        draw_banner(d, "AIR TAP", "1 total", tap_a)

    yank_a = banner_alpha(t, YANK_T, 1.0)
    if yank_a > 0:
        draw_banner(d, "PULLED AWAY", "48 cm/s", yank_a)

    draw_intro(img, d, t)
    draw_outro(img, d, t)
    return img


# ------------------------------------------------------------------ audio ---

SR = 48000


def click(freq=1900.0, dur=0.06, gain=0.5, noise=0.35, seed=0):
    n = int(dur * SR)
    t = np.arange(n) / SR
    body = (np.sin(2 * np.pi * freq * t) * np.exp(-t / 0.010)
            + 0.45 * np.sin(2 * np.pi * freq * 2.71 * t) * np.exp(-t / 0.005)
            + 0.22 * np.sin(2 * np.pi * freq * 0.5 * t) * np.exp(-t / 0.020))
    rng = np.random.default_rng(seed)
    nz = np.diff(rng.standard_normal(n), prepend=0.0) * np.exp(-t / 0.0035)
    return gain * (body + noise * nz) * np.clip(t / 0.0008, 0, 1)


def thump(freq=110.0, dur=0.35, gain=0.4):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * freq * t * (1 - 0.22 * t / dur))
    return gain * tone * np.exp(-t / 0.09) * np.clip(t / 0.004, 0, 1)


def whoosh(dur=0.5, gain=0.2, up=False, seed=3):
    n = int(dur * SR)
    rng = np.random.default_rng(seed)
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    chunk = 256
    for i in range(0, n, chunk):
        u = i / max(1, n)
        k = max(6, int(lerp(240, 18, 1 - u if up else u)))
        lo = max(0, i - k)
        seg = noise[lo:i + chunk]
        sm = np.convolve(seg, np.ones(k) / k, mode="same")
        out[i:i + chunk] = sm[-min(chunk, n - i):]
    env = np.sin(np.linspace(0, np.pi, n)) ** 2.2
    return gain * out * env * 5.0


def chime(freq, dur=1.2, gain=0.22):
    n = int(dur * SR)
    t = np.arange(n) / SR
    tone = (np.sin(2 * np.pi * freq * t)
            + 0.40 * np.sin(2 * np.pi * freq * 2.0 * t)
            + 0.18 * np.sin(2 * np.pi * freq * 3.01 * t))
    return gain * tone * np.exp(-t / 0.20) * np.clip(t / 0.003, 0, 1)


def add(buf, sig, at, pan=0.0, gain=1.0):
    i = int(round(at * SR))
    n = len(sig)
    if i >= buf.shape[0] or i + n <= 0:
        return
    s, e = max(0, i), min(buf.shape[0], i + n)
    seg = sig[s - i:e - i] * gain
    buf[s:e, 0] += seg * math.cos((pan + 1) * math.pi / 4)
    buf[s:e, 1] += seg * math.sin((pan + 1) * math.pi / 4)


def tile_ticks():
    """When the puck first sweeps near each tile: the clicks the UI 'feels'."""
    events, last = [], -9.0
    inside = {key: False for key, *_ in TILES}
    t = 2.2
    while t < YANK_T:
        x, y = puck_pos(t)
        for key, tx, ty, tw, th in TILES:
            d = math.hypot(x - (tx + tw / 2), y - (ty + th / 2))
            hit = d < 300
            if hit and not inside[key] and t - last > 0.22:
                events.append(t)
                last = t
            inside[key] = hit
        t += 1 / 60
    return events


def build_audio(path):
    n = int(DURATION * SR)
    buf = np.zeros((n, 2), np.float32)

    # intro ticks
    add(buf, click(2100, 0.05, 0.20, 0.3, 1), 0.18, -0.15)
    add(buf, click(1750, 0.045, 0.16, 0.3, 2), 0.62, 0.2)
    add(buf, click(2450, 0.04, 0.14, 0.3, 3), 1.08, -0.2)
    add(buf, whoosh(0.75, 0.15, up=True, seed=7), 1.40)
    add(buf, thump(120, 0.40, 0.26), 1.52)

    # magnet arrives, then ticks as it sweeps the tiles
    add(buf, click(1500, 0.07, 0.26, 0.4, 4), 2.16, -0.2)
    for i, at in enumerate(tile_ticks()):
        add(buf, click(2500 + (i % 3) * 240, 0.035, 0.14, 0.55, 10 + i), at,
            0.3 if i % 2 else -0.3)

    # air tap: click-clack, a low thump and a ringing tick
    add(buf, click(1900, 0.05, 0.44, 0.5, 20), TAP_T)
    add(buf, click(2650, 0.05, 0.30, 0.6, 21), TAP_T + 0.035)
    add(buf, thump(155, 0.30, 0.28), TAP_T)
    add(buf, click(3400, 0.35, 0.09, 0.2, 22), TAP_T + 0.02, 0.12)

    # yanked away
    add(buf, whoosh(0.55, 0.20, seed=8), YANK_T + 0.02)
    add(buf, thump(90, 0.50, 0.20), YANK_T + 0.05)

    # outro: three clicky notes
    for i, (freq, at) in enumerate(((659.25, OUTRO_T + 0.24),
                                    (987.77, OUTRO_T + 0.38),
                                    (1318.51, OUTRO_T + 0.52))):
        pan = (-0.25, 0.0, 0.25)[i]
        add(buf, chime(freq, 1.6, 0.20), at, pan)
        add(buf, click(freq * 1.2, 0.035, 0.16, 0.4, 40 + i), at, pan)

    buf = np.tanh(buf * 1.3)
    peak = float(np.abs(buf).max()) or 1.0
    buf *= 0.89 / peak

    fade = int(0.06 * SR)
    buf[:fade] *= np.linspace(0, 1, fade)[:, None]
    fade = int(0.6 * SR)
    buf[-fade:] *= np.linspace(1, 0, fade)[:, None]

    pcm = (np.clip(buf, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------- main ---

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stills", action="store_true", help="write review PNGs instead")
    ap.add_argument("--out", default=os.path.join(PROMO_DIR, "magnetboard-promo.webm"))
    ap.add_argument("--crf", type=int, default=32)
    args = ap.parse_args()

    os.makedirs(PROMO_DIR, exist_ok=True)
    print("building board…")
    tiles, dots, halo = build_assets()
    ctx = {
        "tiles": tiles,
        "dots": dots,
        "halo": halo,
        "bg": [background(i / 8) for i in range(9)],
    }

    if args.stills:
        out = os.path.join(PROMO_DIR, "stills")
        os.makedirs(out, exist_ok=True)
        for t in (0.9, 3.2, 5.0, 8.30, 9.60, 10.05, 12.4):
            render_frame(t, ctx).save(os.path.join(out, f"still-{t:05.2f}.png"))
        print("stills:", out)
        return

    work = tempfile.mkdtemp(prefix="magnetboard-promo-")
    wav = os.path.join(work, "audio.wav")
    silent = os.path.join(work, "video.webm")

    print("synthesising audio…")
    build_audio(wav)

    total = int(DURATION * FPS)
    print(f"rendering {total} frames…")
    cmd = [
        "ffmpeg", "-y", "-loglevel", "error",
        "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
        "-c:v", "libvpx-vp9", "-crf", str(args.crf), "-b:v", "0",
        "-row-mt", "1", "-cpu-used", "3", "-deadline", "good",
        "-pix_fmt", "yuv420p", silent,
    ]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    try:
        for i in range(total):
            proc.stdin.write(render_frame(i / FPS, ctx).tobytes())
            if i % 45 == 0:
                print(f"  {i}/{total}", flush=True)
    finally:
        proc.stdin.close()
    if proc.wait() != 0:
        sys.exit("video encode failed")

    print("muxing…")
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", silent, "-i", wav,
         "-c:v", "copy", "-c:a", "libopus", "-b:a", "128k", "-shortest", args.out],
        check=True,
    )
    size = os.path.getsize(args.out)
    print(f"wrote {args.out} ({size / 1024 / 1024:.1f} MB)")


if __name__ == "__main__":
    main()
