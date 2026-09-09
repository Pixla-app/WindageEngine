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

> **That is about where problems get *found*, and it is not licence to write a game's name in here.**
> The two are separate and both hold: a game is the discovery ground, and this repository still
> mentions none.

What that means for the next session, concretely:

- **The engine's roadmap is its own.** It comes from the gaps listed below, not from what some game
  happens to want this week.
- **`WindageSample` is the proving ground.** A capability is not finished until the sample uses it
  through the public API. That is what has caught every real bug so far.
- **A game adopts afterwards.** If a game already has its own version of something the engine now
  owns, replacing it is that game's work, on that game's schedule — not a prerequisite here.
- **A second sample arrives only when a capability needs a shape the courtyard cannot express.**
  Skinned animation is the first genuine case: a box cannot show a skeleton.

## State — 2026-09-09

162 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop and a save — all against the public
API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`.

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

## Next — in order

1. **Skinned animation.** The single biggest gap: no game with a person or a creature in it can use
   this engine. **Probed 2026-09-06 and found tractable — Model I/O does import UsdSkel**; see the
   README section, which has the working `.usda` and what came back.

   **This one is legitimately engine-first**, and the rule against speculation does not block it:
   that rule is about *architecture* with no single right answer, and skinned animation has a settled
   industry shape — skeleton, bind pose, joint palette, one matrix per joint per frame. Build it
   here, prove it in the sample.

   **It is also the first real case for a second sample**, because a courtyard of boxes cannot show a
   skeleton. Expect a small `WindageSampleCharacter` or an added mesh in the existing one — decide
   which when the loading works, not before.

2. **The shadow pass seam.** It is implemented twice now — here and in a game. What the two agree on:
   the depth texture array, the front-face cull, the reversed-Z depth state, the slope-scaled bias,
   the per-cascade pass descriptors. What they do not: how a game binds its own vertex layout and its
   own per-object uniform buffer. That is the seam. **A third implementation would answer it better
   than a second one guessing**, so this waits unless something else needs a shadow pass first.

3. **Semantic versioning and a changelog.** Stated in the README as worth doing from the first
   outside consumer — cheap now, impossible to reconstruct later. Not started. The window title
   already says `0.1.0`; nothing else does.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
