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


# --- The space it is written in ------------------------------------------------------------------
#
# **Authored in metres, written in centimetres under a node scaled by 0.01** — which is exactly the
# shape a real character export arrives in, and the reason the sample is written this way.
#
# A character out of a game engine, through an FBX, through Blender has its mesh data and its bind
# transforms in centimetres, with the conversion to metres sitting on a parent node the FBX import
# creates. Measured on a real one: 176 units tall in its own space, 1.76 m in the world. **Nothing
# about that is a mistake**, and a consumer that reads the mesh bounds while ignoring the node chain
# concludes the file is a hundred times too big when it is perfectly correct.
#
# The sample ships that shape rather than a tidier one, because a loader that only ever sees identity
# node transforms is a loader whose node handling is untested — and that is precisely the bug this
# arrangement caught.

UNITS_PER_METRE = 100.0


def to_file_space(p, scaled=True):
    """Metres to the file's own units. **Y-up either way** — the axis is not converted here.

    An earlier version of this script wrote Z-up as well, on the belief that a real export is Z-up.
    It is not: the geometry is Y-up and the file says so, and the studio's own exporter now states
    `upAxis = "Y"` explicitly rather than letting Blender's internal convention leak out.
    """
    k = UNITS_PER_METRE if scaled else 1.0
    return (p[0] * k, p[1] * k, p[2] * k)


def axis_to_file_space(a):
    return a


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
    points, normals, uvs, joints, weights, counts, indices = [], [], [], [], [], [], []

    def emit(polygon):
        """`polygon` is a list of (position, influence, uv); its normal comes from its first corner."""
        a, b, c = polygon[0][0], polygon[1][0], polygon[-1][0]
        n = norm(cross(sub(b, a), sub(c, a)))
        counts.append(len(polygon))
        for position, influence, uv in polygon:
            indices.append(len(points))
            points.append(position)
            normals.append(n)
            uvs.append(uv)
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
                # **UVs in metres, like the sample's other meshes**, so the grain is the same size on
                # a forearm as on a thigh: across the limb, the arc travelled; along it, the distance
                # from the joint.
                ring.append((add(centre, offset),
                             influence,
                             (2 * math.pi * radius * side / SIDES, length * t)))
            rings.append(ring)

        for lower, upper in zip(rings, rings[1:]):
            for side in range(SIDES):
                nxt = (side + 1) % SIDES
                # At the seam the next corner wraps back to angle zero. Give it the full
                # circumference instead, or the closing quad runs the whole texture backwards.
                def closing(vertex):
                    return (vertex[0], vertex[1], (2 * math.pi * radius, vertex[2][1])) \
                           if nxt == 0 else vertex
                emit([lower[side], closing(lower[nxt]), closing(upper[nxt]), upper[side]])

        # Caps, as fans of quads off the ring centre — cheap, and they close the silhouette so the
        # figure casts a solid shadow.
        for ring, outward in ((rings[0], -1), (rings[-1], 1)):
            end = length * (0.0 if outward < 0 else 1.0)
            hub = (add(position, mul(axis, end)), ring[0][1], (math.pi * radius, end))
            for side in range(SIDES):
                nxt = (side + 1) % SIDES
                emit([hub, ring[side], ring[nxt]] if outward > 0 else [hub, ring[nxt], ring[side]])

    return points, normals, uvs, joints, weights, counts, indices


# --- The clips ---------------------------------------------------------------------------------

def quat_axis(axis, degrees):
    """A rotation, with its axis already converted into the space the file is written in."""
    half = math.radians(degrees) / 2
    s = math.sin(half)
    a = norm(axis_to_file_space(axis))
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

def fmt2(v): return "(%.5f, %.5f)" % v
def fmt3(v): return "(%.5f, %.5f, %.5f)" % v
def fmt4(v): return "(%.6f, %.6f, %.6f, %.6f)" % v


def matrix(translation):
    return "( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (%.5f, %.5f, %.5f, 1) )" % to_file_space(translation)


