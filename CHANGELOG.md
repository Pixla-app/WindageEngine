# Changelog

Every release of Windage Engine, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) under the pre-1.0 rules set out in
`README.md` § "Versioning".

**Written for somebody upgrading**, which means the entries that matter most are under *Changed* and
*Removed*. A new type costs a reader nothing; a changed one costs them a build.

## [Unreleased]

Nothing yet.

## [0.1.3] — 2026-09-09

**A correction, and the defect behind it.** 0.1.1 said a real character "arrives Z-up and in
centimetres", and treated the scale as something the file failed to record. That was wrong: the
conversion sits on a parent node, and **the loaders were ignoring node transforms entirely**.

### Fixed

- **`MeshLoader` and `RigLoader` now compose the file's node hierarchy.** They read a mesh's bounds
  and a skeleton's joints and never walked the nodes above them, so any asset with a parent transform
  loaded a hundred times too big — harmless for a hand-written OBJ at the origin, which was every
  asset this repository had until a real one arrived.
- **`SceneObject` composes the mesh's node transform** into its volume, so a placement means the same
  thing whatever the geometry came from.

### Added

- **`LoadedMesh.nodeTransform`** and **`Rig.nodeTransform`** — where the mesh or rig sits in the
  file's own hierarchy, composed from the root. Applied in front of the model matrix, like
  `AssetOrientation`, because skinning happens in model space.

### Changed

- **The sample's figure is written in centimetres under a node scaled by 0.01**, Y-up, which is the
  shape a real export actually has. It previously wrote hand-converted Z-up coordinates, on the same
  wrong diagnosis.

### Correcting 0.1.1

That entry's "Z-up" half stands — Blender's USD exporter writes Blender's convention unless told
otherwise, and `AssetOrientation` handles it. Its "in centimetres, and the file does not say so" half
does not: the file says so, on a node. **The probe that produced the wrong answer read
`MDLMesh.boundingBox` and stopped**, never asking what the mesh hung off.

## [0.1.2] — 2026-09-09

**The shadow pass stops being written twice.** The arithmetic has been here since `ShadowCascades`;
the pass — the texture, the depth state, the descriptors, the encoder loop — existed in two
repositories, where a fix to one did not reach the other. Additive: nothing that compiled against
0.1.1 changes.

### Added

- **`ShadowMap`** — the depth texture array and its per-cascade slices, the reversed-Z depth state,
  the front-face cull, the slope-scaled bias, the per-cascade pass descriptors, the light matrices
  per frame in flight, and the encoder loop.
- **`ShadowMap.Batch`** — a pipeline plus closures reaching each drawable's mesh, uniforms and
  optional joint palette. Batches rather than one loop because a skinned mesh has a different vertex
  layout, so pipeline state changes once per kind rather than once per object.
- **`ShadowMap.pipelineDescriptor(vertexFunction:vertexDescriptor:label:)`** — the three things a
  shadow pipeline must get right and none of which is obvious: no fragment function or colour
  attachment, one raster sample, and a depth format matching the texture.
- **`ShadowMap.BufferIndex`** — where the argument table puts the uniforms, the light matrix and the
  joint palette. A mismatch does not fail; it reads a matrix out of the wrong buffer and records the
  scene from nowhere.
- **`ShadowCascades.constantDepthBias`** and **`.slopeScaledDepthBias`**, beside `biasScales`,
  because the three numbers are one tuning. Both negative: under reversed-Z, pushing an occluder away
  from the light is a *smaller* value, so the sign is the opposite of every textbook.

### What a game keeps

The **pipelines** — compiled against its own shaders and vertex descriptor, so they cannot come from
here — the **uniform layout**, the joint palette, and the cascade **numbers**. A courtyard seventy
metres across and a range where the target is at 800 m want different splits.

A game with its own copy of the pass is not obliged to change. Replacing it is that game's work on
that game's schedule.

## [0.1.1] — 2026-09-09

**Everything a real character needs that a generated one did not show.** An 87-joint rigged character
from an actual toolchain was loaded, and it arrives in three shapes the engine had no answer for.
Additive: nothing that compiled against 0.1.0 changes.

### Added

- **`AssetOrientation`** — the up axis and unit scale an asset was authored in, and the one matrix
  that corrects it. A character out of a game-engine toolchain by way of Blender arrives **Z-up and
  in centimetres**; applied in front of the model matrix, one matrix corrects the mesh, the rig and
  the animation together, because skinning happens in model space.
- **`RigLoader.clips(named:withExtension:bundle:)`** — reads only the animations from a file.
- **`RigLoader.load(named:withExtension:clipFiles:bundle:reportingTo:)`** — a rig from one file and
  its animations from others, which is how a character exported one clip at a time arrives. A file
  holding one clip has it renamed to the file's own name. A clip that drives none of the rig's joints
  is dropped and reported; a clip file that is missing is reported, not thrown.
- **`Rig.adding(_:)`** and **`Rig.jointsNotDrivenBy(_:)`**.
- **`AnimationClip.renamed(to:)`** — for the names an exporter produces.

### Changed

- **The sample's figure is now written the way a real export arrives**: Z-up, a hundred units to the
  metre, and its second clip in a file of its own whose copy of the skeleton has the wrong rest pose.
  It renders identically to the Y-up metre version it replaced, which is the point. A sample that
  only ever loads tidy assets leaves the untidy path untested.

