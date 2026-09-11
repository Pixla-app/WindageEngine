#!/usr/bin/env python3
"""Build the sample's brazier: an iron bowl on a post, with a bed of glowing coals.

**USD rather than OBJ, and that is forced rather than chosen.** The brazier's coals glow from an
emissive map, and Model I/O reads no emission from an OBJ at all — `Ke` and `map_Ke` are both
discarded (measured; see the README's section on emission). USD's `emissiveColor`, connected to a
texture, arrives. So the one level object that makes its own light is the one that cannot be an OBJ.

One mesh and one material, over a texture split down the middle: iron on the left half, coals on the
right. **One submesh because the sample writes its uniforms per drawable** — a second material would
get the first one's numbers, which the sample says out loud where it draws.

Faceted, like the figure: every face owns its corners, so every normal is the face's and every
primvar is "vertex". Metres, Y up, the origin at the middle of the base.

Run:  python3 Tools/make_sample_brazier.py
Writes Sources/WindageSample/Resources/brazier.usda and brazier*.png
"""
import math, os, pathlib, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from make_sample_textures import write_png, noise, SIZE  # noqa: E402

OUT = pathlib.Path(__file__).resolve().parent.parent / "Sources/WindageSample/Resources"

SEGMENTS = 12
BASE_RADIUS, BASE_HEIGHT = 0.22, 0.04
POST_RADIUS, POST_TOP = 0.035, 0.80
BOWL_BOTTOM, BOWL_TOP = 0.78, 1.08
BOWL_LOW_RADIUS, BOWL_HIGH_RADIUS = 0.10, 0.30
WALL = 0.018
COALS_HEIGHT, COALS_DOME = 0.97, 0.035

# **The rim is what the level's lamp is placed against.** Kept here, named, because the level file puts
# the lamp's light half a metre above it and the sample throws embers from it; a brazier made taller
# without moving those would have a lamp inside its bowl.
RIM = BOWL_TOP


def ring(radius, y, segments=SEGMENTS):
    return [(radius * math.cos(2 * math.pi * i / segments), y, radius * math.sin(2 * math.pi * i / segments))
            for i in range(segments)]


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    length = math.sqrt(a[0] ** 2 + a[1] ** 2 + a[2] ** 2)
    return (a[0] / length, a[1] / length, a[2] / length) if length > 1e-9 else (0.0, 1.0, 0.0)


def iron_uv(p):
    """Cylindrical, squeezed into the left half of the texture."""
    angle = (math.atan2(p[2], p[0]) / (2 * math.pi)) % 1.0
    return (0.02 + 0.46 * angle, 0.02 + 0.96 * (p[1] / BOWL_TOP))


def coal_uv(p, radius):
    """Planar from above, in the right half."""
    return (0.75 + 0.23 * p[0] / radius, 0.5 + 0.46 * p[2] / radius)


