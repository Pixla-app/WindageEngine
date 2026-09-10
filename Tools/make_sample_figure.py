#!/usr/bin/env python3
"""Generates the sample's rigged figure: Sources/WindageSample/Resources/figure.usda

A courtyard of boxes cannot show a skeleton, so the sample needs one articulated thing. This
writes it rather than shipping a binary, for the same reason the sample's sounds are generated:
an asset nobody can read or regenerate is a blob the repository cannot explain.

Deliberately a blocky mannequin. It is a test of skinning, not of modelling — the point is that a
bend at a joint is unmistakable, and eleven joints with hand-written weights are something a
reader can check against the file.

Run:  python3 Tools/make_sample_figure.py
"""

import math
import os

# --- The rig -----------------------------------------------------------------------------------
#
# Bind-pose positions in metres, in the figure's own space, standing on y = 0. Each joint owns one
# bone: the segment from its own position to `tip` — which is its child's position where it has
# one, and an explicit end where it does not (a head has no child but still needs a skull).

JOINTS = [
    # path,                          position,             tip,                  radius
    ("root",                         (0.00, 0.95, 0.00), (0.00, 1.30, 0.00), 0.150),
    ("root/spine",                   (0.00, 1.30, 0.00), (0.00, 1.62, 0.00), 0.175),
    ("root/spine/head",              (0.00, 1.62, 0.00), (0.00, 1.86, 0.00), 0.125),
    ("root/spine/arm_l",             (0.20, 1.52, 0.00), (0.48, 1.52, 0.00), 0.070),
    ("root/spine/arm_l/forearm_l",   (0.48, 1.52, 0.00), (0.74, 1.52, 0.00), 0.058),
    ("root/spine/arm_r",             (-0.20, 1.52, 0.00), (-0.48, 1.52, 0.00), 0.070),
    ("root/spine/arm_r/forearm_r",   (-0.48, 1.52, 0.00), (-0.74, 1.52, 0.00), 0.058),
    ("root/leg_l",                   (0.13, 0.90, 0.00), (0.13, 0.48, 0.00), 0.088),
    ("root/leg_l/shin_l",            (0.13, 0.48, 0.00), (0.13, 0.05, 0.00), 0.076),
    ("root/leg_r",                   (-0.13, 0.90, 0.00), (-0.13, 0.48, 0.00), 0.088),
    ("root/leg_r/shin_r",            (-0.13, 0.48, 0.00), (-0.13, 0.05, 0.00), 0.076),
]

PATHS = [j[0] for j in JOINTS]
INDEX = {p: i for i, p in enumerate(PATHS)}
PARENT = {p: (INDEX[p.rsplit("/", 1)[0]] if "/" in p else None) for p in PATHS}

# Rings along each bone, and how much of each ring's vertices the *parent* joint owns.
#
# This is the whole of the weighting scheme, and it is the reason a bend looks like a bend: right at
# the joint a vertex is shared equally, and by halfway down the bone it belongs entirely to the bone.
# Weight everything 100% to its own bone instead and every joint tears open when it rotates.
RINGS = [(0.00, 0.50), (0.25, 0.25), (0.60, 0.00), (1.00, 0.00)]

SIDES = 6           # cross-section of a limb; six reads as round enough and stays cheap


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def norm(a):
    length = math.sqrt(dot(a, a))
    return (a[0] / length, a[1] / length, a[2] / length) if length > 1e-9 else (0.0, 1.0, 0.0)


def basis(axis):
    """Two vectors perpendicular to `axis`, picked so a limb along any direction gets a sane ring."""
    reference = (1.0, 0.0, 0.0) if abs(axis[1]) > 0.9 else (0.0, 1.0, 0.0)
    u = norm(cross(reference, axis))
    return u, norm(cross(axis, u))


