#!/usr/bin/env python3
"""Build the sample's turntable: a low stone disc, 4 m across and 0.2 m tall, standing on y = 0.

**Round, and that is for collision.** The controller sees a solid as its world-aligned box, and a
turning square's box swells by 41% at 45° — a body could stand on air past the corners. A disc's box
is the same at every angle. Twenty-four sides: round to the eye at the sample's distances, and still
faceted like everything else here.

**0.2 m tall, under the 0.45 m step**, so it is walked onto rather than climbed.

UVs in metres like step.obj, so the stone is the same size on both. Faceted: every face owns its
corners and its normal.

Run:  python3 Tools/make_sample_turntable.py
Writes Sources/WindageSample/Resources/turntable.obj and turntable.mtl
"""
import math, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/WindageSample/Resources"
SIDES, RADIUS, HEIGHT = 24, 2.0, 0.2


def build():
    v, vt, vn, faces = [], [], [], []

    def face(corners, uvs, normal):
        vn.append(normal)
        n = len(vn)
        idx = []
        for p, uv in zip(corners, uvs):
            v.append(p)
            vt.append(uv)
            idx.append((len(v), len(vt), n))
        faces.append(idx)

    ring = [(RADIUS * math.cos(2 * math.pi * i / SIDES), RADIUS * math.sin(2 * math.pi * i / SIDES))
            for i in range(SIDES)]
    for i in range(SIDES):
        (x0, z0), (x1, z1) = ring[i], ring[(i + 1) % SIDES]
        # The top, as a fan from the centre — counter-clockwise from above, facing up.
        face([(0, HEIGHT, 0), (x1, HEIGHT, z1), (x0, HEIGHT, z0)],
             [(0, 0), (x1, z1), (x0, z0)], (0, 1, 0))
        # The side, facing out.
        mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
        length = math.hypot(mx, mz)
        u0 = RADIUS * 2 * math.pi * i / SIDES
        u1 = RADIUS * 2 * math.pi * (i + 1) / SIDES
        face([(x0, 0, z0), (x0, HEIGHT, z0), (x1, HEIGHT, z1), (x1, 0, z1)],
             [(u0, 0), (u0, HEIGHT), (u1, HEIGHT), (u1, 0)], (mx / length, 0, mz / length))
    return v, vt, vn, faces


def write():
    v, vt, vn, faces = build()
    lines = ["# the sample's turntable: a 24-sided stone disc, 4 m across and 0.2 m tall, standing on y = 0.",
             "# Written by Tools/make_sample_turntable.py — round so its box does not swell as it turns.",
             "mtllib turntable.mtl", "usemtl stone"]
    lines += ["v %.5f %.5f %.5f" % p for p in v]
    lines += ["vt %.5f %.5f" % t for t in vt]
    lines += ["vn %.5f %.5f %.5f" % n for n in vn]
    lines += ["f " + " ".join("%d/%d/%d" % c for c in f) for f in faces]
    (OUT / "turntable.obj").write_text("\n".join(lines) + "\n")
    (OUT / "turntable.mtl").write_text(
        "# The surface for turntable.obj: the same cut stone as the steps.\n"
        "# **`bump`, not `map_Bump`** — Model I/O's OBJ reader recognises only this spelling.\n"
        "newmtl stone\nKd 1 1 1\nKs 0 0 0\nNs 6\nmap_Kd stone.png\nbump stone_normal.png\n")
    print("wrote turntable.obj — %d faces" % len(faces))


if __name__ == "__main__":
    write()
