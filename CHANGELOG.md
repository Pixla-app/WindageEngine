# Changelog

Every release of Windage Engine, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) under the pre-1.0 rules set out in
`README.md` § "Versioning".

**Written for somebody upgrading**, which means the entries that matter most are under *Changed* and
*Removed*. A new type costs a reader nothing; a changed one costs them a build.

## [Unreleased]

Nothing yet.

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