def build_mesh():
    """One faceted mesh: every face owns its four points outright.

    Sharing points between faces would mean sharing normals too, and a shared normal on a box is a
    smeared edge. Four points per face costs a few hundred vertices on a figure this size and keeps
    every interpolation in the file "vertex" — no face-varying primvars to expand, so what the
    loader receives is exactly what is written here.
    """
    points, normals, joints, weights, counts, indices = [], [], [], [], [], []

    def emit_quad(ring_a, ring_b, i, j):
        quad = [ring_a[i], ring_a[j], ring_b[j], ring_b[i]]
        n = norm(cross(sub(quad[1][0], quad[0][0]), sub(quad[3][0], quad[0][0])))
        counts.append(4)
        for position, influence in quad:
            indices.append(len(points))
            points.append(position)
            normals.append(n)
            joints.extend(influence[0])
            weights.extend(influence[1])

    for index, (path, position, tip, radius) in enumerate(JOINTS):
        axis = norm(sub(tip, position))
        u, v = basis(axis)
        parent = PARENT[path]
        length = math.sqrt(dot(sub(tip, position), sub(tip, position)))

        rings = []
        for t, parent_weight in RINGS:
            # No parent means nothing to share with, and a root ring weighted half to nobody would
            # shrink toward the origin.
            share = parent_weight if parent is not None else 0.0
            influence = ((index, parent if parent is not None else index),
                         (1.0 - share, share))
            centre = add(position, mul(axis, length * t))
            # Taper the ends a little so a limb reads as a limb rather than as a post.
            scale = radius * (0.72 if t in (0.0, 1.0) else 1.0)
            ring = []
            for side in range(SIDES):
                angle = 2 * math.pi * side / SIDES
                offset = add(mul(u, math.cos(angle) * scale), mul(v, math.sin(angle) * scale))
                ring.append((add(centre, offset), influence))
            rings.append(ring)

        for lower, upper in zip(rings, rings[1:]):
            for side in range(SIDES):
                emit_quad(lower, upper, side, (side + 1) % SIDES)

        # Caps, as fans of quads off the ring centre — cheap, and they close the silhouette so the
        # figure casts a solid shadow.
        for ring, outward in ((rings[0], -1), (rings[-1], 1)):
            centre = add(position, mul(axis, length * (0.0 if outward < 0 else 1.0)))
            influence = ring[0][1]
            n = mul(axis, outward)
            for side in range(SIDES):
                nxt = (side + 1) % SIDES
                fan = [(centre, influence), ring[side], ring[nxt]] if outward > 0 \
                      else [(centre, influence), ring[nxt], ring[side]]
                counts.append(3)
                for point, inf in fan:
                    indices.append(len(points))
                    points.append(point)
                    normals.append(n)
                    joints.extend(inf[0])
                    weights.extend(inf[1])

    return points, normals, joints, weights, counts, indices


# --- The clips ---------------------------------------------------------------------------------

def quat_axis(axis, degrees):
    half = math.radians(degrees) / 2
    s = math.sin(half)
    a = norm(axis)
    return (math.cos(half), a[0] * s, a[1] * s, a[2] * s)


IDENTITY = (1.0, 0.0, 0.0, 0.0)


def local_translation(path):
    position = JOINTS[INDEX[path]][1]
    parent = PARENT[path]
    return position if parent is None else sub(position, JOINTS[parent][1])


# Every third 24th of a second: 8 keys a second, which is plenty for curves this smooth and is a
# third of the file size of sampling every frame. Slerp does the rest.
ROTATION_STEP = 3


def clip(name, frames, pose):
    """`pose(path, phase)` returns a quaternion; `frames` is how many 24ths of a second it runs.

    **Only the rotations are keyed over time.** Nothing in these clips translates or scales a joint,
    so those channels get a single key holding the rest pose — a channel with one key samples to that
    key at any time, and writing 122 identical copies of it tripled the size of the file for nothing.
    The three channels therefore have *different* key times, which is worth having in the sample: a
    loader that assumed one shared timeline would be wrong here and right on most exports.
    """
    rotations = {}
    for frame in list(range(0, frames, ROTATION_STEP)) + [frames]:
        rotations[frame] = [pose(path, frame / frames) for path in PATHS]
    return name, rotations, {0: [local_translation(path) for path in PATHS]}


def idle(path, phase):
    """Standing, with a slow weight shift so the figure is never quite still.

    **The arms come down here, not in the bind pose.** The rig is modelled with the arms straight
    out, which is what every character is rigged as and what makes weighting a shoulder tractable —
    a pose is a clip's job. A figure standing in its bind pose is the tell that nothing is animating
    it, so this is also the check that the clip is being applied at all.
    """
    sway = math.sin(phase * 2 * math.pi)
    if path == "root/spine":
        return quat_axis((0, 0, 1), 2.5 * sway)
    if path == "root/spine/head":
        return quat_axis((0, 1, 0), 9.0 * sway)
    if path == "root/spine/arm_l":
        return quat_axis((0, 0, 1), -72.0 - 3.0 * sway)
    if path == "root/spine/arm_r":
        return quat_axis((0, 0, 1), 72.0 + 3.0 * sway)
    if path == "root/spine/arm_l/forearm_l":
        return quat_axis((0, 0, 1), -12.0 - 4.0 * sway)
    if path == "root/spine/arm_r/forearm_r":
        return quat_axis((0, 0, 1), 12.0 + 4.0 * sway)
    return IDENTITY