def header(frames):
    # `metersPerUnit = 1` with centimetre data is not a contradiction: the conversion lives on the
    # node below, exactly as a real export puts it, so the file *is* in metres at world level.
    return ('#usda 1.0\n(\n    defaultPrim = "Figure"\n'
            '    metersPerUnit = 1\n    upAxis = "Y"\n'
            '    timeCodesPerSecond = 24\n    startTimeCode = 0\n    endTimeCode = %d\n)\n'
            % frames)


def scale_op():
    """The node that carries the centimetre-to-metre conversion, like an FBX import's parent empty."""
    return ('    double3 xformOp:scale = (%g, %g, %g)\n'
            '    uniform token[] xformOpOrder = ["xformOp:scale"]\n'
            % (1 / UNITS_PER_METRE, 1 / UNITS_PER_METRE, 1 / UNITS_PER_METRE))


def skeleton_block(rest_from=None):
    """The rig. `rest_from` supplies a rest pose other than the true one — see `write_clip`."""
    rest = [local_translation(p) for p in PATHS] if rest_from is None else rest_from
    out = ['    def Skeleton "Rig" (\n        prepend apiSchemas = ["SkelBindingAPI"]\n    )\n    {\n']
    out.append('        uniform token[] joints = [%s]\n' % ", ".join('"%s"' % p for p in PATHS))
    out.append('        uniform matrix4d[] bindTransforms = [\n            %s\n        ]\n'
               % ",\n            ".join(matrix(j[1]) for j in JOINTS))
    out.append('        uniform matrix4d[] restTransforms = [\n            %s\n        ]\n'
               % ",\n            ".join(matrix(t) for t in rest))
    return out


def clip_block(name, rotations, translations):
    out = ['\n    def SkelAnimation "%s"\n    {\n' % name]
    out.append('        uniform token[] joints = [%s]\n' % ", ".join('"%s"' % p for p in PATHS))
    out.append('        float3[] translations.timeSamples = {\n')
    for frame in sorted(translations):
        out.append('            %d: [%s],\n'
                   % (frame, ", ".join(fmt3(to_file_space(t)) for t in translations[frame])))
    out.append('        }\n        half3[] scales.timeSamples = {\n            0: [%s],\n        }\n'
               % ", ".join("(1, 1, 1)" for _ in PATHS))
    out.append('        quatf[] rotations.timeSamples = {\n')
    for frame in sorted(rotations):
        out.append('            %d: [%s],\n' % (frame, ", ".join(fmt4(q) for q in rotations[frame])))
    out.append('        }\n    }\n')
    return out


def write_clip(path, name, built):
    """One animation in a file of its own — which is how a real character arrives.

    **Its copy of the skeleton has the wrong rest pose, on purpose.** A per-clip export carries a full
    rig whose rest transforms are wherever the exporter left it, usually the clip's first frame, and
    not the rig's actual rest pose. That is exactly what is written here. An engine that merged
    skeletons out of clip files would pick this up and stand the character wrong — so the sample ships
    the fault rather than a tidied version of it, and `RigLoader` ignoring it is a thing the sample
    proves rather than a thing a comment claims.

    It carries no mesh, where a real export would. That is the one liberty taken: the point being made
    is about the skeleton, and the repository does not need a second copy of the same 1,188 vertices.
    """
    _, rotations, translations = built
    out = [header(max(rotations))]
    out.append('\ndef SkelRoot "Figure"\n{\n')
    out.append(scale_op())
    out += skeleton_block(rest_from=translations[0])
    out.append('        rel skel:animationSource = </Figure/%s>\n    }\n' % name)
    out += clip_block(name, rotations, translations)
    out.append('}\n')
    with open(path, "w") as handle:
        handle.write("".join(out))
    print("wrote %s — clip '%s', %d keys" % (os.path.basename(path), name, len(rotations)))


