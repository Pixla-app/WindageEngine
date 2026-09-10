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

199 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop, a save — and now **animated
characters** — all against the public API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`, and **`Skeleton`,
`AnimationClip`, `SkeletonPose` and `RigLoader`**.

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
  Materials and textures, post-processing, particles, a character controller, LOD, object parenting.
- **Contested architecture** — ECS, a scene node model, scripting, *animation state*. Defer, and say
  so; shipping without them is the norm, not a shortcut.
- **Enormous cost** — an editor application, a second platform, physics, networking. Business
  decisions with the cost written down.

> **"Nothing gets built until a game needs it" was too blunt and is corrected.** It is circular while
> an engine is small: nobody needs what nobody can use. Only the *contested* bucket waits on a game.
> Skinned animation is the worked example — it was in the settled bucket, it was built engine-first,
> and the sample found every fault in it.

## Next — in order

1. **Materials and a texture path.** The largest remaining *routine* gap, and now the one holding the
   sample back visually: every consumer hand-rolls albedo/roughness uniforms and its own texture
   loading, and the sample's characters are one flat colour because there is nowhere to put a skin.
   Settled shape — no game has to ask.

2. **A bought rigged character, once one is worth buying.** The generated figure proved the API; what
   it cannot test is a hundred joints, four influences per vertex genuinely in use, a non-identity
   geometry bind transform, and whatever a real exporter does. **Buy USD, or FBX with a Blender step
   — OBJ carries no skeleton.** Not a blocker for anything; a confidence check on the loader.

3. **The shadow pass seam.** It is implemented twice now — here and in a game — and the sample's copy
   has since grown a *second* pipeline for skinned geometry, which is new evidence about the seam:
   what varies is the vertex layout and the per-object bindings, and the batch shape in
   `SampleShadowMap.Batch` is one answer to it. **A third implementation would still answer it better
   than a second one guessing**, so this waits unless something else needs a shadow pass first.

4. **Semantic versioning and a changelog.** Stated in the README as worth doing from the first
   outside consumer — cheap now, impossible to reconstruct later. Not started. The window title
   already says `0.1.0`; nothing else does.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
