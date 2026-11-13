#!/usr/bin/env python3
"""Generate the MagnetBoard app icon (1024x1024 PNG, no dependencies)."""

import math
import struct
import zlib

S = 1024
BG_IN = (0.080, 0.110, 0.200)
BG_OUT = (0.008, 0.014, 0.028)
CYAN = (0.350, 0.870, 0.980)
WARM = (1.000, 0.450, 0.360)
STEEL = (0.905, 0.925, 0.960)


def clamp01(x):
    return 0.0 if x < 0.0 else 1.0 if x > 1.0 else x


def mix(a, b, t):
    t = clamp01(t)
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def rounded_box(px, py, x0, y0, x1, y1, r):
    """Signed distance to a rounded rectangle (negative inside)."""
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - r, (y1 - y0) / 2 - r
    qx = abs(px - cx) - hx
    qy = abs(py - cy) - hy
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return outside + inside - r


def coverage(d):
    """1px antialiased coverage from a signed distance."""
    return clamp01(0.5 - d)


def main():
    rows = []
    for y in range(S):
        row = bytearray()
        for x in range(S):
            px, py = x + 0.5, y + 0.5

            # Background: soft radial light from the upper middle.
            t = math.hypot((px - 512) / 760, (py - 360) / 760)
            r, g, b = mix(BG_IN, BG_OUT, t * 1.15)
            vig = 1.0 - 0.35 * (math.hypot(px - 512, py - 512) / 724) ** 2
            r, g, b = r * vig, g * vig, b * vig

            # Halo behind the magnet.
            d_halo = math.hypot(px - 512, py - 520) / 300
            halo = max(0.0, 1.0 - d_halo) ** 2 * 0.55
            r, g, b = mix((r, g, b), (0.10, 0.28, 0.38), halo)

            # Horseshoe: two legs plus the lower half of a ring.
            leg_top, leg_bottom, leg_w = 296, 596, 100
            leg_r = leg_w / 2
            left_leg = rounded_box(px, py, 512 - 216 - leg_r, leg_top, 512 - 216 + leg_r, leg_bottom, leg_r)
            right_leg = rounded_box(px, py, 512 + 216 - leg_r, leg_top, 512 + 216 + leg_r, leg_bottom, leg_r)

            dcx, dcy = px - 512, py - 520
            dist = math.hypot(dcx, dcy)
            ring = abs(dist - 168) - 50  # annulus, 100 thick
            ring = max(ring, 520 - py)   # keep the lower half only
            body = min(left_leg, right_leg, ring)

            cov = coverage(body)
            if cov > 0:
                # Pole tips on the two legs, steel elsewhere.
                tip = 108.0
                if py < leg_top + tip:
                    band = clamp01((py - leg_top) / tip)  # 0 at the tip, 1 at the steel
                    poll = mix(CYAN, STEEL, band) if px < 512 else mix(WARM, STEEL, band)
                    r, g, b = mix((r, g, b), poll, cov)
                else:
                    shade = 0.82 + 0.18 * max(0.0, 1.0 - (py - 500) / 320)
                    r, g, b = mix((r, g, b), tuple(c * shade for c in STEEL), cov)

                # A soft rim so the shape sits in the dark.
                rim = clamp01(1.0 - abs(body + 6) / 8) * 0.5
                r, g, b = mix((r, g, b), (0.02, 0.04, 0.07), rim * 0.6)

            row += bytes((
                int(clamp01(r) * 255),
                int(clamp01(g) * 255),
                int(clamp01(b) * 255),
                255,
            ))
        rows.append(bytes(row))

    raw = b"".join(b"\x00" + row for row in rows)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", S, S, 8, 6, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(raw, 9))
           + chunk(b"IEND", b""))

    out = "MagnetBoard/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
    with open(out, "wb") as handle:
        handle.write(png)
    print("wrote", out, len(png), "bytes")


if __name__ == "__main__":
    main()