def write(path):
    points, normals, uvs, joints, weights, counts, indices = build_mesh()
    clips = [clip("Idle", 72, idle)]
    frames = max(max(c[1]) for c in clips)

    out = []
    out.append(header(frames))
    out.append('\ndef SkelRoot "Figure"\n{\n')
    out.append(scale_op())

    out += skeleton_block()
    out.append('        rel skel:animationSource = </Figure/%s>\n' % clips[0][0])
    out.append('    }\n')

    for name, rotations, translations in clips:
        out += clip_block(name, rotations, translations)

    out.append('\n    def Mesh "Body" (\n'
               '        prepend apiSchemas = ["SkelBindingAPI", "MaterialBindingAPI"]\n    )\n    {\n')
    out.append('        rel skel:skeleton = </Figure/Rig>\n')
    out.append('        rel material:binding = </Figure/Skin>\n')
    out.append('        matrix4d primvars:skel:geomBindTransform = '
               '( (1, 0, 0, 0), (0, 1, 0, 0), (0, 0, 1, 0), (0, 0, 0, 1) )\n')
    out.append('        int[] primvars:skel:jointIndices = [%s] (\n'
               '            elementSize = 2\n            interpolation = "vertex"\n        )\n'
               % ", ".join(str(j) for j in joints))
    out.append('        float[] primvars:skel:jointWeights = [%s] (\n'
               '            elementSize = 2\n            interpolation = "vertex"\n        )\n'
               % ", ".join("%.3f" % w for w in weights))
    out.append('        point3f[] points = [%s]\n' % ", ".join(fmt3(to_file_space(p)) for p in points))
    out.append('        normal3f[] normals = [%s] (\n            interpolation = "vertex"\n        )\n'
               % ", ".join(fmt3(to_file_space(n, scaled=False)) for n in normals))
    out.append('        texCoord2f[] primvars:st = [%s] (\n            interpolation = "vertex"\n        )\n'
               % ", ".join(fmt2(t) for t in uvs))
    out.append('        int[] faceVertexCounts = [%s]\n' % ", ".join(str(c) for c in counts))
    out.append('        int[] faceVertexIndices = [%s]\n' % ", ".join(str(i) for i in indices))
    out.append('        uniform token subdivisionScheme = "none"\n    }\n')

    # **A UsdPreviewSurface, because that is what a bought asset carries.** The sample could assign
    # this texture in code; reading it out of the file is what exercises the loader.
    out.append(MATERIAL)

    with open(path, "w") as handle:
        handle.write("".join(out))
    print("wrote %s — %d joints, %d vertices, %d faces, clip: %s"
          % (os.path.basename(path), len(JOINTS), len(points), len(counts), clips[0][0]))


MATERIAL = """
    def Material "Skin"
    {
        token outputs:surface.connect = </Figure/Skin/Surface.outputs:surface>

        def Shader "Surface"
        {
            uniform token info:id = "UsdPreviewSurface"
            color3f inputs:diffuseColor.connect = </Figure/Skin/Albedo.outputs:rgb>
            normal3f inputs:normal.connect = </Figure/Skin/Bump.outputs:rgb>
            float inputs:metallic = 0
            float inputs:roughness = 0.75
            token outputs:surface
        }

        def Shader "Bump"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @figure_normal.png@
            float2 inputs:st.connect = </Figure/Skin/Reader.outputs:result>
            token inputs:wrapS = "repeat"
            token inputs:wrapT = "repeat"
            float3 outputs:rgb
        }

        def Shader "Albedo"
        {
            uniform token info:id = "UsdUVTexture"
            asset inputs:file = @figure.png@
            float2 inputs:st.connect = </Figure/Skin/Reader.outputs:result>
            token inputs:wrapS = "repeat"
            token inputs:wrapT = "repeat"
            float3 outputs:rgb
        }

        def Shader "Reader"
        {
            uniform token info:id = "UsdPrimvarReader_float2"
            string inputs:varname = "st"
            float2 outputs:result
        }
    }
}
"""


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    out = os.path.join(here, "..", "Sources", "WindageSample", "Resources")
    write(os.path.join(out, "figure.usda"))
    write_clip(os.path.join(out, "figure-wave.usda"), "Wave", clip("Wave", 48, wave))