def build():
    points, normals, uvs, counts, indices = [], [], [], [], []

    def emit(corners, uv_of):
        """Counter-clockwise seen from outside, which is the winding the sample's pipeline culls by."""
        n = norm(cross(sub(corners[1], corners[0]), sub(corners[-1], corners[0])))
        counts.append(len(corners))
        for p in corners:
            indices.append(len(points))
            points.append(p)
            normals.append(n)
            uvs.append(uv_of(p))

    def band(lower, upper, uv_of, flip=False):
        """Quads between two rings of the same count, facing out from the axis — or, flipped, in."""
        for i in range(len(lower)):
            j = (i + 1) % len(lower)
            quad = [lower[i], upper[i], upper[j], lower[j]]
            emit(list(reversed(quad)) if flip else quad, uv_of)

    def cap(rim_points, centre, uv_of, facing_up):
        for i in range(len(rim_points)):
            j = (i + 1) % len(rim_points)
            tri = [centre, rim_points[j], rim_points[i]] if facing_up else [centre, rim_points[i], rim_points[j]]
            emit(tri, uv_of)

    # The foot: a low plate, sides and top.
    band(ring(BASE_RADIUS, 0), ring(BASE_RADIUS, BASE_HEIGHT), iron_uv)
    cap(ring(BASE_RADIUS, BASE_HEIGHT), (0, BASE_HEIGHT, 0), iron_uv, facing_up=True)

    # The post.
    band(ring(POST_RADIUS, BASE_HEIGHT, 6), ring(POST_RADIUS, POST_TOP, 6), iron_uv)

    # The bowl: outside, the underside, the rim, and the inside wall.
    outer_low, outer_high = ring(BOWL_LOW_RADIUS, BOWL_BOTTOM), ring(BOWL_HIGH_RADIUS, BOWL_TOP)
    inner_low = ring(BOWL_LOW_RADIUS - WALL, BOWL_BOTTOM + WALL)
    inner_high = ring(BOWL_HIGH_RADIUS - WALL, BOWL_TOP)
    band(outer_low, outer_high, iron_uv)
    cap(outer_low, (0, BOWL_BOTTOM, 0), iron_uv, facing_up=False)
    # The rim. **Flipped, because the two rings are at one height**: "outward" from inner to outer
    # is radial, and the quad built that way faces *down* — a rim that vanishes from above, which is
    # the only direction anyone looks at a rim from. Caught by working the cross product by hand.
    band(inner_high, outer_high, iron_uv, flip=True)
    band(inner_low, inner_high, iron_uv, flip=True)

    # The coals: a shallow dome filling the bowl at their height. **Wider than the wall there by a
    # hair**, so no crack of the dark inner wall shows between the coals and the iron.
    t = (COALS_HEIGHT - BOWL_BOTTOM) / (BOWL_TOP - BOWL_BOTTOM)
    coal_radius = BOWL_LOW_RADIUS + (BOWL_HIGH_RADIUS - BOWL_LOW_RADIUS) * t - WALL + 0.004
    cap(ring(coal_radius, COALS_HEIGHT, 16), (0, COALS_HEIGHT + COALS_DOME, 0),
        lambda p: coal_uv(p, coal_radius), facing_up=True)

    return points, normals, uvs, counts, indices


def fmt3(v): return "(%.5f, %.5f, %.5f)" % v
def fmt2(v): return "(%.5f, %.5f)" % v


def write_usda(path):
    points, normals, uvs, counts, indices = build()
    out = ['#usda 1.0\n(\n    defaultPrim = "Brazier"\n    metersPerUnit = 1\n    upAxis = "Y"\n)\n\n',
           'def Xform "Brazier"\n{\n',
           '    def Mesh "Body" (\n        prepend apiSchemas = ["MaterialBindingAPI"]\n    )\n    {\n',
           '        rel material:binding = </Brazier/Iron>\n',
           '        point3f[] points = [%s]\n' % ", ".join(fmt3(p) for p in points),
           '        normal3f[] normals = [%s] (\n            interpolation = "vertex"\n        )\n'
           % ", ".join(fmt3(n) for n in normals),
           '        texCoord2f[] primvars:st = [%s] (\n            interpolation = "vertex"\n        )\n'
           % ", ".join(fmt2(t) for t in uvs),
           '        int[] faceVertexCounts = [%s]\n' % ", ".join(str(c) for c in counts),
           '        int[] faceVertexIndices = [%s]\n' % ", ".join(str(i) for i in indices),
           '        uniform token subdivisionScheme = "none"\n    }\n',
           MATERIAL, '}\n']
    path.write_text("".join(out))
    print("wrote %s — %d vertices, %d faces, rim at %.2f m" % (path.name, len(points), len(counts), RIM))