### Notes for anyone loading a real character

- **A clip file's skeleton is not the rig's skeleton.** Its rest pose is wherever the exporter left
  the rig — usually the clip's first frame. Measured: one joint reports (10.42, 4.08, 7.84) in the
  base file and (3.16, 1.17, 7.84) in the walk file. Merge them and every joint a clip does not
  animate stands in the wrong place, and the fault changes with which files were loaded.
- **Model I/O exposes `upAxis` and not `metersPerUnit`.** The axis can be read; the scale has to be
  measured once and written down.
- **Each per-clip export carries a whole copy of the mesh.** Model I/O offers no way to open an
  asset's animations alone, so the parse cost stays; what `clips(...)` avoids is the expensive half,
  since nothing is laid out or uploaded to a GPU without a vertex descriptor and an allocator.

## [0.1.0] — 2026-09-09

**The first version with a number.** Everything before this was a folder inside a studio repository,
consumed by one game that was developed alongside it — so there was nothing for a version to mean.
It is `0.1.0` rather than `1.0.0` deliberately: the API is not settled, and saying so in the number
is cheaper than discovering it in somebody else's build.

### Added

- **Frame pacing and frames in flight.** `FrameRenderer` drives the loop from a
  `CAMetalDisplayLink`, owns the depth buffer and the reversed-Z clear value, and hands a game four
  methods to implement (`GameLoop`). `FixedTimestep` separates simulation rate from frame rate and
  reports the interpolation fraction for rendering between steps.
- **The reversed-Z convention, enforced rather than documented.**
  `matrix_perspective_right_hand_reverse_z`, `FrameRenderer.makeDepthStencilState()` and
  `FrameRenderer.reversedZClearDepth` are one set: use all three and the projection, the compare
  function and the clear value cannot disagree. A depth-slice variant projects a first-person
  viewmodel into the front of the buffer.
- **`Camera`** — position, yaw and pitch, mouse and stick look, and interpolation between two
  cameras for rendering between simulation steps.
- **`InputState`** — keyboard, mouse and gamepad behind one interface, with `StickResponse` for
  dead zone and response curve, and `SprintLatch` for holds that have to survive a frame boundary.
- **`MeshLoader`** — geometry through Model I/O, laid out to match a pipeline's vertex descriptor,
  with per-submesh materials and the mesh's bounds.
- **Skinned animation** — `Skeleton`, `AnimationClip`, `JointTransform`, `JointTrack`,
  `AnimationBinding`, `AnimationPlayhead`, `SkeletonPose` and `RigLoader`. Rigs and clips load from
  USD, clips cross-fade, and the result is a joint palette a vertex shader indexes.
- **Materials and textures** — `Material` (the metallic-roughness set), `TextureSlot` (which decides
  sRGB decoding, because that is a property of the map and not of the call site) and `TextureStore`
  (loads once, caches, mipmaps, and carries 1×1 fallbacks).
- **`ShadowCascades`** — cascade splits, the light basis, texel snapping, per-cascade depth bias
  derived from the world size of a texel, and the blend bands between cascades.
- **`Frustum`** — the planes of a view-projection and a conservative box test. Five planes, not six:
  the engine's projection has an infinite far plane.
- **`BoundingBox`** and **`Volume`** — an extent, where it is, and one segment hit test shared by
  everything that asks "what is out there".
- **`Level` and `LevelEditor`** — a versioned level format with placements, markers, tags and
  anchors that resolve against ground the game supplies; and the operations an in-game editor needs,
  with undo.
- **`HUDRenderer` and `FontAtlas`** — text and quads drawn after tone mapping, in the same pass,
  with an atlas that can be asked for characters beyond ASCII and says what a font could not supply.
- **`AudioEngine`** — positional playback with a listener that follows the camera.
- **`SaveStore`** — injected rather than global, so tests do not fight over one file.
- **`ShaderLibrary`** — finds a compiled Metal library, and compiles from source when there is none,
  because `swift build` compiles no Metal at all.
- **`WindageSample`** — a complete small game built against the public API only: two levels loaded
  from JSON, an in-game editor, cascaded shadows, positional audio, animated characters, textured
  surfaces, a win/lose loop and a save. It is the standing check that somebody who did not write the
  engine can build with it.

### Known gaps

Not a list of bugs — a list of things a consumer will look for and not find. The reasoning, and
which of them are waiting on evidence rather than on time, is in `README.md` § "Where this engine
actually stands".

- No normal mapping in any consumer: the slot and the sRGB rule exist, tangents in the vertex layout
  do not.
- No animation state machine, retargeting, IK or root motion.
- No transform hierarchy between *objects* — a rig is one, objects are a flat list.
- No post-processing or tone-map curve; each game supplies its own.
- No particles, character controller, LOD or instancing.
- The shadow *pass* is not extracted — only the arithmetic behind it.
- macOS and Metal 4 only.

---

**Versions are git tags** — `0.1.0`, no `v` prefix, which is what SwiftPM expects. This repository
has no remote yet, so there are no compare links here; add them when it has one, rather than
inventing a URL that resolves to nothing.