def wave(path, phase):
    """One arm up, waving — the clip the sample cross-fades into as the player approaches.

    **Deliberately far from the idle pose.** A cross-fade between two poses that nearly agree proves
    nothing; this arm travels most of a half-turn, so a blend that took the long way round, or that
    averaged the matrices instead of the quaternions, would be impossible to miss.
    """
    swing = math.sin(phase * 4 * math.pi)
    if path == "root/spine/arm_l":
        return quat_axis((0, 0, 1), 96.0)
    if path == "root/spine/arm_l/forearm_l":
        return quat_axis((0, 0, 1), 22.0 * swing + 8.0)
    if path == "root/spine/arm_r":
        return quat_axis((0, 0, 1), 68.0)
    if path == "root/spine/arm_r/forearm_r":
        return quat_axis((0, 0, 1), 16.0)
    if path == "root/spine":
        return quat_axis((0, 0, 1), -4.0)
    if path == "root/spine/head":
        return quat_axis((0, 1, 0), -7.0 * swing)
    return IDENTITY


# --- Writing it out ------------------------------------------------------------------------------

def fmt3(v): return "(%.5f, %.5f, %.5f)" % v
def fmt4(v): return "(%.6f, %.6f, %.6f, %.6f)" % v


def matrix(translation):
    return "( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (%.5f, %.5f, %.5f, 1) )" % translation


def write(path):
    points, normals, joints, weights, counts, indices = build_mesh()
    clips = [clip("Idle", 72, idle), clip("Wave", 48, wave)]
    frames = max(max(c[1]) for c in clips)

    out = []
    out.append('#usda 1.0\n(\n    defaultPrim = "Figure"\n    metersPerUnit = 1\n    upAxis = "Y"\n'
               '    timeCodesPerSecond = 24\n    startTimeCode = 0\n    endTimeCode = %d\n)\n' % frames)
    out.append('\ndef SkelRoot "Figure"\n{\n')

    out.append('    def Skeleton "Rig" (\n        prepend apiSchemas = ["SkelBindingAPI"]\n    )\n    {\n')
    out.append('        uniform token[] joints = [%s]\n' % ", ".join('"%s"' % p for p in PATHS))
    out.append('        uniform matrix4d[] bindTransforms = [\n            %s\n        ]\n'
               % ",\n            ".join(matrix(j[1]) for j in JOINTS))
    out.append('        uniform matrix4d[] restTransforms = [\n            %s\n        ]\n'
               % ",\n            ".join(matrix(local_translation(p)) for p in PATHS))
    out.append('        rel skel:animationSource = </Figure/%s>\n' % clips[0][0])
    out.append('    }\n')

    for name, rotations, translations in clips:
        out.append('\n    def SkelAnimation "%s"\n    {\n' % name)
        out.append('        uniform token[] joints = [%s]\n' % ", ".join('"%s"' % p for p in PATHS))
        out.append('        float3[] translations.timeSamples = {\n')
        for frame in sorted(translations):
            out.append('            %d: [%s],\n' % (frame, ", ".join(fmt3(t) for t in translations[frame])))
        out.append('        }\n        half3[] scales.timeSamples = {\n            0: [%s],\n        }\n'
                   % ", ".join("(1, 1, 1)" for _ in PATHS))
        out.append('        quatf[] rotations.timeSamples = {\n')
        for frame in sorted(rotations):
            out.append('            %d: [%s],\n' % (frame, ", ".join(fmt4(q) for q in rotations[frame])))
        out.append('        }\n    }\n')

    out.append('\n    def Mesh "Body" (\n        prepend apiSchemas = ["SkelBindingAPI"]\n    )\n    {\n')
    out.append('        rel skel:skeleton = </Figure/Rig>\n')
    out.append('        matrix4d primvars:skel:geomBindTransform = '
               '( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1) )\n')
    out.append('        int[] primvars:skel:jointIndices = [%s] (\n'
               '            elementSize = 2\n            interpolation = "vertex"\n        )\n'
               % ", ".join(str(j) for j in joints))
    out.append('        float[] primvars:skel:jointWeights = [%s] (\n'
               '            elementSize = 2\n            interpolation = "vertex"\n        )\n'
               % ", ".join("%.3f" % w for w in weights))
    out.append('        point3f[] points = [%s]\n' % ", ".join(fmt3(p) for p in points))
    out.append('        normal3f[] normals = [%s] (\n            interpolation = "vertex"\n        )\n'
               % ", ".join(fmt3(n) for n in normals))
    out.append('        int[] faceVertexCounts = [%s]\n' % ", ".join(str(c) for c in counts))
    out.append('        int[] faceVertexIndices = [%s]\n' % ", ".join(str(i) for i in indices))
    out.append('        uniform token subdivisionScheme = "none"\n    }\n}\n')

    with open(path, "w") as handle:
        handle.write("".join(out))
    print("wrote %s — %d joints, %d vertices, %d faces, clips: %s"
          % (path, len(JOINTS), len(points), len(counts), ", ".join(c[0] for c in clips)))


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    write(os.path.join(here, "..", "Sources", "WindageSample", "Resources", "figure.usda"))