MATERIAL = """
    def Material "Iron"
    {
        token outputs:surface.connect = </Brazier/Iron/Surface.outputs:surface>

        def Shader "Surface"
        {
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor.connect = </Brazier/Iron/Albedo.outputs:rgb>
            float inputs:occlusion.connect = </Brazier/Iron/ORM.outputs:r>
            float inputs:roughness.connect = </Brazier/Iron/ORM.outputs:g>
            float inputs:metallic.connect = </Brazier/Iron/ORM.outputs:b>
            color3f inputs:emissiveColor.connect = </Brazier/Iron/Glow.outputs:rgb>
            token outputs:surface
        }

        def Shader "Albedo"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @brazier.png@
            float2 inputs:st.connect = </Brazier/Iron/Reader.outputs:result>
            float3 outputs:rgb
        }

        def Shader "ORM"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @brazier_orm.png@
            float2 inputs:st.connect = </Brazier/Iron/Reader.outputs:result>
            float outputs:r
            float outputs:g
            float outputs:b
        }

        def Shader "Glow"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @brazier_emissive.png@
            float2 inputs:st.connect = </Brazier/Iron/Reader.outputs:result>
            float3 outputs:rgb
        }

        def Shader "Reader"
        {
            uniform token info:id = "UsdPrimvarReader_float2"
            string inputs:varname = "st"
            float2 outputs:result
        }
    }
"""


def cracks(x, y):
    """How lit a coal is at a texel of the right half, 0…1: bright seams between dark lumps.

    A cellular pattern — distance to the nearest of a few jittered points — with the seams where two
    cells meet. **The seams glow and the lumps do not**, which is what a bed of coals looks like: the
    heat shows in the gaps."""
    cell = 22
    cx, cy = x // cell, y // cell
    nearest = second = 1e9
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            gx, gy = cx + dx, cy + dy
            px = gx * cell + noise(gx, gy, 5) * cell
            py = gy * cell + noise(gx, gy, 9) * cell
            d = math.hypot(x - px, y - py)
            if d < nearest:
                nearest, second = d, nearest
            elif d < second:
                second = d
    seam = max(0.0, 1.0 - (second - nearest) / 5.0)
    return seam * (0.7 + 0.3 * noise(x, y, 3))


def textures():
    albedo, glow, orm = [], [], []
    for y in range(SIZE):
        a, g, o = [], [], []
        for x in range(SIZE):
            if x < SIZE // 2:
                # Iron, blackened by the fire and rusting. **Darker than a bare metal's reflectance
                # would be**, because it is not bare: the first pass used a clean iron's mid-grey,
                # and half a metre under a lamp it read as cream — a pale bowl with a checker of rust
                # squares, rather than a black one catching the firelight.
                rust = noise(x // 2, y // 2, 11)
                grain = 0.85 + 0.3 * noise(x, y, 13)
                base = (0.13, 0.12, 0.11) if rust < 0.75 else (0.20, 0.11, 0.06)
                a.append(tuple(int(255 * min(1, c * grain)) for c in base))
                g.append((0, 0, 0))
                # Rust is rough and not metal; bare iron is smoother and is.
                o.append((255, int(255 * (0.62 if rust < 0.75 else 0.9)), 255 if rust < 0.75 else 40))
            else:
                heat = cracks(x, y)
                ash = noise(x // 2, y // 2, 17)
                lump = (0.05, 0.035, 0.03) if ash < 0.9 else (0.18, 0.17, 0.16)
                a.append(tuple(int(255 * c) for c in lump))
                # Orange where it is hottest, deep red where it is only warm. sRGB, like any colour.
                g.append((int(255 * min(1, heat * 1.2)), int(255 * heat * heat * 0.55), int(255 * heat ** 3 * 0.12)))
                o.append((255, 235, 0))
        albedo.append(a)
        glow.append(g)
        orm.append(o)
    write_png(OUT / "brazier.png", albedo)
    write_png(OUT / "brazier_emissive.png", glow)
    write_png(OUT / "brazier_orm.png", orm)


if __name__ == "__main__":
    write_usda(OUT / "brazier.usda")
    textures()
