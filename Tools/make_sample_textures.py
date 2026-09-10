#!/usr/bin/env python3
"""Draw the sample's textures.

**The sample has no asset dependency and this keeps it that way** — like the sounds and the figure's
rig, the textures are generated rather than downloaded, so cloning this repository is enough to build
and run it.

Pure standard library: PNG is a handful of chunks around a zlib stream, and taking a dependency on an
imaging library to draw four flat patterns would cost the reader more than it saves.

They are deliberately plain — planks, blocks, grain, a grid. A sample with good art teaches the
reader about the art.

Run:  python3 Tools/make_sample_textures.py
Writes Sources/WindageSample/Resources/*.png
"""
import math, pathlib, struct, zlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/WindageSample/Resources"
SIZE = 256


def write_png(path, pixels):
    """`pixels` is a list of rows, each a list of (r, g, b) 0-255."""
    raw = b"".join(b"\x00" + bytes(v for px in row for v in px) for row in pixels)

    def chunk(kind, payload):
        body = kind + payload
        return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", len(pixels[0]), len(pixels), 8, 2, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", header)
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))
    print("wrote %s (%d bytes)" % (path.name, path.stat().st_size))


def noise(x, y, seed, scale=1.0):
    """A cheap deterministic hash. Not good noise — good enough to break up a flat colour, and it
    gives the same texture on every machine, which matters more here than the quality does."""
    n = (x * 374761393 + y * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    n = (n ^ (n >> 13)) * 1274126177 & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0 * scale


def shade(base, amount):
    return tuple(max(0, min(255, int(c * amount))) for c in base)


def crate():
    """Planks with dark gaps, so a rotated crate reads as rotated."""
    rows = []
    for y in range(SIZE):
        row = []
        plank = y * 5 // SIZE
        for x in range(SIZE):
            base = (176, 132, 84)
            tone = 0.86 + 0.14 * noise(x // 2, y // 2, plank)
            # Gaps between planks, and a border so the crate has visible edges.
            if (y * 5) % SIZE < 6 or x < 5 or x > SIZE - 6 or y < 5 or y > SIZE - 6:
                tone *= 0.55
            # A lengthways grain streak.
            tone *= 1 + 0.05 * math.sin(x * 0.35 + plank * 2)
            row.append(shade(base, tone))
        rows.append(row)
    return rows


def stone():
    """Coursed blocks, offset row to row."""
    rows = []
    course_height = SIZE // 6
    for y in range(SIZE):
        row = []
        course = y // course_height
        offset = (course % 2) * (SIZE // 8)
        for x in range(SIZE):
            base = (150, 149, 143)
            block = ((x + offset) // (SIZE // 4), course)
            tone = 0.82 + 0.22 * noise(block[0], block[1], 7)
            tone *= 0.94 + 0.06 * noise(x // 3, y // 3, 11)
            if y % course_height < 3 or (x + offset) % (SIZE // 4) < 3:
                tone *= 0.62                       # mortar
            row.append(shade(base, tone))
        rows.append(row)
    return rows


def ground():
    """Dry earth with a faint metre grid, so distance and scale are readable while walking."""
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            base = (124, 126, 108)
            tone = 0.88 + 0.16 * noise(x // 2, y // 2, 3)
            tone *= 0.97 + 0.03 * math.sin(x * 0.08) * math.sin(y * 0.08)
            # A faint metre grid, since the UVs are in metres — it gives the eye something to judge
            # distance by on an otherwise featureless plane. Faint on purpose: at 0.9 it reads as a
            # wireframe rather than as ground.
            if x < 2 or y < 2:
                tone *= 0.96
            row.append(shade(base, tone))
        rows.append(row)
    return rows


def figure():
    """Wood grain for the mannequin, banded so a bending limb shows the bend."""
    rows = []
    for y in range(SIZE):
        row = []
        for x in range(SIZE):
            base = (198, 164, 122)
            grain = 0.5 + 0.5 * math.sin(y * 0.6 + 2.2 * math.sin(y * 0.05) + noise(x // 8, y, 5) * 2)
            tone = 0.84 + 0.16 * grain
            tone *= 0.95 + 0.05 * noise(x, y // 4, 17)
            row.append(shade(base, tone))
        rows.append(row)
    return rows


if __name__ == "__main__":
    for name, draw in (("crate", crate), ("stone", stone), ("ground", ground), ("figure", figure)):
        write_png(OUT / ("%s.png" % name), draw())
