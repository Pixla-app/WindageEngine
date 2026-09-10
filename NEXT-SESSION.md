# Windage Engine — Next Session Handoff

**Read `README.md` first.** It holds the standing decisions and the reasoning; this file holds only
what changed recently and what is next.

> **This repository stands alone, and that is a rule rather than a description.** It builds, runs and
> tests with no game checked out. Capabilities arrive by being *extracted* from a working game — that
> is the quality rule — but nothing that arrives keeps the name of where it came from. If a doc
> comment, a test or this file starts naming somebody's game, that is a regression: rewrite it to
> describe the *shape* of the consumer instead. The reasoning is what is worth keeping; the product
> name is coupling.

**Run it:** `swift run WindageSample` · **Test it:** `swift test`

---

## Start here — how the work proceeds

**A game drives an engine; that is the industry's normal shape, not a compromise.** id Tech, Unreal,
Source, CryEngine, Frostbite, Decima and Godot were every one of them extracted from a shipping
title, and Unity — the engine-first outlier — is the cautionary tale. **`README.md` §"How this engine
gets built" carries the table and the reasoning; read it before proposing a different arrangement.**

> **Two separate rules, and both hold.** A game is where problems get *found*; this repository still
> mentions none. Nothing about the first licenses writing a product name into the second.
>
> **And a driving game does not have to contain everything this engine can do** — that inference is
> wrong and expensive, and the README's table says where capabilities actually come from. Most of
> what an engine owes a game has a settled industry shape and needs no game to discover it.
> **Skinned animation was the worked example**: built engine-first on 2026-09-09, proved in the
> sample, and every fault in it found by the sample rather than by a game. The next task is another
> one of those.

What that means for the next session, concretely:

- **The engine's roadmap is its own.** It comes from the gaps listed below, not from what some game
  happens to want this week.
- **`WindageSample` is the proving ground.** A capability is not finished until the sample uses it
  through the public API. That is what has caught every real bug so far.
- **A game adopts afterwards.** If a game already has its own version of something the engine now
  owns, replacing it is that game's work, on that game's schedule — not a prerequisite here.
- **A second sample arrives only when a capability needs a shape the courtyard cannot express.**
  Skinned animation was expected to be that case and **was not** — what it needed was a character
  standing *in* the courtyard, not a second scene around it. The bar is higher than it looked.

## State — 2026-09-09

