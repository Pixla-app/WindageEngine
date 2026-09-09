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

## State — 2026-09-09

162 tests. `WindageSample` is the engine's own game and the standing check that the public API is
usable by somebody who did not write the engine.

**What is in the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`.

**What the sample shows:** a lit, shadowed scene with a moving camera, two levels loaded from JSON,
an in-game level editor, positional audio, a win/lose loop and a save — all against the public API.

## Done 2026-09-08/09

- **Levels are files.** `courtyard.json` and `ruins.json` ship in `WindageSampleCore`'s resources and
  load through `Level.load(named:bundle:)`. They were Swift functions written to Application Support
  on first run, which taught the opposite of what the format claims. Loading writes nothing now.
- **`FontAtlas` is no longer ASCII-only by force.** It takes `additionalCharacters`, reports what the
  font could not supply, and an unmapped character logs once instead of silently drawing nothing —
  which had been eating every keyboard symbol out of the sample's hint lines.
- **`ShadowCascades` extracted.** Splits, light basis, texel snapping, per-cascade bias, blend bands.
  Its constants became parameters in the move, which is the whole value of extracting it.
- **The repository was decoupled from the games it came from.** Nineteen doc comments and a README
  full of one studio's product names, roadmap and folder paths, all rewritten to describe consumer
  *shapes*. A README that told a cloner to look in `~/PixlaGames/` was describing an engine nobody
  else could own.

- **Shadows in the sample.** Four cascades, front-face culled, 3x3 comparison filtering, blended
  across the splits. It found a real fault before it drew anything: the constant depth bias was in
  normalised depth units, so it silently scaled with `lightDepthRange` — sixteen metres of bias in a
  courtyard three metres tall, and no shadows at all. It derives from the world size of a texel now.
  Both levels' suns moved to the side, in the level files, because a sun behind the camera hides
  every shadow behind its own caster.

## Next

1. **The shadow pass is implemented twice now** — here and in the game it came from. What the two
   agree on is the texture array, the front-face cull, the reversed-Z depth state and the
   slope-scaled bias; what they do not is how a game binds its own vertex layout and per-object
   uniforms. That is the seam to find, and a third implementation would answer it better than a
   second one guessing.
2. **Skinned animation** — the single biggest gap. Probed 2026-09-06 and found tractable: Model I/O
   does import UsdSkel. See the README section.
3. **Semantic versioning and a changelog**, from the first outside consumer. Cheap now, impossible to
   reconstruct later. Not started.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
