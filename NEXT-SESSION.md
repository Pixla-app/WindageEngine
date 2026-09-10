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

218 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop, a save — and now **animated
characters** — all against the public API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`, **`Skeleton`,
`AnimationClip`, `SkeletonPose` and `RigLoader`**, and **`Material`, `TextureSlot` and
`TextureStore`**.

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

1. **A real character exists, and it exposes three gaps.** An 87-joint rigged character is available
   as `.usdc` with five clips in separate files, and it was probed on 2026-09-09: the skeleton, the
   weights, the UVs and a non-identity geometry bind transform all come through. What does not work
   yet, and is genuinely engine work rather than a game's:

   - **Clips live in one file each**, and each of those files carries a whole copy of the mesh and
     the skeleton. `RigLoader.load` reads one file and returns skeleton *and* clips, so loading six
     clips means parsing six copies of a 34,650-vertex mesh. **Needs a way to read clips alone and
     bind them to a skeleton already loaded** — `AnimationBinding` matches by path, so the mechanism
     is there; the entry point is not.
   - **The rest pose differs between those files.** The same joint reports a different rest
     transform in the base file and in a walk file, because a clip file's rest pose is whatever the
     exporter left the rig at. **The skeleton must come from the base file**, which is a rule
     nothing currently states or enforces.
   - **It is Z-up and in centimetres** — 176 units tall, `upAxis` (0, 0, 1). Model I/O does not
     convert either. Every real export from that toolchain will be like this, so an import transform
     (scale plus up-axis) is a settled, cheap thing the engine should own rather than every game
     rediscovering it.

   Its material also names no texture: the colour map ships beside it as a PNG the game binds by
   name. That is normal and fine, but it means the file-carries-its-own-texture path stays proved
   only by the sample.

2. **Extract the shadow pass. It is one thing implemented twice, and that is a defect.** The
   *arithmetic* has been in the engine since `ShadowCascades`; the **pass** — the texture, the
   pipelines, the per-cascade encoder loop — exists in the sample and again in a game, and a fix to
   one does not reach the other.

   **This was previously parked as "waiting for a third consumer", and that framing was wrong.** It
   is not speculative: the code is written, working and tested in two places, and the only open
   question was what varies between them. **That question is now answered**, by this session rather
   than by a third copy — teaching the sample's pass to draw skinned meshes forced exactly the
   abstraction the seam needs. What varies is the **vertex layout** and the **per-object bindings**,
   and `SampleShadowMap.Batch` — a pipeline, a count, and closures giving a mesh, a uniform address
   and an optional joint-palette address — serves two completely different vertex layouts through one
   encoder.

   So: lift `SampleShadowMap` into the engine with `Batch` as its interface, leave the *pipelines*
   with the game (they are compiled against the game's shaders and its vertex descriptor), and the
   sample keeps only the half that is genuinely its own. A game replacing its copy afterwards is that
   game's work on that game's schedule — this repository does not wait on it.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