246 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop, a save — and now **animated
characters** — all against the public API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`, **`Skeleton`,
`AnimationClip`, `SkeletonPose` and `RigLoader`**, and **`Material`, `TextureSlot` and
`TextureStore`**.

## Done 2026-09-10 — normal mapping (0.2.1)

**The last material slot with nothing behind it.** `MeshLoader` generates a tangent basis when the
pipeline asks for one and the file did not bring it; the sample is normal mapped throughout — crate,
stone, ground and the figure.

### Four things measured, each of which fails quietly

- **Model I/O's OBJ reader recognises only `bump`.** All five spellings were tried: `map_Bump` (what
  Blender and Maya write), `norm`, `map_Kn` and `map_normal` are read and **silently dropped** — no
  property on the material, nothing logged.
- **The basis must be built before the vertex descriptor is applied.** Handing a descriptor to
  `MDLAsset(url:vertexDescriptor:)` converts at load and fills a missing tangent with **zeroes** —
  degenerate rather than absent, which normalises to NaN and *deletes* the triangle.
- **`w` is handedness, ±1.** A mirrored UV island — most of any character — has its bitangent
  reversed; drop the sign and it is lit from the wrong side.
- **A tangent transforms by the model matrix, not the normal matrix.** It lies along the surface.

### And one about shadows

**The shadow lookup keeps the geometric normal.** Biasing along a mapped normal moves the sample off
the surface it belongs to and the contact shadow detaches — a bug that looks like a shadow problem
and is a normal-mapping one.

**The sample's normal maps are derived from the same height fields as its colours**, so they cannot
drift; a normal map that disagrees with the colour under it reads as bad lighting rather than as a
mistake.

## Done 2026-09-09 — every texture was upside down (0.2.0)

**Metal puts texture (0, 0) at an image's top-left; USD and OBJ put `st` (0, 0) at its bottom-left.**
Nothing reconciled them, so every textured asset had loaded flipped since the day textures were
added. `TextureStore` now loads with a bottom-left origin by default; `.topLeft` is available for
glTF-derived UVs.

**Minor bump, not patch** — it changes what existing code does, correctly.

### Why it survived

The sample's own textures are planks, brickwork and noise, and every one reads the same upside down.
It took a bought character whose texture is a **palette** — a 32×32 grid of swatches with a magenta
row along the bottom — for the flip to stop softening an edge and start putting the wrong colour on a
limb. The character tool photographs what it made, so there was a reference to compare against.

> **The lesson is about the test asset.** Four generated textures, none able to fail visibly. The
> regression fixture is red on top and blue on the bottom now, because an image that looks the same
> either way up tests nothing about which way up it is.

## Done 2026-09-09 — a real character, actually run (0.1.4)

**Not probed with a script this time — loaded into the sample and looked at.** A 93-joint,
39,360-vertex character with six clips renders: skinned, textured, shadowed, animating, at the right
scale, standing on the ground.

- **The engine could not load anything outside its own bundle.** Both loaders took a resource name and
  a `Bundle`. There are `url:` entry points now. **A fixture could never have found this**, because a
  fixture is a bundle resource by construction — which is the whole argument for running a real asset
  rather than probing one.
- **Facing is per asset**, as predicted, and is not in the file. The sample applies a half turn for an
  external character; a game applies whatever its asset needs, where it places the thing.
- **The material names no texture**, as predicted. The colour map ships beside the model and is bound
  by name.
- **Everything else worked** — the palette at real joint counts, four influences genuinely in use, the
  node scale, clip-per-file loading, the wrong rest poses, the up axis. That is what the fixtures were
  for.

**Run it:** `WINDAGE_SAMPLE_CHARACTER=/path/to/Name swift run WindageSample` — a path with no
extension, `<path>.usdc` plus `<path>_*.usdc` clips and `<path>_ColorMap.png`. Not shipped: a real
character is tens of megabytes and belongs to whoever made it.

## Done 2026-09-09 — node transforms, and a correction (0.1.3)

**A wrong diagnosis, corrected, and the real defect behind it fixed.** The handoff below said a real
character "is Z-up and in centimetres — 176 units tall". The centimetres half was wrong in its
explanation: the conversion sits on a **parent node** scaled by 0.01, exactly where an FBX import puts
it, and the file is entirely consistent. **What was actually wrong was the engine** — `MeshLoader` and
`RigLoader` read a mesh's bounds and a skeleton's joints and never walked the node chain above them,
so any exported asset came in a hundred times too big.

- **`LoadedMesh.nodeTransform` and `Rig.nodeTransform`** report the composed hierarchy. Applied in
  front of the model matrix, like `AssetOrientation`. `SceneObject` composes it into its volume.
- **The sample's figure is now written the way a real export is**: centimetre data, Y-up, under a node
  scaled by 0.01. It previously wrote hand-converted Z-up coordinates, on the same wrong diagnosis.
- **The up-axis half stands.** Blender's USD exporter writes Blender's Z-up unless told otherwise, and
  `AssetOrientation` handles that. The studio's exporter now states `upAxis = "Y"` — USD's own default
  and what Model I/O, Quick Look and Preview assume — so our own characters need no correction, and a
  bought one still might.

> **The lesson is about the probe, not the asset.** The measurement that produced the wrong answer
> read `MDLMesh.boundingBox` and stopped, never asking what the mesh hung off — so it could not see
> the half of the answer sitting one level up. **A probe that reports a number without reporting the
> space it is in will eventually be believed.**

## Done 2026-09-09 — the shadow pass is extracted (0.1.2)

**One thing implemented twice is now implemented once.** `ShadowMap` owns the depth texture array,
the reversed-Z depth state, the front-face cull, the slope-scaled bias, the per-cascade descriptors,
the light matrices and the encoder loop. `SampleShadowMap.swift` is deleted; what the sample keeps is
two pipelines and four cascade numbers.

- **`ShadowMap.Batch`** is the seam: a pipeline plus closures for the mesh, the uniform address and an
  optional joint-palette address. Closures rather than arrays, because a game's drawables are its own.
- **`pipelineDescriptor(vertexFunction:vertexDescriptor:label:)`** and **`BufferIndex`** were comments
  and are now API — the things that must be right and whose failure is silent.
- **`constantDepthBias` / `slopeScaledDepthBias` moved onto `ShadowCascades`.** Both negative: under
  reversed-Z, pushing an occluder away from the light is a *smaller* value.

### The bad reason it waited, written down because it will recur

It was parked as *"waiting for a third consumer to say what the seam is"*. **That was wrong twice.**
The code was already written, working and tested in two repositories where a fix to one does not
reach the other — a defect, not a shape waiting to be discovered. And a third copy would have been
more of the same evidence; what actually answered it was **teaching the sample's own pass to draw
skinned meshes**, because a second vertex layout inside one consumer forced the abstraction two
consumers had only hinted at.

> **The rule protects against *designing* with no evidence. It says nothing about code that already
> exists in two places** — and reaching for it there is how duplication acquires a justification.

## Done 2026-09-09 — what a real character needs (0.1.1)

**An 87-joint character from a real toolchain was loaded, and it arrived in three shapes the engine
had no answer for.** All three are now handled, and the sample ships the untidy version so the path
stays tested.

- **Clips in files of their own.** `RigLoader.clips(named:)` reads only animations;
  `load(named:clipFiles:)` puts a rig from one file together with clips from others. A file holding
  one clip has it renamed to the file's own name — the exporter's name is
  `root_A_MOD_BL_Walk_F_Femn_Animation_Base_Layer`. A clip that drives none of the rig's joints is
  dropped and reported; a missing clip file is reported, not thrown.
- **A clip file's skeleton is ignored, and that is the load-bearing part.** Its rest pose is wherever
  the exporter left the rig — measured, the same joint is (10.42, 4.08, 7.84) in the base file and
  (3.16, 1.17, 7.84) in the walk file. Merge them and every joint a clip does not animate stands
  wrong, and the fault changes as animations are added.
- **`AssetOrientation`** — Z-up and a hundred units to the metre, corrected by **one matrix in front
  of the model matrix**, which fixes the mesh, the rig and the clips together because skinning
  happens in model space. `MDLAsset` exposes `upAxis` and **not** `metersPerUnit`, so the axis is read
  and the scale is measured once and written down.
- **The sample's figure is now written the way a real export arrives** — Z-up centimetres, second
  clip in its own file, that file's rest pose deliberately wrong. It renders identically to the
  version it replaced, which is the point.

**What a real character still tests that the sample does not:** its material named no texture, so the
colour map ships beside it as a PNG the game binds by name. The file-carries-its-own-texture path is
proved by the sample alone.

## Done 2026-09-09 — versioning and a changelog

**`0.1.0` is the first version with a number**, and the repository can now be depended on by URL.

- **`Engine.semanticVersion`** is the single source of truth; `Engine.version` formats it, and
  `SemanticVersion` is `Comparable` and refuses to parse anything that is not `major.minor.patch` —
  `v0.1.0` included, because that is not what SwiftPM resolves.
- **`CHANGELOG.md`**, Keep a Changelog format, with 0.1.0 covering everything so far and a list of
  the gaps a consumer will look for and not find.
- **A test is what keeps it honest.** `ChangelogTests` fails if the newest entry is not the version
  the engine reports, if entries are out of order, or if there is no `Unreleased` section. Nothing
  in a build cares whether a changelog was updated, so discipline was never going to be enough — and
  a changelog that has fallen behind is worse than none, because a reader believes it.
- **The pre-1.0 rule is written down**: minor carries breakage, patch is additions and fixes, so a
  consumer pins `.upToNextMinor(from: "0.1.0")`. **The conventions count as API** — reversed-Z, the
  depth clear value, the vertex-descriptor contract — because changing one makes a consumer's game
  compile and then draw nothing.
- **Tagged `0.1.0`**, no `v` prefix.

## Done 2026-09-09 — materials and textures

**The largest routine gap after animation, closed the same day.** Surfaces come from the files that
name them, and the sample is textured throughout.

- **`Material`** — the metallic-roughness set (base colour, metallic, roughness, emissive) plus where
  each map lives. A value type with no device, read from `MDLMaterial`.
- **`TextureSlot`** — which map a texture is, and therefore whether it holds **colour or numbers**.
  `isColor` decides sRGB decoding once, for everybody. Decode a roughness map as sRGB and 0.5 arrives
  as 0.21; the whole scene looks wet and it reads as a lighting bug.
- **`TextureStore`** — loads once, caches by file *and* by that decision, generates mipmaps, and
  carries the 1×1 white and flat-normal fallbacks so a shader can always sample without a branch.
- **`MeshLoader` returns a material per submesh** instead of discarding what the file said.
- **The sample** textures every surface: `box.obj` names `crate.png` through its `.mtl`, the figure
  names `figure.png` through a `UsdPreviewSurface` — two formats, one code path. `Tools/make_sample_textures.py`
  draws all four PNGs with nothing but the standard library, so the no-asset-dependency rule holds.

### Three things measured about Model I/O's materials

1. **Two properties can share one semantic.** A textured diffuse arrives as a float3 `baseColor` *and*
   a texture `diffuseColor`, both `.baseColor`; `property(with:)` returns whichever it reaches first.
   Read `properties(with:)` and take the **first**, which is the authored one rather than the
   invented one.
2. **The invented default is 0.18 grey.** Multiply a texture by it and the asset arrives at 18%
   brightness. A slot with a map takes a white tint.
3. **A texture property's type is `.string` before `loadTextures()` and `.texture` after** — so
   recognise a map by it having a URL, not by its type.

### And three from the sample

- **`half` is a type in MSL**, and naming a half-vector that fails with an error about declaration
  specifiers.
- **A `float4` vertex attribute wants a 16-byte-aligned offset**, which puts the skin weights before
  the joint indices in memory although the shader declares them the other way round.
- **Identity tints stop working once surfaces are textured.** The sample tinted by level tag; against
  a map, a ground tint of 0.32 took the courtyard to a sixth of its brightness. The tint now says only
  what a file cannot know — objective state and editor selection.

### What is deliberately not here

**No material *system*** — no shader graph, no permutations, no pass model, no authoring. The
parameter set is settled and shared by every format; the system around it is the contested part.
**And nothing binds a normal map yet**: the slot, the sRGB rule and the flat-normal fallback exist,
but it needs tangents in the vertex layout and a mesh worth mapping.

## Done 2026-09-09 — skinned animation

**The biggest gap is closed: a game with a person or a creature in it can use this engine.** Four
types, 37 new tests, and the sample uses every one of them through the public API.

- **`Skeleton`** — joint paths, parentage *derived from the paths* and checked rather than trusted,
  the rest pose, and inverse bind matrices with any geometry bind transform folded in.
- **`AnimationClip`** + `JointTransform`, `JointTrack`, `AnimationBinding` — keys with binary-searched
  sampling, and a clip's joints matched to a rig's **by path, once at load** rather than per frame.
- **`SkeletonPose`** — samples one clip, cross-fades two, or takes a pose outright; produces local,
  model-space and skinning matrices. Allocates nothing per frame.
- **`RigLoader`** — skeleton and every clip out of a USD file, **with no GPU**, which is what makes
  the half with all the convention in it testable against a real fixture.
- **The sample** draws figures placed by `figure` markers in both levels: idling, cross-fading into a
  wave as the player comes within 7 m, and casting **skinned shadows** through the same cascades.
  Its rig is written by `Tools/make_sample_figure.py` — 11 joints, two clips, a readable `.usda`.

### Three findings, each of which produces a wrong character rather than a failed build

1. **`MDLSkeleton`'s two transform arrays are in different spaces** — rest is joint-local, bind is
   skeleton-space. **They hold the same numbers in any rig rooted at the origin**, so a test rig that
   does not separate them passes while wrong. `Tests/…/Resources/offset-rig.usda` puts its root at
   (5, 0, 0) for that reason alone.
2. **Clips are not in the object hierarchy** — they come from `MDLAsset.animations`. Walk the objects
   looking for them and every character is a statue.
3. **`MDLAnimationBindComponent.jointPaths` is empty** even with the skeleton attached; the paths are
   on `MDLSkeleton.jointPaths`.

Two smaller ones: **times arrive in seconds**, converted from the file's time codes; and **asking for
four influences when the file authored two is safe** — Model I/O pads with joint 0 at weight 0.

### What was deliberately left out, and why

**No animation state machine, no retargeting, no IK, no root motion.** Cross-fading two clips is a
settled shape; *choosing* which two is not, and there is nothing to design it from — the sample has
two clips and a distance check. See the README section, which says what a bought character would test
that a generated one cannot.

## Done 2026-09-08/09

- **Levels are files.** `courtyard.json` and `ruins.json` ship in `WindageSampleCore`'s resources and
  load through `Level.load(named:bundle:)`. Loading writes nothing; the editor's save shadows the
  shipped level and says so, and ⌘⌫ discards it.
- **`FontAtlas` is no longer ASCII-only by force.** It takes `additionalCharacters`, reports what the
  font could not supply, and an unmapped character logs once instead of silently drawing nothing.
- **`ShadowCascades` extracted**, and its constants became parameters in the move.
- **The sample draws shadows** — four cascades, front-face culled, 3×3 comparison filtering, blended
  across the splits. It found a real fault before drawing anything: the constant depth bias was in
  normalised depth units and so scaled with `lightDepthRange` — sixteen metres of bias in a courtyard
  three metres tall. It derives from the world size of a texel now.
- **The repository was decoupled from the games it came from.** Nineteen doc comments and a README
  full of one studio's product names, roadmap and folder paths, rewritten to describe consumer
  *shapes*. Three paths pointed at a directory that does not exist in this repo.

## The roadmap, and the rule that produces it

**`README.md` §"Where this engine actually stands" is the real answer to "what is missing".** Read it
before planning anything — it enumerates the gap honestly (this is ~3,800 lines; Godot is ~a million)
and sorts what is missing into three buckets:

- **Settled shape** — everybody's version looks alike, so build it on a roadmap. No game has to ask.
  Post-processing, particles, a character controller, LOD, object parenting, normal mapping.
- **Contested architecture** — ECS, a scene node model, scripting, *animation state*. Defer, and say
  so; shipping without them is the norm, not a shortcut.
- **Enormous cost** — an editor application, a second platform, physics, networking. Business
  decisions with the cost written down.

> **"Nothing gets built until a game needs it" was too blunt and is corrected.** It is circular while
> an engine is small: nobody needs what nobody can use. Only the *contested* bucket waits on a game.
> Skinned animation is the worked example — it was in the settled bucket, it was built engine-first,
> and the sample found every fault in it.

## Next — in order

1. **Post-processing and a tone-map curve.** Listed in the README as settled shape: an engine that
   renders past 1.0 and writes it straight makes every lit surface clip identically, and each game
   currently supplies its own answer or none.

2. **Metallic, roughness, occlusion and emissive maps still have no consumer.** The slots exist and
   `TextureStore` resolves them; the sample binds base colour and normal and reads the other three as
   scalars. A metallic-roughness *map* is the same wiring again and needs an asset that has one.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
