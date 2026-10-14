# Windage Engine — Next Session Handoff

**Read `README.md` first.** It holds the standing decisions and the reasoning; this file holds only
what changed recently and what is next.

> **This repository stands alone, and that is a rule rather than a description.** It builds, runs and
> tests with no game checked out. Capabilities arrive by being *extracted* from a working game — that
> is the quality rule — but nothing that arrives keeps the name of where it came from. If a doc
> comment, a test or this file starts naming somebody's game, that is a regression: rewrite it to
> describe the *shape* of the consumer instead. The reasoning is what is worth keeping; the product
> name is coupling.

**Run it:** `swift run WindageSample` · **Test it:** `swift test` · **Walk it:** `python3 Tools/walks.py`
· **Look at it:** `python3 Tools/frames.py` — four recorded viewpoints drawn with no window and compared
pixel by pixel (`--record` to redraw them, and then look at what changed).
— every documented walk, run invisibly, failing on more than 2 cm from its record. **Run it before
committing anything that touches the sample's levels or the controller**, and add an item's proof walk
to `Tools/walks.json` when it is measured. A walk may name the step `rates` it has to hold at — the
course walk gives one set of numbers at 30, 60, 120 and 240 (`WINDAGE_SAMPLE_RATE`), and its segments are
whole steps of the slowest, because a key can only be held for whole steps.

**Reproduce a screenshot:** `WINDAGE_SAMPLE_LEVEL=1 WINDAGE_SAMPLE_CAMERA=-4,20,4,0,-62 swift run
WindageSample` — level index, then `x,y,z,yaw,pitch` with the angles in degrees. **A camera placed
this way flies** — a screenshot position is a viewpoint, not somewhere to stand, and gravity would
pull it to the floor before the first frame.

**Walk it without a keyboard — or a controller:** `WINDAGE_SAMPLE_LEVEL=1 WINDAGE_SAMPLE_WALK="d:0.75 w:1.0 w:0.4 wait:1"
swift run WindageSample` — key names and seconds, **pressed through the same path a keyboard uses**,
and the log says where the feet ended each segment. **It keeps time with its window hidden** (2026-09-11). `o:0.1 return:0.1 i:0.1 o:0.1` opens settings and
rebinds forward to I; `pad.south`, `pad.menu`, `pad.down` press a virtual controller, which then
counts as connected. **A script that changes settings writes the real settings file** in Application
Support; delete it afterwards.

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
- **A game that an engine change reaches is brought up to date in the same pass** (2026-09-11,
  replacing "on that game's schedule", which is how one fell so far behind it no longer compiled). If a change
  breaks a game's build, changes what it draws or how it behaves, or makes a copy it holds wrong, the
  pass is not done until that game builds, passes its own tests and has been run and looked at — in
  **its** repository, through **its** handoff, never from here. Swapping a game's *working* copy of
  something for the engine's, for tidiness, is still that game's call. Check every game that depends
  on the engine, not only the one in mind.
- **A second sample arrives only when a capability needs a shape the courtyard cannot express.**
  Skinned animation was expected to be that case and **was not** — what it needed was a character
  standing *in* the courtyard, not a second scene around it. The bar is higher than it looked.

## Done 2026-10-13 — the public API audit, fixed (Unreleased)

**`API-AUDIT.md` is the record**: 133 findings across the public API, reviewed before 1.0 and fixed with the
owner's approval in four area passes plus a consistency pass — **128 done, 5 declined with reasons, none left
for the owner.** Every change is in `CHANGELOG.md` under *Unreleased*, which is now the 1.0.0 entry. Every
consumer was followed in the same pass: Coldkeel now owns its sniper controls (`ColdkeelCore/Controls.swift`),
Worldra follows the new shadow and math API, and the rigs build. Checks: 666 + 50 tests, 20 walks and 5 frames
as recorded; Worldra's forest frame byte-identical to before.

**Not released — nothing is.** The engine reports 1.0.0, the version its first release will be;
`CHANGELOG.md` has one *Unreleased* section ("Initial release") and there are no tags. When 1.0.0 ships is the
owner's, in **Pixla Games Control's Releases window** (2026-10-13): Cut runs the tests and tags, Publish pushes,
Make Public is the one-time switch — a session never does any of them. Ready for it: `LICENSE` is PolyForm
Small Business with the credits line as its Required Notice, the docs name `github.com/Pixla-app/WindageEngine`,
and `web/` is the site to upload. **No repository is backed up yet** — Repos ▸ Create backup, before anything.
Above PolyForm's thresholds: legal@pixla.app, no price set (owner, 2026-10-13).

## Done 2026-10-13 — the docs, written (Unreleased)

**windageengine.com's docs are complete**: 29 guides (every sidebar topic, plus loading meshes, the camera,
sky and environment, particles, instancing, level of detail, culling and saving), a reference page of every
public type linked to its guide, the changelog as a page, search (box or ⌘K), and a Contents menu on phones.
Sources in `Tools/docs-src/`, built into `web/` by `Tools/build-docs.py` — **run it after changing a guide, the
changelog or a public type**. Every Swift identifier in the examples exists (checked by script); Your first
game was built and run. **Doc comments are US English now** (the sweep the owner scheduled for publication),
and four that had stopped being true were corrected. Comments only — no consumer can be affected.

> **Found while writing, not changed:** `SprintLatch` is public, but has no public `init` and its
> `isEngaged` is not public, so a game can neither make nor read one. Either it should be internal or it
> needs both. Raised with the owner.

## Done 2026-10-13 — the British names removed

The deprecated British aliases (2026-10-12) and the level reader's `colour` key are deleted, at the owner's word: no one outside the
studio uses the engine yet, and every game here was already on the new names. A rule for later, once there are
outside users: **deprecate for a release before removing**, as the renaming on 2026-10-12 did.

## Done 2026-10-12 — public names in US English

`color`, `center`, `unitsPerMeter` throughout the public API; the British names forward, deprecated
(`Deprecated.swift`) — deleted the next day. Level files write a light's
`color` and still read `colour`; the sample's levels are converted. Renamed in code only: **doc comments are
still British, to be swept when the docs are published** (owner, 2026-10-12). 596 tests (2 new: old levels
open, old names forward); 20 walks and 5 frames as recorded. **The consumers caught two faults in the aliases
before anyone else could:** they inherited the package's main-actor default, so background code using `centre`
stopped compiling (now `nonisolated`, as their types are), and `ring`'s alias renamed a `color:` label that was
never British.

## Done 2026-10-12 — level of detail

**`MeshDetail`**: up to ten tiers of a loaded mesh, each with its own vertices and normals recomputed from its
own faces, and `choose` — the coarsest tier under half a pixel of error. Built on **meshoptimizer 1.3's
simplifier, vendored unmodified as the `MeshOptimizer` target** (MIT; an app shipping it ships its license).
Extracted from a world editor's woods: 1,000 trees of 19,000 triangles, 25 → 5.6 ms on an M2. Three things
learned there, written into the doc comments: **permissive** simplification, because low-poly assets split
every vertex at every hard edge; **recomputed normals**, because kept ones drew far copies nearly black; **half a
pixel**, because at one a wood of six-pixel trees visibly lost its tiers of branches. 6 new tests, one loading a
real mesh. **Not in the sample** — nothing there is far enough away to switch; see the CHANGELOG.

## Done 2026-10-12 — a self-drawing batch knows its pass

`ShadowMap.Batch`'s `encode` closure gets a `ShadowMap.Pass` (index, light view-projection), so a batch can
cull to each cascade, tile or face. Measured in the consumer it came from: a wood's shadows drawn whole into
four cascades were three quarters of a frame; culled per cascade, the frame went from 75 to 25 ms.

## Done 2026-10-12 — shadows for self-drawn geometry

`ShadowMap.Batch(pipeline:encode:)` — a batch that encodes its own draws, for instanced copies and for a
mesh a game builds itself; `ShadowAtlas` and `ShadowCubes` draw it whole. `BufferIndex.instances` (4).
`updateMatrices(frameSlot:cameraPosition:cameraForward:sunDirection:)` for a view that is not a `Camera`.
The sample's debris casts through it. 638 tests; 20 walks and 5 frames as recorded (redrawn for the debris's
shadows). Followed into every consumer the same day.

## Done 2026-10-12 — instancing

**`InstanceBatches` and `InstanceBuffer`**: copies grouped by kind in a fixed order, and a per-frame
buffer of their transforms that grows and keeps its residency. Extracted from a world editor's scatter
brush, where it drew woods of hundreds of trees; proved in the sample, which strews ~100 pieces of debris
round each level as one batch. 10 new tests (5 engine, 5 sample core). **LOD is not done** — nothing has
lower-detail meshes yet.

**The sample had stopped finding its resources.** Xcode 27's SwiftPM copies a `.copy("Resources")` folder
one level deeper, and lookups by name missed it: no meshes, no sounds, no figure, every frame failing.
`.process("Resources")` puts them back where they are looked for. **The splash frame is redrawn for 3
pixels** of the host font's edge shading, which moved with macOS 27.

Followed into every consumer the same day — see the CHANGELOG and each one's handoff.

## State — 2026-09-15

626 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop, a save — and now **animated
characters** — all against the public API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`, `Skeleton`,
`AnimationClip`, `SkeletonPose` and `RigLoader`, `Material`, `TextureSlot` and `TextureStore`,
`ToneMapping`, `ProceduralSky` and `EnvironmentMap`, `PunctualLight` and `LightSet`,
`ClusterGrid` and `ClusteredLights`, `TransformHierarchy`, `CharacterController`, `ParticleSystem`
and `ParticleRenderer`, `InputBindings`, **`PadBindings`** and `PlayerSettings`, and — for the lamps that cast —
`ShadowMap`, `ShadowAtlas` and `ShadowCubes` — and, since 2026-09-12, **`EngineMark` and `SplashScreen`**,
with the mark itself in `Brand/`.

## Done 2026-09-15 — the Drift W

**The mark is a W with its right half carried up 16%** — chosen from six directions drawn as a 1024 icon, a
Dock, a 16 px tab rendered into real pixels, and a splash on dark and on white. The 2026-09-12 diagram of a mark read
as a chart and died at tab size. `EngineMark.outline` is the construction (five centre-line points, a stroke
width, corners where edges meet, ends cut flat); every file in `Brand/` — two one-tone marks, the app icon, the
favicon — is written from it and checked. **No hue, no accent** (an accent split the letter in two). The whole
selection, with the reason each rejected direction lost, is in `Brand/README.md`.

**Two engine pieces a letter needed.** `HUDRenderer.fill(polygon:color:feather:)` — ear clipping (a fan
spills between the W's arms) and a one-unit feather, because the HUD has no multisampling and the W came out
stair-stepped on its own splash. Proofs: unfeathered, the splash frame fails at 0.12%; a fan fails four tests;
the offset at 10% fails all four `Brand/` files and the frame at 0.16%.

**The splash is one line across** — `MADE WITH` · W · `WINDAGE`/`ENGINE` — and **no version by default**: no
engine's shipped splash shows one. The name is still set in the host's font; there is no drawn wordmark.

**`web/`** — `windageengine.com`, the folder that is uploaded, from the concept chosen: the product page's first
screen ("Native to the Mac. Nothing in between.") and a game as a Swift file, then the proof-led argument ("A
game engine that shows its work": the jump at four rates, the stale shadows, what's in it and isn't, how it's
checked), and the docs' first page in their own shape. **Four things in it are ahead of the facts** — the
licence, the package URL, the numbers, the placeholder imagery — listed in its README. No game is named on it.

## Done 2026-09-12 — the engine says its own name

**`EngineMark`** (the device, as geometry — a straight rule where a shot was aimed, a square where it
left, a path carried off it, a square where it arrived; drawn from the HUD's own primitives, so no
texture, no resource, no pipeline), **`SplashScreen`** (fade, hold, fade, `skip()`, a `lead` line), and
**`Brand/`** — two SVGs and the rules. **The SVGs are written from `EngineMark.pieces`** and a test fails
if they and the code disagree: `WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests`.

**Achromatic, on purpose.** Every title has a colour lane and a title's accent outranks everything inside
it; this mark appears inside somebody else's game, so a hue of its own would be a second brand competing
with the one the player came for — and it would spend a lane the studio has not got many of.

**Two things the pictures found that the arithmetic did not, and both are worth carrying.**

- **A polyline drawn as a strip of quads has a seam at every joint.** A wedge as wide as the turn, zero
  at the stroke's centre and `(t/2)·tan(Δθ/2)` at its edge. A comment of mine called that "under a tenth
  of a pixel at any size" — arithmetic done without looking. At a splash filling a 1440-point window it
  is two thirds of a point and the curve came out **visibly hatched**. Segments overlap by a twentieth of
  their length now, never past the ends of the path.
- **The frame check's tolerance is sized for a lit scene and cannot see a mark move.** Nudging the
  curve's end by 4% of the mark's height changes **a quarter of a percent** of a 640 × 400 frame — well
  inside the half-percent that is right for a scene with a GPU's last bit in it. A frame may carry its
  own tolerance now; the splash's is `pixels: 0, channel: 2`, and it catches that nudge.

**Proved by failing**, four ways: the mark nudged fails the splash frame *and* both SVGs; the splash
turned off fails the frame; a splash that swallows the press that skips it makes the 17th walk stand at
the spawn and fail all three of the crate walk's numbers (the ordinary crate walk passing beside it);
and a fat finger on the fade lengths fails the two rules taste is not allowed to break — under three
seconds, and less time fading than being read.

**Looked at, which is how the seam was found**: run, the splash up, the splash gone and the game playing
behind it with its clock already counting — the sample deliberately does not pause, which is what makes
the walk worth anything.

## Done 2026-09-12 — one course, four rates, one set of numbers

**No engine code changed, and that is the result.** The capstone (`OneCourseTests`) walks, jumps, climbs
three treads, sprints, slides, goes off a cliff and lands, at 30 / 60 / 120 / 240 steps a second: it ends
at the **same 63.283 m** (the parts added up: 18 + 9 + 16.138 + 0.945 + 19.2), lands at **6.3, 6.928 and
10.954 m/s**, reaches **0.9923 m** in the jump and puts a foot down **14 times** — everything computed
first, since four wrong answers can agree. Switched off: the old flight fails the jump and all three
landings at every rate; the old landing speed fails every landing (0.41 m/s out at 30); the old slide
fails the ending at every rate (0.246 m short at 30).

**Walked in the ruins too**, as a 16th walk run at all four rates (`Tools/walks.py` takes `rates`): up
the stairs, off the landing, a jump, a sprint, a slide — **every line identical at 30, 60, 120 and 240**,
the slide ending 16.81 m along at x −19.81. `WINDAGE_SAMPLE_RATE` is new.

**The measurement found the walk runner rounding badly.** A 0.75 s strafe covered 4.40 m at 30 steps a
second where it covers 4.50 at 120 — a key can only be held for whole steps, and each segment was being
measured from the *last boundary*, so forty of those roundings could add up. Boundaries are absolute now;
all 15 recorded walks are unchanged at 120. What cannot be fixed is the rounding itself, so **a walk to be
run at several rates has its segments in whole steps of the slowest** — multiples of 1/30 s.

**Two things worth keeping.** The floor on any of this is the `Float`: a plain eight-second walk in a
straight line lands 0.1 mm from 48 m at 30 steps a second, 0.6 mm at 240, 1.8 mm at 480 — so a centimetre
is as tight as a course this long can be asked, and the course's 1.5 mm is that and nothing else. And
**a law whose clock starts at a collision cannot be pinned by a course**: the eye's settling is kicked by
a climb, the climb lands on whichever step first overlaps the tread, and `e^(−12·Δ)` over a 33 ms rounding
is a third either way. Switching the eye's exponential settling back to `1 − rate·dt` leaves the course untouched; it does move
what the sample prints (eye 1.70 m above the feet at the top of the stairs at 30, where it reads 1.69),
and that number is deliberately **not** recorded — it sits on the rounding of the printed centimetre.

## Done 2026-09-11 — the frames are a check, and a missing barrier

**`FrameRenderer.render(into:)`** (a frame into your own texture, GPU waited for), **`WINDAGE_SAMPLE_FRAME`**
(one frame to a PNG, no window, before any step), **`Tools/frames.py` + `frames.json` + four recorded
frames** (the ruins from above, the lintel, the courtyard, the turntable). 15 s; they match to the bit here.

**Drawing one found a real bug**: the scene pass sampled shadow maps a pass in the same command buffer was
still writing — Metal 4 tracks no hazard, and the engine had no barrier anywhere. In play it looked right
because the previous frame's maps are there (so every shadow was a frame stale); the first frame of all
came out differently every run — black, or blotched in cluster-sized squares. Two consumer barriers fixed
it: four runs, identical bytes.

**Two proofs that proved nothing, caught**: `ToneMapping`'s default curve (the sample sets its own) and
the constant depth bias × 25 (too small against a cascade's range) both left the frames identical. The
levers that do move it: the sample's own curve (98% of pixels) and the sun's casters not drawn (5.5–7.6%).

## Done 2026-09-11 — a slide covers the ground its curve says

**The step takes the slide speed's average over the step** (`∫ r^e dr`), not one reading of a falling
curve; a slide ending inside a step is spent for the part it lasted. The curve integrates to **16.138 m**:
before, 15.847 / 15.997 / 16.069 / 16.093 at 30 / 60 / 120 / 240 steps a second; now 16.050 / 16.138 /
16.138 / 16.121, the ends being the measuring window (the step a slide ends inside is over before it is
looked at — 0.088 m at 30 a second, exactly the gap). One test, all four rates failing on the old reading.

**Two traps, both in the test rather than the engine**: keys pressed by step index start the slide at a
different moment at each rate; and a tolerance of `sprintSpeed·dt` (0.6 m at 30 a second) would have
passed the old code at every rate — it is the crouched walk of one step, 0.09 m, that bounds the window.

## Done 2026-09-11 — the eye settles as the exponential it is

**`settling`, `bobCatchUp` and the bob's easing take `e^(−rate·dt)`** — a rate per second is an
exponential, and `1 − rate·dt` is its first two terms, zero at `dt = 1/rate`: at twelve steps a second the
eye closed the whole gap in one step. Up four treads: **1.640 m above the feet at 30 steps a second, 1.636
at 120**; the same at every rate now. Two tests (the share a step leaves, at 10/30/120; a second of it in
one step or a hundred), all failing on the old form.

**A test of mine that measured the wrong thing**: the first version compared the eye's height after a fixed
number of steps up stairs — which depends on where in the climb the sampling lands, not on the settle law,
and it failed at every rate. And the 10-steps-a-second case passed the *old* code until the test also
demanded there be a lag at all: both its readings were zero, which is the snap it was looking for.

**Nothing the walks record moved** — 15 walks, 79 expectations, the head bob included.

## Done 2026-09-11 — a landing hits at the ground's speed

**`√(v² + 2g·h)`**, the speed at the surface, not at the end of the step that crossed it (over by up to
g·dt). A fall from 1 m: **6.3246 m/s at 30, 60, 120 and 240 steps a second**, where it read 6.667 / 6.333 /
6.333 / 6.333. One test over four rates, all four failing on the old reading. The landing spring's kick is
made from it, so the dip is the fall's.

**In the sample**: the drop off the ruins' landing reads **6.9 m/s where it read 7.0** (it is 6.928) and a
jump's landing 6.3 where it read 6.4. **The walk check reads impacts and dips now** — the stairs-and-jump
walk carries both, and fails on the old reading, at 120 steps a second.

**A claim of mine corrected by the test**: I had written that the error at 120 was a millimetre a second
and the sample would not show it. It is up to g·dt — a sixth of a metre a second — and the sample showed
it in the first run.

## Done 2026-09-11 — the walk check sees the look

**The view's turns are checked** (to the hundredth of a degree; a segment that reports none is no turn —
a stick inside its dead zone). **Four walks recovered**: the sensitivity item's at defaults (91.67 / 45.84 /
63.03 / 25.21) and set from the pad (45.84 / −22.92 / 126.05 / 50.42); the dead-zone item's at defaults
(none / 2.26 / 18.11 / 91.67, and 0.11 m / 2.59 m) and at 26%–30% from the pad (none / 9.64 / 91.67, 0 m /
1.99 m). **15 walks, 79 expectations, 33 s.** Failing on purpose: the mouse's look scale doubled fails the
mouse's turns in both look walks, the stick's untouched.

**A gap in the check itself, found by a walk that measured the defaults twice**: the settings screen's pad
input is read in `beginFrame`, and a check draws no frames — so a scripted pad pressed its buttons and
nothing read them. A check polls the pad from its steps now. (The keyboard was never affected: its keys go
straight to the game, which is why the head-bob walk could set the bob.)

## Done 2026-09-11 — the walks run four at a time

**25 s for eleven walks, where one at a time took 122** — and `--serial` still there: **all 60 measured
values identical either way**. Two things it needed: **saves named after the walk**
(`WindageSample-check-<walk>`, or a walk launching clears the settings another just set — `SampleRun.store`'s
lesson again), and **no environment map in a check** (2.6 s of the 3.3 before a walk's first step; that
also took the serial run to 87 s). Found on the way: `--record` and `--serial` were being read as walk-name
filters, so `--serial` ran nothing.

**Still fails when it should**: the slider back where it was first placed fails the crate walk on (3.22, 5.28) and
now the head-bob walk too, whose path it also crosses; a wrong recorded number exits 1.

## Done 2026-09-11 — the same jump at any step rate

**A step of flight is stepped by its exact answer** (`y + v·dt − ½g·dt²`), not by the velocity the step
ends at, which lost ½g·dt² a step. Apex **0.992 m at 30, 60, 120 and 240 steps a second** (less the
sampling: 2.8 mm at 30), where it was 0.890 / 0.940 / 0.966 / 0.979. Two tests over four rates; all eight
cases fail on the old integration.

**The walks' jump heights re-recorded** — 0.97 → 0.99 and 1.90 → 1.92 — which makes the lift jump
rise the **1.17 m** it was computed to. Nothing else moved. **`Tools/walks.py --record`** (new) prints
what each walk gives now: the check's 2 cm tolerance would have let this change pass unseen, and did
until I looked.

## Done 2026-09-11 — the walk check hears footsteps and sees the head bob

**`Tools/walks.py` checks the lines under each segment**: footsteps (exact), surfaces (exact), head bob
(± the printed millimetre). **Three walks recovered from the transcript and logs, not retyped** — the head-bob
item's (walk 2.8 × 1.8, sprint 4.7 × 3.0, crouch 1.4 × 0.9, then off on the settings screen), the same at
50% (1.4 × 0.9, now set on the screen), the tread item's stairs down (4 up, 5 down, dirt/stone/wood) — plus no
footsteps riding the lift and none being pushed. **11 walks, 59 expectations, all hold.**
Failing on purpose: tread `abs` out → 3 against 5; bob a fifth smaller → all three gaits caught.

**A claim of mine, checked and wrong**: I wrote into `walks.json` that the head-bob walk's settings-screen
part had to be left out because the screen's rows had moved. Read: without a pad every row added since
(dead zones, stick rows, ambience) is pad-only or below Head bob, so the old key presses still land on it.
The full walk went in, and reproduced the head-bob item's "off" exactly.

## Done 2026-09-11 — a push in mid-air is kept

**Air push → `airVelocity`**, up to the pusher's speed along the push. **And the kept speed is the
pusher's** everywhere, not the step's displacement: at first contact that read a 1.5 m/s push 0.24 and
0.30 m/s wrong at two of five gaps (measured). The push-on-leaving numbers unchanged (a settled push agrees). Three
tests, each failing without its part.

**In the ruins**, jumping as the piston arrives: before, the player came down **on top of the piston**
(z −1.315, 2.05 m up); after, thrown clear to the ground at z −2.177. **My simulation was wrong first** —
the jump a step early, and no piston to land on (it predicted −2.164 on the ground, and the ground for the
before case too); fixed, it matched both outcomes to the mm. Frames of both. Eighth walk added; 8 of 8.

## Done 2026-09-11 — the sample uses `pinnedBy`, and a push bug it found

**The slider turns back when it pins the player** (`SampleLevel.SlideRun`, three tests; state kept outside
the rebuild, since collecting a crate rebuilds the level), against a **`"stop"`** crate at (−5.3, 7.9) —
placed after checking the documented walks: straight across the run's end it would have caught the push
walk, so it sits on the run's south side, 0.1 m off that walk's line. Content test for it.

**The first run found an engine bug.** Pinned 7 mm into the slider's face, the player was thrown 1.8 m
through it when it turned back and carried home behind it: the push went "the way it went, just clear" —
out the far side. **Push, and pin, only a body ahead of a solid** (nearer its leading face). A full-speed
reversal did not show it (out of the body in one step); a gentle one, as the eased slider makes, fails the
old code by 3.76 m. Every earlier push test and walk unchanged.

**Walked**: pinned at face −6.5947 (computed −6.595), feet −6.3012 held by the stop, left there as the
slider went home. **Seventh walk in `Tools/walks.py`** — which also had to learn a last segment label can
repeat (it stopped at the first `wait:3.0`). 7 of 7 hold.

## Done 2026-09-11 — the documented walks are a check

**`Tools/walks.json`** (six walks — crate, lift jump, stairs and jump, push, turntable rim, piston — with
21 expectations: feet after segments, highest points, report numbers) and **`Tools/walks.py`** (runs them,
fails on > 2 cm). All six hold, ~60 s. **Proved by failing**: slider back at (1, 8) → the crate walk fails
on (3.22, 5.28), the deflection found by hand, and the push walk fails too; exit 1. Restored.

**Checked, not guessed, on the way**: the stairs walk was dated from memory — `git log -S` found
it in **the body-with-feet item (2026-09-10)**, and the README's version of it went on to a jump that peaked at 0.97; the check uses that
whole walk now.

**`WINDAGE_SAMPLE_CHECK=1`** runs the sample invisibly: accessory app (a regular one became frontmost at
launch with no `activate` — measured), window never shown, silent, saves in `WindageSample-check`, cleared.
That needed **an engine fix**: the hidden clock waited for a first frame, which a never-shown
window never gets — it starts at the timer's first tick now. One test, failing on the old clock by 10 s.

## Done 2026-09-11 — a push is kept on leaving

**A push counts toward `groundVelocity` across** — shoved off an edge a body flies on; a jump while
pushed takes it. **And a found fix in the same line**: the vertical part was the carry's whole
displacement, so a carried body climbing a 0.3 m step read 36 m/s up (measured) — a jump then would
have left at 42. Vertical is the ground's own motion now. Four tests, each failing without its half.

**Proved in the ruins** by a new **piston** (`"piston"`, 1.5 m/s linear, `SampleLevel.pistonOffset`;
movers run along their placement's yaw now) on the landing's east side, shoving the player off the south
edge: before 0.050 m beyond (computed 0.050), after **0.512 m** (computed 0.512), landing z −2.315
(computed −2.314). Frames of both, looking back from where they came down.

**Placed after checking the documented walks**: a pusher across the landing's middle would have crossed
the stairs walk (x 4.5), the regression the slider made in the courtyard; this one runs at x 5.1–6.0. The
lift walk came out identical to its first recording and the stairs walk as recorded. **The first design — an eased
slider — was simulated first and dropped**: 0.219 m against 0.187 m, since a moving slider keeps pushing a
falling body. Only a pusher that stops shows what is kept.

## Done 2026-09-11 — kept out of App Nap

**The item's premise needed a correction first**: the hidden clock's "no App Nap in 87 s" had the sample's audio
engine running, and an app playing sound is exempt. So the measurement was of a **bundled, silent** app:
`Tools/bundle_sample_app.sh` (new; `.build/WindageSample.app`, ad hoc, `open`-launched) with
`WINDAGE_SAMPLE_SILENT=1` (new). And the rate report now gives the **longest wait between steps** —
steps a second read 120 in every case, since the clock credits the time a slowed timer skipped.

Hidden two minutes each: no activity — steady ~17 ms, then ragged from about a minute in, up to 120 /
78 ms (23 / 18 seconds over 25 ms); a user-initiated activity — milder, 165 / 54 ms (5 / 11); **adding
`latencyCritical` — 33 / 32 ms (1 / 1), steady throughout**, as steady as the app with sound (32 ms, 1).
`runsWhileHidden` now holds that activity while on. A third no-activity run was spoiled — the window was
clicked into view ten seconds in — and was run again rather than counted.

No test: the activity is the operating system's, and the measurement is the check.

## Done 2026-09-11 — round solids are round

**`Footprint.radius`**, `Footprint(center:radius:)`, `Footprint(discOf:)`; a disc collided as a rounded
square against the body's square (slabs and corner circles, entering at the first). The sample marks
`turntable` round (`SampleGame.roundMeshes`). Six tests; three fail with discs as their squares. A box
body meets a column face on and **stops** — honest, pinned by a test.

**The proof had to be timed.** At the first timing the square had turned 41°, a flat side facing the
approach, and square and disc agreed (2.418 both) — computed before running, and the walk given a wait
so the square's corner pointed along it. Then: square **3.068 m** (computed 3.068), disc **2.418 m**
(computed 2.418). Frames of both at the step up.

**A regression of mine, found by the rule of re-running old walks**: the push item's slider sat across the
turned-crate walk (ended (3.22, 5.28), not (3.21, −0.13)). Moved to x −12, z 9; the crate walk
reproduces again, and the push re-measured there matches. **A new placement in a level re-runs the walks
documented for that level.**

**And a scripted walk ignores the real keyboard.** Two runs stood at the spawn with every report
printing; four reruns did not. The window takes the keyboard when it opens, and a real Tab puts the game
in its editor — reproduced with System Events (walk frozen at (−0.74, 9.77)), gone with the guard. That
it was the cause of those two is likely, not proven.

## Done 2026-09-11 — pushed by something that moves

**A moved or turned solid that runs into a body pushes it** — along its displacement at the body, just
clear (2 mm), through collision with everything else, before walking, no footsteps; a low solid is stood
on instead. **`pinnedBy`** when a push is stopped — a property, because a new `Event` case would break
every exhaustive switch (the sample has one). **A change in behaviour**: worlds with motion now come out differently next
to moving things, as keeping the platform's motion did for jumps.

Six tests: four fail with the push off (checked), two are guards. **Pushed in the courtyard** by a new
slider (`"slider"` tag, `SampleLevel.slideOffset`, 5 m eased over 4 s): its face within 3 mm of the
computed curve at every sample, the feet 0.302 m ahead each time and at its speed to the mm/s (1.843,
1.849, 1.620, 1.157, 0.460), left at 7.05 (computed 7.052) when it went back. Two frames: nose to its
face mid-push; then it pulling away. A content test keeps its run clear of every other solid and the
spawn.

**Two faults in the measuring, not the feature**: the report's speed read 0 — the previous feet were
stored where the report reads them, at the start of a step; and the first screenshots failed, the window
looked up before macOS listed it.

## Done 2026-09-11 — a clock while the window is hidden

**The item's diagnosis was wrong, and measuring first is what showed it.** It said a hidden window's
display link was throttled and the 0.25 s ceiling threw the time away, and proposed lifting the ceiling
while a script ran. Hidden with System Events (`set visible … to false`, after the first frame — the
first attempt hid it before the window existed and measured nothing), the display link delivered **no
frames at all** for 10.2 s, then one frame reporting 10.23 s, 30 steps kept. Nothing to lift a ceiling
for. The old crawls fit a window behind others getting an occasional frame.

**`FrameRenderer.runsWhileHidden`** (off by default): a timer steps the simulation once the display
link has been quiet 0.1 s, without drawing or `beginFrame`. The crediting is **`FrameClock`** (internal),
tested alone — four tests; crediting up to *now* fails two of them by exactly the 48 ms lead, no timer
fails two. That lead was found in the sample first: 125 steps in the second the window came back, 120
after the fix. The sample turns it on for any scripted walk, and `WINDAGE_SAMPLE_FPS` reports from steps
too.

Measured (`hiddenrun`: the crate walk, window hidden from its first frame to 20 s):

| | hidden | walk |
|---|---|---|
| off | no frames; one back crediting 16.5 s → 30 steps | opening 2 s wait ended at 21.4 s |
| on | **0 frames, 119–121 steps/s** | on the wall clock, 6.59 s for 6.5915 s, ending at the crate's face |

87 s hidden: 120 steps/s throughout, no App Nap — for the sample as a terminal-started executable. A
bundled app hidden is unmeasured; if one ever naps, `ProcessInfo.beginActivity` is the answer, measured.

## Done 2026-09-11 — a turned crate stops you at its face

**`Surroundings.footprints`** — each solid's plan, a rectangle turned about the vertical
(`Footprint(of: Volume)`, nil for a tilted one) — and collision against it by separating axes. Standing,
headroom and support use it too. **A move into a turned face slides along it** for the rest of the
step: at an angle both axis moves hit the face, and without the slide the body stuck. Additive — a world
without footprints passed all 557 earlier tests untouched.

Six tests: four fail with footprints ignored (checked), two with the slide off (checked); the other two
check `Footprint(of:)` and that an unturned footprint collides exactly as its box.

**The handoff's own prediction was wrong, and was corrected before measuring.** It said the walk would
stop "0.30 m (the body's radius)" from the face — true of a round body. The body is a box, and at 45°
its corner meets the face: h + r(|cos|+|sin|) from the centre. Walked in the courtyard, square at the
face of the crate turned 45.8°, window in front:

| | held up | from the real face | then |
|---|---|---|---|
| box alone | z −1.64 (computed −1.637) | **0.70 m** short | slid along a wall of air, round the crate, never touching it |
| footprint | at the face | **0.000 m**, 1.174 from its centre (computed 1.174) | stayed there, inside the crate's box |

A frame of each: the whole crate in view, held off; and nose to its face. The ruins' lift-jump walk
came out identical line for line. The walk reports the nearest turned solid's gap now, measured by the
sample from the two outlines, not asked of the controller.

**Found**: the turntable's tool said a disc's box does not swell as it turns. It did — a world box is
the local box's corners turned, and a disc's local box is a square: 5.66 m at 45°. Tool, OBJ header and
README corrected. Its footprint is that square turning with it — which is the new third item.

**Two test lessons**: a stop lands anywhere between a millimetre inside a face and two out (true of the
old code as well); and rounding a corner overshoots by up to one step's slide.

## Done 2026-09-11 — a jump keeps the platform's motion

**`groundVelocity`** (the ground's speed this step) and **`airVelocity`** (the horizontal part, kept
through the air). A jump adds the ground's speed to its own; a step off an edge falls away at it; a
landing clears it and a wall stops the part that runs into it. **A change in behaviour, not only an addition**: jumping off
anything a game reports moving now comes out differently. `motion` has to be movement — a solid put
back at its start in one step must report none that step (in the `motion` doc).

Five tests, each **failing with its part switched off** — the rising-lift apex (0.40 m out), a
sliding platform's jump (1.25 m behind), a step off one moving at 1.5 m/s (no drift), a turntable's
tangent (no speed); the landing test fails only with the landing's clearing removed, checked
separately.

**Jumped in the ruins** from the lift at mid-rise (0.54 m/s up), computed first — window in front:

| jump | takes off | highest | rise | computed |
|---|---|---|---|---|
| from the ground | 0.00 | 0.97 | 0.97 | 0.97 (0.99 less the stepper's 2.5 cm) |
| from the lift, switched off | 0.75 | 1.72 | 0.97 | — |
| from the lift | 0.75 | 1.90 | **1.15** | 1.14 (1.17 less 2.5 cm) |

It came back down onto the still-rising lift and rode it to the top. No frame taken: a still cannot
show a height a log measures to the centimetre.

## Done 2026-09-11 — an ambience volume

**`AudioEngine.ambienceVolume`** (the loops' spatialiser's output — every loop, no one-shot) and
**`PlayerSettings.ambienceVolume`**. Two tests, one rendering audio offline.

**Measured**: half ambience, a loop −6.0206 dB and a one-shot 0.0 dB; off, silence. The sample's own
sounds (`WINDAGE_SAMPLE_MEASURE_AUDIO=1`): crackle at 2 m −33.10 → −39.12 dBFS, a walking footstep
−29.18 → −29.18. **Set on the settings screen** from the keyboard, five presses left to 50%: the file
saved `ambienceVolume 0.5`, `volume` untouched at 0.8; the row photographed. Not heard.

**Every game checked, clean builds**: none uses `PlayerSettings`; the one using `AudioEngine` has no
loops, and its one-shots are untouched. All five build and pass.

## Done 2026-09-11 — a platform that turns

**`Surroundings.turns`** (per-solid turn and centre) and **`turned`** (the angle, for the game to add to
its view). Carried round the centre through collision, no footsteps; a solid that moves and turns is moved
first. Four tests; three fail with the turning switched off (the fourth is the off-the-table guard).

**Ridden in the courtyard's new turntable** (24-sided stone disc, 4 m, 30°/s), standing 1.2 m from its
centre, window in front at 60 frames a second:

| over 3 s | table | feet round its centre | view yaw | radius |
|---|---|---|---|---|
| before | 70.5° | 16.7° | 16.8° | 1.21 m |
| after | 160.5° | 106.7° | 106.7° | 1.21 m |

**Found on the way**: a test compared against the *reported* turn and passed with turning switched off
(both zero) — it compares against the table's turn now; and **lifts and turntables froze in photo
mode** (advanced inside the walking branch) — caught by two identical frames 1.5 s apart. A run with the
window hidden stalled again, and ran on time once in front: the throttling noted below, confirmed.

**Every game checked, clean builds**: none uses the controller; all five build and pass.

## Done 2026-09-11 — a foot on every tread going down

**The tread rule counts a drop as well as a rise** — a one-word fix (`abs`) with a real reason behind
it. Two tests: descending matches climbing from mirrored starts (**0 against 4 before, 4 and 4 after** —
fails on the old rule, checked), and a slope going down keeps its ordinary stride.

**"One per tread" is not literal**: a natural footstep just before a tread edge merges with that tread's,
by the guard that stops a tread ringing twice — and it does so going up too (a climb from a different
start sounds three). Symmetry is what the test holds.

**Walked on the ruins' stairs**, up to the landing and straight back down, 60 frames a second throughout:

| | up (ground → landing) | down (landing → ground) |
|---|---|---|
| old rule | 4 — dirt, stone, wood | **3** |
| now | 4 — dirt, stone, wood | **5** — wood, stone, dirt |

**A detour worth recording**: the first run crawled once the player was on the landing — a 0.6 s wait
took over 20 s — and a profile showed the main thread waiting, not working. **`WINDAGE_SAMPLE_FPS=1`**
(new) showed 60 frames a second at every viewpoint in photo mode and on the landing in a later run: the
crawl was the window hidden behind others, where macOS throttles the display timer the simulation runs
on. A slow scripted run is a hidden window until the frame count says otherwise. *(Since 2026-09-11 a
scripted run keeps time hidden; and a fully hidden window turned out to get no frames at all.)*

**Every game checked**: none uses the controller; all five build and pass.

## Done 2026-09-11 — a brazier that crackles

**Loops in `AudioEngine`** (start, move, stop; each from a different point in its sound) through **a
second spatialiser** — inverse law from 2 m — and **offline rendering** to measure any of it.
**`Level.Placement.sound`** and **`carriedSounds(on:)`**. Seven tests, four of them rendering real
audio offline.

**Measured** (offline, listener facing the source):

| distance | loop (near spatialiser) | one-shot (range spatialiser) |
|---|---|---|
| 2 m | 1 | 1 |
| 8 m | 0.250 | 1.28 — HRTF's near quirk, see below |
| 20 m | 0.100 | 0.545 |

The sample's own crackle (`WINDAGE_SAMPLE_MEASURE_AUDIO=1`): −34.5 dBFS at 1 m, −33.1 at 2, −39.1 at 4,
−45.1 at 8, −53.1 at 20; a walking footstep −29.2 — the fire about 6 dB under the feet beside it, at the
level file's 0.8. **Not heard**: the levels are measured and the seam checked sample by sample.

**The measurement overturned a change I had made.** The engine's note said spherical-head rendering
"keeps the directional cue"; I switched voices to it as a fix — and a direction test failed: **1.01×
louder in the near ear, where HRTF gives 4.6× and `.auto` 5.6×.** Reverted before commit: voices stay
`.auto`, as they always effectively were; the note is corrected; the test stays. **Also measured**: under
HRTF a source inside the spatialiser's reference distance is quieter, not flat (72% at the listener,
full at the reference) — so the one-shot row above reads louder at 8 m than 2 m.

**Driven in the ruins**: two loops at the braziers' coals on load; a brazier nudged twice — its loop
moved each time, nothing restarted; copied — a third loop at the copy; the copy deleted — back to two;
**N** to the courtyard — zero. **The run found** that keying loops by placement index restarted the
*other* brazier's fire when a copy renumbered it; matched by what and where first now (3 loops ever
started across that whole edit, where it had been 5).

**The engine's own tests hit the stale-build crash too** (a sample test failing nonsensically after
`Placement` gained a field); a clean build cleared it. Every game checked from clean builds.

## Done 2026-09-11 — standing on something that moves

**`Surroundings.motion`** (per-solid displacement since the last step) and **`carried`**. A body on a
solid that moved goes with it before walking: rigid vertically, through collision across. Six tests;
three fail with the carry switched off (the eye 8 cm behind a rising lift, a sliding platform leaving
the body 4 m behind, walking not relative) — the other three guard what must not break.

**Ridden in the ruins**: a timber lift (`"lift"` tag; motion in `SampleLevel.liftHeight(at:)`) beside
the wooden landing, rising 0.9 m. Scripted ride, feet against the lift's top:

| | lift top | feet |
|---|---|---|
| stepped on at the bottom | 0.30 | 0.30 — one footstep on wood |
| halfway up | 0.75 | 0.75 |
| top | 1.20 | 1.20 |
| back down — through the turn | 0.30 | 0.30, still riding |
| up again, then walked off onto the landing | 1.20 | 1.20, off it |

No footsteps while riding; the eye held 1.70 throughout. Frames from on the lift at the bottom (the
landing a raised deck) and at the top (flush with it).

**Every game checked, clean builds**: none uses the controller; all five build and pass.

## Done 2026-09-11 — standing up under something low

**Measured before touching it**: letting go of crouch under a beam with a 1.5 m underside raised the
eye to 1.7 and the head 35 cm into the beam, and the player was then **stuck** — every move refused,
since the body overlapped the beam wherever it went. Now the body stays crouched in every respect
until the footprint is clear, and stands on its own; `isHeldDown` reports it. Five tests; the
three that exercise the fix fail without it (checked).

**The sample found a second fault**: the first headroom check had no collision tolerance, so a player
who walked up to the new lintel *standing* — stopped against its face to within a hair — was pushed
into a crouch. Fixed, with a test.

**Driven in the ruins** (new lintel: two stone slabs on crate posts, underside 1.5 m, at z −4):

| | feet z | eye |
|---|---|---|
| walk up standing | −3.20 (stopped at the face) | 1.70 |
| crouch, shuffle under | −4.01 | 1.05 |
| let go of crouch, wait 1 s | −4.01 | 1.05 — "no room to stand" |
| walk on | −6.62 | 1.70 — stood when clear |

The frame shows the underside of the lintel overhead and "NO ROOM TO STAND".

**Every game checked**: none uses `CharacterController`; all five build and pass.

## Done 2026-09-11 — adding from the editor

**`Level.kinds`** (one of each kind of thing — all but `x`, `z`, yaw) and **`LevelEditor.add(_:at:yaw:)`**
(another of a kind, with its height, scale, tags, surface and lamp). Two tests. In the sample **t** steps
through the kinds and **i** drops one where the crosshair meets the ground.

**Driven in the ruins**, scripted, with the drop points computed from the camera first:

| added | predicted ground point | landed | lamp |
|---|---|---|---|
| brazier (lamp at 60) | (−2.74, 0, −1.52) | (−2.74, 0.00, −1.52) | (−2.74, 1.80, −1.52) |
| crate, scale 2.4 | (0.88, 0, −0.28) | (0.88, 0.00, −0.28) | — |

The frame shows the new brazier lit — a pool on the ground, embers off its coals — and the crate
selected. **Two things the run found**: the ruins' braziers have differently coloured lamps, so they are
two kinds and my key count was one short (the palette now names the lamp's brightness so the two can be
told apart); and the palette's "×" was dropped by the HUD's ASCII font.

**Every game checked**: none uses `LevelEditor` or `Level.kinds`; all five build and pass.

## Done 2026-09-11 — what things are made of, from the level file

**`Level.Placement.surface`, `Level.groundSurface`, `Level.surface(standingOn:)`** — game-named, optional,
left out of the file when unset. A placement that names none answers `nil` rather than the ground's.
Seven tests, two of them on the sample's shipped levels (every solid names a surface the sample can
sound; the ruins' landing is wood).

**Walked in the running sample** (`WINDAGE_SAMPLE_LEVEL=1`, scripted): up the three stone treads —
"footsteps on dirt and stone" — across the three timber ones — "footstep on wood", twice — and off the
end, "landed at 7.0 m/s on dirt". Nothing reported missing a surface. The landing was photographed:
stone stairs up to a timber deck.

**Content**: `step_wood.obj` (the step's shape, the crate's timber), wood and metal footsteps and
landings from `Tools/make_sample_sounds.py` — the dirt and stone ones regenerated byte-for-byte.
**Not verified by ear**; the files load and play through `AudioEngine` without error.

**Checking the games found two build hazards, and the first is fixed in the engine.**

- **A new defaulted parameter changes an initialiser's symbol.** The first version added `surface:` to
  `Placement.init`; a consumer's test target compiled against the engine before it then failed to link. The surface
  variants are **separate initialisers** now, so the old symbols are unchanged.
- **A new stored field changes a public struct's size, and SwiftPM did not rebuild the consumer's
  objects** that were compiled against the old one. The consumer's tests then *crashed* — signal 5, then
  11, at a different test each run — rather than failing. **A clean build (`rm -rf .build`) fixed it**:
  307 + 519, and the app from a clean derived-data folder. The engine's own tests hit the link half of
  this too, and were re-run from a clean build — same results, same footsteps.

> **The rule this adds to "check every game":** when an engine change adds a stored property to a
> public type, build each consumer **clean**, not incrementally. A crash in a consumer's tests after
> such a change is a stale build until proven otherwise.

All five games build and pass against the change; the one with a window was built clean, run and looked at.

## Done 2026-09-11 — a stick dead zone the player sets, and a stick that walks at its speed

**`PlayerSettings.moveDeadzone`, `lookDeadzone`** (0…0.5, defaults 0.16 and 0.10), read by
**`InputState.moveDeadzone`, `lookDeadzone`**. On the sample's settings screen beside the stick rows,
in 2% steps. The scripted walk holds a stick part-way: `pad.lookRight@0.2:1`, `pad.moveUp@0.6:1`.

**It found a real bug first**: `CharacterController` and `Camera.advance` *normalised* the movement
direction, so a stick at 5% walked 6 m a second, the same as full. Measured by a probe before touching
anything; clamped to 1 now (two keys still no faster than one). **A change in behaviour, for that.**

**Measured in the running sample:**

| stick held | defaults (look 10%, move 16%) | look 26%, move 30% — set on the settings screen from the pad |
|---|---|---|
| look at 8%, 1 s | no turn | — |
| look at 20%, 1 s | 2.26° (the drift) | no turn |
| look at 50%, ½ s | 18.11° | 9.64° |
| look full, ½ s | 91.67° | 91.67° |
| move at 20%, 1 s | 0.11 m | 0 m |
| move at 60%, 1 s | 2.59 m | 1.99 m |

Every figure is the response curve's, computed before the run.

**The game with a window had the same normalising line** — its walking is where the engine's came
from — and its left stick was an on/off switch. **Fixed there in the same pass**, with a test that fails
on the old line; built, run and looked at. The four rigs pass unchanged.

## Done 2026-09-11 — a lamp from the editor

**`LevelEditor.setLight`, `raiseLight(by:)`, `brightenLight(by:)`**, and `add(mesh:…, light:)`. Raised
in world metres whatever the placement's scale; brightened in thirds of a stop, never to zero; all
undoable, and an edit that changes nothing records nothing. Six tests.

**Driven in the running sample**, scripted: walk up, **Tab**, pick a plain crate (#7, scale 2) with
**Space**, then **l**, **]** ×2, **.** ×3. Logged through `carriedLights(on:)`:

| after | lamp at | intensity |
|---|---|---|
| **l** | (−4.00, 3.20, −18.00) | 45.0 |
| **]** **]** | 3.30, then 3.40 | 45.0 |
| **.** **.** **.** | 3.40 | 56.7, 71.4, 90.0 |

Every figure is the prediction: the box mesh is 1 m, so the lamp sits at 1.6 in the placement's space,
3.2 m up at scale 2; three thirds of a stop double 45. **A frame difference** against the same view
without the lamp shows the new pool of light on the ground under the crate, with the objective crates'
shadows cut out of it — in daylight the change is subtle to the eye and plain in the difference.

**Every game checked**: none uses `LevelEditor`; all five build and pass.

## Done 2026-09-11 — head bob, and a setting for it

**`CharacterController.headBob`**, a view offset locked to the stride phase — the head lowest as each
foot lands, swaying toward the carrying leg, two dips per sway — scaled by gait, eased, and absent in
the air and in a slide. **`PlayerSettings.headBob`**, 0…1, 0 is off. Nine tests.

**Measured in the running sample** (scripted walk, peak to peak as shown on screen):

| | up and down | side to side |
|---|---|---|
| walk | 2.8 cm | 1.8 cm |
| sprint | 4.7 cm | 3.0 cm |
| crouch | 1.4 cm | 0.9 cm |
| walk, setting 50% | 1.4 cm | 0.9 cm |
| walk, setting off (set on the settings screen) | none | none |

**One bug found before it shipped**: a stair tread jumps the stride phase to a footfall, and the bob
jumped 2.86 cm in one frame with it. Carried and eased out at the eye's settling rate now; the stairs
test fails without it (checked by removing the fix).

**Not seen as motion.** The numbers are the bob that reached the screen; a still frame cannot show a
bob, and no video was captured.

**Every game checked**: none uses `CharacterController` or `PlayerSettings`; all five build and pass.

## Done 2026-09-11 — a mouse sensitivity and a stick sensitivity

**`PlayerSettings.mouseSensitivity`, `stickSensitivity`, `invertMouse`, `invertStick`**, with
`mouseLookScale` and `stickLookScale` in front of the camera's two look paths. **Breaking**:
`lookSensitivity`, `invertLook` and `lookScale` are gone — no game used them (checked). A file from
before the split loads with its one setting on both devices.

**Proved by rates in the running sample**, three runs with the same scripted turns
(`pad.lookRight:0.5`, `pad.lookUp:0.25`, `mousex:500`, `mousey:-200`):

| settings | stick right | stick up | mouse right | mouse up |
|---|---|---|---|---|
| defaults | 91.67° | 45.84° | 63.03° | 25.21° |
| mouse 2.0, stick 0.5, stick inverted — **set through the settings screen from the pad** | 45.84° | −22.92° | 126.05° | 50.42° |
| an old-style file: `lookSensitivity` 1.5, `invertLook` on | 137.51° | −68.75° | 94.54° | −37.82° |

Each is the constant times the setting, to the hundredth. The screen shows the mouse rows beside the
keys and the stick rows beside the pad's buttons, only while a pad is connected.

**It found a scripted-walk bug**: a segment could be held one step long, because sixty steps of
1/120 s add to a hair under 0.5 in a Float. The first stick turn came out 1.53° — one step — over.
Half a step of slack now.

**Every game checked, per the rule**: none uses `PlayerSettings`, and all five build and pass —
the four rigs (5, 2, 3, 10 tests) and the game with a window (306 + 493, Debug build, run and
looked at; it renders as before).

## Done 2026-09-11 — lights that belong to a placement

**Two steps, because the first was found on the way.**

**First — `Level.transform(of:on:)`, and bedding turned the right way.** A carried light needs its
placement's transform, and there was no definition of one: the sample built it, a game built it twice,
and **the engine's `beddedFootprint` bedding turned the opposite way from all of them** — sampling the
ground under the corners of the placement's mirror image. It uses `Level.turned(_:by:)` now, the
matrix's own turn; a test with an asymmetric footprint turned on a slope fails against the old
rotation. A change in behaviour, because a bedded placement can now sit at a different height.

> **For the game this was extracted from:** its installation bedding and its collision masks use the
> same backwards turn, while its renderer draws with the standard one. Its parity test against the
> engine will now disagree, and that disagreement is the bug. **Fixed in that game the same day**, in
> its own repository — see below.

## Done 2026-09-11 — every game rebuilt against the engine, and what that found about the engine

**The five games depending on this engine were rebuilt, tested and — the one with a window — run.**
Four built and passed untouched. **The fifth had not been rebuilt since 2026-09-09, through two days of engine changes, and
came back three ways broken.** All three are about this engine's surface, which is why they are here
without the game's name:

- **A public type name is a namespace shared with every consumer.** The engine added `Material` on 2026-09-09. The game
  had a C struct called `Material` in its shader-types module, and a Swift file importing both no
  longer compiles. A game's own *Swift* types shadow the engine's quietly (it has its own
  `ShadowMap` and `ParticleRenderer`, and those still compile) — **it is a second imported module that
  makes the name ambiguous**, and a game's shader-types module is always one. Worth remembering
  before the next generic name goes public.
- **The tone-mapping break (2026-09-10) fails as noise, not as an error.** A scene pipeline still declaring
  `colorPixelFormat` inside the HDR scene pass is not refused by Metal 4 — pipelines and passes are
  decoupled — so the game rendered magenta and blue static with nothing logged. The CHANGELOG said
  "breaking" and was right; the symptom is what a consumer needs told. **And a game that already tone
  maps in its own shader wants `ToneMapping.off`**, or the picture goes through two curves.
- **The bedding fix reached the game's copies of the turn**, as the note above predicted: its
  bedding and collision were mirror images of what it drew. Fixing them also exposed a separate bug
  of the game's own (corners rejected before the mask was read), because its tests finally looked.

**Two scaffolded rigs had stale handoffs**: one still claimed a probe that graduated three days
earlier, one still held a `LightSet` that the engine had extracted *and corrected* — deleted there
now, with a test pinning the correction.

**Then — `Placement.light`, `resolvedLights(on:)`, `carriedLights(on:)`.** The ruins' braziers carry
their flames; free lights with no cone are gone from the level, and a test keeps them gone. **Driven in
the editor by the scripted walk** (which gained `click`): select a brazier, nudge it six times, and the
lamp is logged moving with each nudge; before-and-after frames show its pool, shadow and embers moved.

## Done 2026-09-11 — the landing dip

**A landing shows now.** `CharacterController` kicks a critically damped spring by the impact: the eye
drops (`landingDrop`, in `eye`) and the view nods (`landingCameraDip`, view only, like the slide's).
Scaled from 3 to 12 m/s — a jump dips a third, a 3.6 m fall 16 cm and 3.4°. Down in 70 ms, back in
0.4 s, no overshoot.

**A test found the Euler-integrated spring 20% short**; it is stepped by its exact solution now, and
the curve is the same at 60 and 240 Hz. **Driven in the sample**: the drop off the steps logs 7.0 m/s
and a 7 cm, 1.5° dip, as the tuning predicts; a frame paused mid-dip shows the horizon 1.5° higher
than the settled one.

## Done 2026-09-10 — controller rebinding

**`PadButton` and `PadBindings`**: jump, crouch, sprint and brace onto any face button, shoulder or L3,
stored by position (`south`, not "A" or "Cross"). Sticks, triggers, d-pad and menu stay the convention;
R3 is refused as the scroll notch. `InputState` reads the pad through `padBindings`, with one
press-edge set for every button.

**The sample's settings screen shows the controller's rows when one is connected, and runs from the
pad**: menu button opens it, d-pad moves, Cross changes, Circle leaves. `acceptsPadActions` goes off
while it is open, or Circle would crouch the player behind it; the menu reads raw presses, not the
bindings it is editing.

**A virtual pad drives all of it.** `GCController.withExtendedGamepad()` plus
`InputState.useGamepad(_:)` — the tests press real `GCExtendedGamepad` buttons, and the scripted walk
takes `pad.south`, `pad.menu`, `pad.down`. **Its d-pad moves only by its axes**; the first scripted run
could not leave the menu's first row.

**Driven in the running sample, two launches, pad only**: rebind jump to R1; R1 jumps 0.97 m, Cross
does nothing; relaunch, same; reset from the pad, Cross jumps again. Settings file deleted afterwards.
**Not tried with a physical controller** — the names shown on a DualSense ("Cross") are the framework's
and were not seen here; the virtual pad reports "A".

## Done 2026-09-10 — braziers

**The ruins' lamps stand over iron braziers** (`brazier.usda`, from `Tools/make_sample_brazier.py`)
with coals glowing from an emissive map, and the embers come off the coals. **USD because Model I/O
reads no emission from an OBJ**; the sample's level loader now tries OBJ, then USD.

**It found a shipped bug: the ruins had white, untextured pillars and steps when reached from the
courtyard.** The second level's meshes were loaded by a path that resolved no textures. Every
screenshot had used `WINDAGE_SAMPLE_LEVEL=1`, which loads through `init` — the override hid it. One
loading path now. **Check future screenshots the way a player arrives, not only through the
override.**

Also: a test that every coneless lamp stands over a brazier and every brazier has its lamp; the second
lamp had been floating over a crate, so both pairs moved to open ground; the iron blackened because a
bare metal's grey blew out to cream under a lamp half a metre away; glow ×2.5, since ×6 read white.

## Done 2026-09-10 — footsteps and landings

**`CharacterController.events`** — strides, landings with impact speed, jumps — and **`groundSolid`**,
what is underfoot. The sample plays three dirt and three stone footsteps in a six-step order, heavier
landings, and a push-off on a jump, synthesised by `Tools/make_sample_sounds.py`.

**Footfalls count distance covered, not asked for**, so a player pushing into a wall does not march.
Strides are long because the speeds are (2.3, 3.6 and 1.7 steps a second walking, sprinting,
crouched). No footsteps in a slide; a stair down is not a landing.

**A test found stairs climbed in half the footsteps** even after the fix was written: the fix was in
the step-up, and on stairs the body is lifted by the ground-following instead. It is in both now. The
first pass of the sounds also clipped; they are normalised.

**Verified by the scripted walk**, which now prints footsteps and landings per segment: 4 on stone for
the four treads, a 7.0 m/s landing off the 1.2 m drop, 5 over 12 m walking, 3 over 4 m crouched, 4 over
18 m sprinting. **Not verified by ear** — this session cannot hear the output; the files load, play
through `AudioEngine` without error, and measure as intended.

## Done 2026-09-10 — keys a player can change

**`KeyCode`, `InputBindings`, `PlayerSettings`**, `InputState.bindings` and `flagsChanged`, and
`AudioEngine.masterVolume`. The sample has a settings screen on **O** — eight keys, look sensitivity,
invert look, volume, brightness, reset — saved the instant anything changes. *(Look sensitivity and
invert are per device since 2026-09-11.)*

**It found that Shift had never worked in the sample.** macOS sends modifiers as a flags change, not a
key press, and the window never listened. Modifiers are keys now, read by their device-specific bit;
the on-screen hint is built from the bindings so it cannot lie again. **And the em dash never rendered**
in the HUD — the engine had been saying so in the log every run.

**Rules**: a key in use is swapped, not stolen; Escape, Tab and the arrows are refused, plus the game's
own always-on keys; one key per action; decoding tolerant field by field, because a settings file that
fails to decode is every setting reset.

**The scripted walk presses real keys now**, through the path a keyboard takes. Two launches: rebind
forward to I in the screen, walk 6.05 m with I, W does nothing, Shift sprints 18.15 m; quit, relaunch,
I still walks. Reset from the screen puts W back. The test settings file was deleted afterwards.

## Done 2026-09-10 — particles

**`ParticleSystem`, `ParticleRecipe`, `ParticleEmitter` and `ParticleRenderer`.** Embers rise off the
ruins' braziers and the figures' lanterns, a collected crate throws green sparks, a landing from a
drop kicks up dust.

**Extracted from a working game**, with three changes: its enum of kinds became a recipe a game
defines; its "every eighth step" emission became a rate per second, tested at four step sizes; and its
spread randomness — `fract(sin(x) × 43758)` in 32-bit floats — turned out to give **8,923 distinct
values in 300,000 draws**, so it is an integer hash now (297,320).

**Light and matter share one pipeline** through premultiplied alpha: light writes zero coverage and
the blend becomes an add.

**The sample found two things.** Unlit dust is a lamp: a 0.5-grey cloud in shadow came out as a white
glow, so matter is now lit by the sky's mean radiance plus the sun over 4π (`matterLight(under:)`).
And the crate burst started inside the crate, so depth hid half of it.

**Driven in the running sample**: embers seen rising, a scripted walk collecting a crate shows the
burst, and the landing dust is a dim tan puff after the lighting fix, a white blob before it. The
scripted walk gained `yaw:` and `pitch:`, because a replay that ignores the mouse otherwise cannot look
at its own feet.

## Done 2026-09-10 — a body with feet

**`CharacterController`**: walking, standing on things, a 0.45 m step, gravity, a jump of about a
metre, crouch and slide. The sample walks on it; it used to pin the camera to one height.

**The walking, crouch and slide half was extracted from a working game** with its tuning and reasons
intact. What that game did not have — gravity, steps, obstacles — is what the sample's crates and a
new set of stone steps in the ruins needed, and the seam turned out to be the ground: `Surroundings`
is terrain plus solid boxes, asked by the controller rather than owned by the game. That game still has
its own copy; replacing it is its own work.

**The body is a box** (exact against box solids), **the feet move at once and the eye eases after
them** (stairs read as stairs; a fall is never eased), **no jump out of a slide**, and a tenth of a
second of coyote time and jump buffer each.

**The sample found one bug**: a blocked step stopped the player where the last whole step ended, 4 cm
short of a crate at a walk and 15 cm at a sprint. A blocked axis now moves to the face; the test for it
fails without the fix.

**Driven in the running sample**, with the new `WINDAGE_SAMPLE_WALK`: up four steps to 1.20 m, off the
end to 0.00, a jump peaking at 0.97 m, and stopped exactly at a crate's face walking and sprinting.

## Done 2026-09-10 — things that hang off other things

**`TransformHierarchy` is parenting**, and the sample's figures carry lanterns. A list of attachments
and a list of matrices, owning no objects — so the same hierarchy places a drawable, a light and a
collision volume without knowing that any of them exist. **Not a scene graph**, which is still in the
contested list and stays there.

**The interesting case is the one that reaches outside itself.** A rig is already a hierarchy and
`SkeletonPose` already resolves it; what it cannot do is reach *out*, and a weapon in a hand is
exactly that — the parent is a joint, inside a pose, that is itself placed by an object's world
transform. `Attachment.external` makes it first-class, so the node's own local transform stays the
grip rather than being rewritten every frame by a caller keeping the grip somewhere else anyway.
**How many externals will arrive is declared up front**, so a bad index is a load-time error and not
an identity substituted at sixty hertz.

**Scale is inherited, and that is wrong for a held object.** A rig in centimetres hands its wrist a
hundredfold scale; a lantern hung there is drawn at one percent of its size, in a position that is
otherwise correct. `matrix_without_scale` at the call site rather than a flag inside the hierarchy —
it is a decision about what is being attached, and only the caller can see that.

### The finding: a joint's frame is not where the mesh got drawn

The bind pose puts the figure's forearm joint 48 cm along the arm and the mesh reaches 74, so 26 cm
along the joint's +X reads as "the hand" — and with the arm down it is exactly that. **Raised, it is
not:** the drawn limb stops a hand's length short, and the lantern floats above the head. That gap
belongs to the asset, not the engine; the lesson is that **a grip derived from bind-pose arithmetic
is a guess**, and it is a number set by looking.

### What it found in the point-light shadows

**The sample assigned cube slices once, at level load** — correct for lamps that do not move, and the
first lamp that did move exposed it. A cube recorded from where the lamp *was* is a shadow that lags
the hand. Assigned every frame now; it is a sort of five elements.

### Measured

Two frames of the same figure, waving and not: the lantern is at the end of the outstretched arm in
one and raised with it in the other. The lantern lights change **24.5% of the frame** against having
none; their own cube shadows a further **4.7%**.

## Done 2026-09-10 — point lights cast too

**Every lamp in the sample stops at a wall now**, aimed or not. `ShadowCubes` is a cube-array depth
texture, the six face matrices, and the pass that records them.

**A cube array, not tiles of the atlas — which is not what the spot-light shadows predicted.** Two of the three things
that entry listed survived; the tiles did not, for two reasons that only appear once the shader is
written. **The face maths would have to agree with six matrices exactly** — which axis becomes *u*,
which becomes *v*, which of the six sign flips applies — and a mirrored face still casts a shadow, just
in the wrong place, which reads on screen as a bias problem. **And a filter kernel cannot cross a tile
edge**: a tap off the edge of a face lands on a different face at a right angle, so clamping draws a
bright seam down all twelve edges and not clamping reads a neighbouring lamp's tile. The hardware does
both jobs for a `typeCubeArray`.

**The bias is in metres, not in depth.** A face stores `near / distance`, so the same added constant is
a third of a millimetre at one metre and most of a metre at ten.

**Six passes per light, and two culls give most of it back.** Range for all six faces, `Frustum` per
face. The ruins, two casting point lights over 32 drawables: **35 objects recorded against 384
unculled** — twelve passes for barely more than one unculled one. `ShadowMap.Batch` gained an optional
`bounds` for it, and this is the first consumer `Frustum` has had inside this repository.

**`right × up == forward` for a cube face**, which looks like the wrong handedness and is not — a cube
is sampled from the inside. The same relation already held for a spot and for the cascades, so the
winding and the front-face cull are unchanged. Asserted in the tests, because it is exactly the sort
of thing somebody "fixes".

### Verified twice, because half of it is invisible

The half a screenshot cannot show is whether the matrices agree with the sampler. `lookup(direction:)`
writes the sampler's own rule down, nothing calls it at runtime, and the test asserts that for a
spread of directions the face and *uv* it gives are where that face's matrix actually lands the point.

The half it can show was a difference, as with the spots: the same frame with the cube flag on and off
changed **1.77% of it**, around the two braziers.

> **The sample gained `WINDAGE_SAMPLE_LEVEL` and `WINDAGE_SAMPLE_CAMERA` for this.** Comparing two
> frames needs them to be the *same* frame, which a sample that always opens on level one and is then
> walked to the interesting corner by hand cannot give. `y` sets the eye height rather than a one-off
> position, because the walk clamps to the ground every step — set as a position it would be true for
> one frame and then quietly gone.

## Done 2026-09-10 — shadows for the lamps

**A spot light casts now**, so a wall stops it. `ShadowAtlas` is one depth texture cut into tiles, a
spot's view-projection, and the pass that records every caster into its own tile.

**An atlas rather than a texture each**: a fixed allocation, **one render pass for every light** — the
viewport moves between them — and a single binding the shader samples with an offset. **Scissored as
well as viewported**, which is not redundant: a viewport limits where geometry lands and does not stop
a clear or a wide triangle touching a neighbour's tile.

**Spot lights only.** A spot's map is one perspective render, sharing the cascade pipelines. A point
light needs **six**, so `viewProjection(for:)` returns nil for a coneless light rather than silently
shadowing one direction of six. The rest is cube tiles, six passes per light, and a shader that picks
a face before a tile — real work rather than hard work.

### Four smaller ones

The field of view is the cone's outer angle doubled. **A lamp pointing straight down is the common
case and exactly where a fixed up vector is degenerate** — zero cross product, `NaN` basis, nothing
draws. **The shader's constant bias is positive where the rasteriser's is negative**: different
quantities in different spaces, and reversed-Z inverts only one of them. And tiles go to the
brightest, longest-reaching lamps.

### Verified by difference, not by looking

A spot's shadow on open ground is subtle enough that "looks about right" is not verification. The same
frame with the per-light flag on and off: **1.2% of the frame changed**, confined to the lit ground.

> **That measurement came before the hunt for a good camera angle**, which is the right order — it
> answered "is this working" in one step, so the time afterwards went into making it visible rather
> than into wondering whether there was anything to see.

## Done 2026-09-10 — clustered shading

**A fragment asks which lights reach *it*** rather than inheriting a list chosen for the whole mesh.
`ClusterGrid` cuts the frustum into 16×8×24 cells; `ClusteredLights` bins the scene's lights into the
cells they reach, once per frame, on the CPU.

**This is the floor per-draw selection could not get under** — the sample's ground is one
eight-hundred-metre quad, so one draw got four lights for a level. A cluster is a small box of the
world, so the lights reaching it are few by construction.

### Three decisions

- **Exponential slices.** An even cut makes near slices microscopic and far ones hundreds of metres
  deep, because a frustum's cross-section grows with distance. The logarithm keeps clusters cubic.
- **Clustering needs a finite far and this projection has none**, so `ClusterGrid` carries its own
  `lightRange`. Honest rather than awkward: a punctual light's range is finite by definition.
- **An offset and a count per cluster**, not a fixed list each — an empty cell costs nothing and a
  full one has no ceiling.

### Measured

64 lights in a test scene: busiest cluster **9**, average **2.2**. The ruins: 10 lights, busiest
**6**. The worst fragment loops nine times instead of sixty-four.

### The bug that made it render as nothing

It drew **no local light at all**, with the CPU side provably right — 6 lights, 222 entries, 173 cells
occupied. Printing those numbers is what turned an open-ended hunt into a two-line one: the fault had
to be between the buffer and the shader.

**A `SIMD3<Float>` used as padding is 16-byte aligned in Swift; the shader's three trailing scalars
are 4.** The struct was 48 bytes on one side and 32 on the other, so every field after it was read
from the wrong address. It compiled, ran, and looked exactly like a feature nobody had wired up.

> **The third layout question in this repository** — after the skinned vertex layout's `float4`
> alignment and the tone-map uniform's packing. The test pins size, stride **and** alignment, because
> the first two only catch half of it.

## Done 2026-09-10 — spot lights

**A cone, for the lamps that are aimed.** A direction and two angles — full brightness within the
inner, nothing beyond the outer, smooth between; one cutoff gives a hard edge that reads as a stencil.
Levels write the angles in degrees and no direction means no cone, so every lamp already written stays
a point light.

**A point light is a spot with no cone and the shader does not branch**: scale 0, offset 1, and the
angular term is exactly 1 everywhere from the same two multiplies.

### Selection is where a cone bites

The nearest point of a box gives the best *distance*, which settles a point light and does not settle
a spot — the nearest corner of a wall can be outside the cone while the far end is brightly lit.
Testing that one point drops the light and darkens the lit end. So the cone is tested against the
box's bounding **sphere**, conservative in the safe direction, and ranking uses distance alone. Same
asymmetry as `Frustum`.

### The finding that was not about spot lights

The sample's first spot lit nothing, and **over-subscription was not why** — the check reported the
level clean everywhere a player stands. **The cause is that the ground is one 800-metre quad**, so
per-draw selection gives that single draw four lights for the entire level and the objective lamps
0.6 m above it beat a spot 5 m up.

**Per-draw selection is only as good as the draws are small.** No budget or ordering rule fixes an
oversized one; that is what clustered and tiled shading are for. Written down rather than tuned
around, and the sample aims its spot at a pillar instead.

> **The check earned its place by being negative.** A tool that said "not that" is what stopped an
> afternoon of adjusting intensities looking for a problem that was never there.

## Done 2026-09-10 — lights that are not the sun

**A sun and an environment map have no answer for an interior.** `PunctualLight` and `LightSet` are
extracted from the probe built to ask this, stripped of the game that asked it. `Level.lights` is a
named list in the format; the sample selects per draw and shades lamps with the same GGX lobe as the
sun.

### What the probe had right

**A hard budget cannot promise a smooth hand-over in an arbitrary level.** Choosing by influence
rather than distance fixes the common case; it does not fix the general one, and a bigger budget only
moves the number. So the promise is conditional and `isOverSubscribed(at:)` checks it: where no more
than the budget are above `negligible`, nothing visible is ever dropped. That is a constraint on how a
level is built, findable before it ships.

### What the probe had wrong

It ranked by **falloff alone**, so a candle at one metre outranked a floodlight at ten and the
floodlight was dropped. Influence is luminance-weighted now.

### Four smaller ones

Selection is per draw against the box's **nearest point**, not its centre. The falloff needs a floor
or a fragment at the lamp's position is `NaN`, which draws black rather than bright. **Local lights
cast no shadows** — one shadow map, and the sun has it — which is why the sample's ranges are short.
And a lamp in daylight does almost nothing, correctly, which is why the sunlit level has none.

### And one about the format

**`Level` decodes explicitly and tolerantly now.** Every field but the version is optional: the
synthesised decoder throws on a missing key, so adding `lights` would have refused every level already
written, including any a player saved into Application Support.

> **The stale-build hazard bit again** — adding a parameter to `Level.init` left the sample-core tests
> linking against the old mangled name. Same rule: delete the build directory when a shared type
> changes shape.

## Done 2026-09-10 — emission

**The last material slot with nothing reading it.** Every slot `Material` carries now reaches a pixel.
The figure has glowing seams from an emissive map; objectives emit instead of swapping albedo, so a
collected crate and an uncollected one differ by being lit rather than by being two paints.

### The identity-scalar rule, third instance

A file that connects `emissiveColor` to a texture supplies no scalar, so the field kept `Material`'s
default of zero and multiplied the map away. **Base colour, the metallic-roughness pair, and
emission all needed this for the same reason** — which is what makes it a rule rather than three
fixes.

### Three things about emission

- **Added, not lit.** Nothing multiplies it — not the sun's angle, not the shadow map, not occlusion.
  A seam that dimmed in shadow would be a lamp that goes out when you stand in front of it.
- **A whole object that emits looks flat**, correctly: an emitting surface has no light direction.
  Real ones are a strip or a panel, confined by a map — which an OBJ cannot carry.
- **A PNG cannot exceed 1**, so a map alone is never brighter than white and does not read as lit.
  The multiplier is the game's, because how bright is a look decision.

### And who owns the value

**The game's, not the material's times the game's.** Multiplying was the first attempt and produced
nothing: an OBJ material's emission is always zero — `Ke` and `map_Ke` are both discarded, and the
property comes back an always-black `.color` — so a crate the game wanted lit was zero times whatever
it asked for.

## Done 2026-09-10 — packed material maps

**Occlusion, roughness and metalness from a texture** — the last slots with nothing behind them.
Packed R/G/B, which is glTF's packing, so one file serves three slots. `TextureSlot.packedChannel`
says which channel each reads.

### The 0.18 trap in a second place, and it was nearly shipped

**A file that connects `metallic` to a texture supplies no scalar for it at all**, so the field kept
`Material`'s own default — and `metallic` defaults to 0. Multiplied by the map that is zero
everywhere: a metal figure rendering as a dielectric one, with nothing to say why. Caught by looking
at the figure, thinking it looked less metallic than before, and measuring what the material reported.

**A slot with a map takes the identity for the operation it is used in** — white for a tint, 1 for a
multiplied factor. The base-colour case already needed that rule; it is applied in both places now.

### What Model I/O carries, measured

- **USD carries all four** — metalness, roughness, occlusion, emissive — **and drops which channel
  each reads**. The convention is assumed. It is right for an unpacked greyscale map too, which is
  why glTF fixed one.
- **OBJ carries none of it.** `map_Pr` and `map_Pm` are read and discarded. What does arrive is
  `map_Ns` as a `specularExponent` **texture** and `map_Ka` as emission — an OBJ can vary shininess
  spatially, in exponents. Not wired up: differently shaped, and nothing needs it.

### Two in the shader

White is exactly the right fallback because the three are multiplied. And occlusion applies to the
ambient terms only — applying it to the sun would darken a surface the sun is plainly shining into.

## Done 2026-09-10 — a level says what sky it is under

**It said where the sun was and nothing else about the light.** `Level.sky` is a `ProceduralSky` now,
written as its own block — three colours, two angles and a sun size — so the two sample levels are a
clear afternoon and a low overcast one rather than the same scene with the sun moved.

- **A named block, not more `settings` scalars.** Fifteen keys with no structure and nothing to stop
  `skyZenithB` being set while `skyZenithG` is forgotten.
- **Angles, not a vector**, because a person edits the file. The pitch/yaw convention moved into the
  engine at the same time: once the sky is *in* the file, whatever reads it and whatever lights with
  it have to agree, and the only place they can is there.
- **Every key optional**, so a sky naming only `sunPitch` is legal.
- **`resolvedSky` migrates the old `settings` keys**, because levels a player saved live in
  Application Support and cannot be rewritten from here. In `Level` rather than in a game: one
  migration instead of one per consumer.

### Radiance is not irradiance — they differ by about 130×

`sunRadiance` is how bright the disc *is*; what a surface receives is that times the solid angle it
subtends, and a 0.05 rad disc subtends 0.0079 sr. `sunIrradiance` derives it, which stops the sun you
see and the sun that lights the scene from drifting apart — and makes a wider sun both softer *and*
stronger, which is physically true and now free. The default radiance moved 28 → 330 as a result.

### Two things found doing it

- **Overcast is dimmer, not just a dimmer sun.** Keeping a bright sky and dimming only the sun lit
  everything flatly and washed the stone to near-white.
- **Adding a stored property to `Level` segfaulted a test in another target.** `WindageSampleCore`
  was still linked against the old layout, so a decoded `Level` read a garbage array. `swift test`
  gave `signal code 11`, no summary, and a crash log pointing at an unrelated assertion. **Delete the
  build directory when a shared type gains a field.**

## Done 2026-09-10 — image-based lighting

**Metal reflects its surroundings now, not a gradient.** `ProceduralSky` is a sky as a function of
direction; `EnvironmentMap` convolves it twice — a GGX-prefiltered cube whose mips are roughness
levels, and a small cosine-convolved irradiance cube. The sample draws its sky from the same cube it
reflects.

**Prefiltered on the CPU, deliberately.** Everything here that can be *wrong* is arithmetic — cube
face projection, importance sampling, two convolutions — and the rule is that such halves want tests
and tests should not want a GPU. **92 ms release, 2.6 s debug**; the debug figure is what somebody
running `swift run` sees, and it is the honest price. It prefilters a *function*, not a photograph.

### Three things the tests found, all on first run

- **Fireflies at high roughness.** At a fixed 96 samples the chain stops getting blurrier around
  roughness 0.6 and gets *brighter* — 0.72 rising to 1.67 at roughness 1.0 where the truth is 0.60.
  A wide lobe over a small bright sun: the estimate is decided by whether a sample hit the sun.
  **Fixed for free by quadrupling samples per mip** — each level has a quarter of the texels, so the
  cost per level is flat and the roughest mips are the cheapest place to spend.
- **The irradiance integral was out by π.** A Riemann sum over `dφ dθ` weights each term by `step²`;
  dividing by the sample count gives an average instead. Caught by the one value known in closed
  form — a uniform sky of radiance L integrates to πL.
- **The lower hemisphere must not be black**, or every lit object looks like it is floating.

## Done 2026-09-10 — a microfacet specular

**The sample shades with GGX now** — Cook-Torrance, Smith height-correlated visibility, Schlick
Fresnel, Karis's analytic environment BRDF, and a two-colour analytic sky standing in for an
environment map. It replaced Lambert plus Blinn-Phong, which had become the weakest part of the
picture once there was an HDR target to put a real highlight in.

**Behaviour change**: an OBJ material's roughness now comes from its specular exponent.

- **Model I/O's OBJ reader hard-codes roughness to 0.9 and metallic to 0.0.** Five materials measured:
  `Ns 12`, `Ns 200`, `Pr 0.25`, `Pm 1.0`, and both extensions together — the roughness semantic never
  moved. `Ns` arrives as `specularExponent` and is the only shininess an OBJ carries through.
- **`Material.specularExponent` is the tell for a Blinn-Phong material**: a USD `UsdPreviewSurface`
  carries real roughness and metallic and no exponent at all.
- **The BRDF is in the sample, not the engine**, because what a surface *is* is a game's. **If a
  second consumer writes it, that is the moment to extract it** — the shadow-pass lesson applied
  before the fact rather than after.
- **The figure is metal deliberately.** A dielectric surface looks much the same under either lobe;
  metal does not, and USD is the only format here that can say "metal" at all.

### Five things worth knowing

Metal with no environment is black. `alpha` is roughness squared and the squaring is not decorative.
Fold `1/(4 NdotL NdotV)` into the visibility term or grazing angles fill with fireflies. Clamp
roughness away from zero or a smooth surface is one crawling pixel. And `kD = 1 − F`, or a shiny
surface is brighter than the light falling on it.

## Done 2026-09-10 — tone mapping

**The scene stops being written straight to the screen.** Shading does not stop at 1 — the sample's
own lit faces reach about 1.13 before anything shiny is involved — and everything above it was
clipping to the same white, so the brightest part of the image carried no information.

**Breaking**: a game's scene pipelines must declare `FrameRenderer.sceneColorPixelFormat`, not
`colorPixelFormat`. The latter still means the drawable — what a view's layer is set to and what an
interface pipeline draws into.

- **Two passes now.** The scene into an HDR target (`rgba16Float`), then a full-screen triangle
  applying exposure and a curve into the drawable. **`encodeHUD` runs in that second pass**, so the
  ordering it has documented for months is now literally true rather than an intent.
- **`ToneMapping`** — `clamp`, `reinhard` or `aces`, plus exposure **in stops**. `apply(_:)` runs the
  curve on the CPU, which is what makes it testable at all and what a game needs to pick an interface
  colour that matches a scene.
- **The sample cycles curves with `m`**, so the difference can be looked at rather than argued about.

### Two things worth knowing

- **ACES lifts midtones by about a third** — middle grey 0.18 maps to 0.267. A scene tuned before
  there was a curve comes out *brighter*, not darker, and looks washed until its exposure is set. The
  sample sits at −0.5 stops; a game authored against the curve would sit at zero.
- **Narkowicz's fit is not asymptotic.** It passes 1 at an input of about 6.6, so the clamp after it
  is load-bearing rather than a guard. Found by pinning the curve's values in a test.

**Not here: auto-exposure, bloom, colour grading, vignette.** The first is contested — metering, what
"correct" means for a game, adaptation over time — and the rest are a look. This is the part without
which there is no picture.

> **Two copies of one formula, written down as a risk.** `ToneMapping.apply(_:)` is the definition
> and `ToneMapShaders.metal` transcribes it. The tests pin specific input-output pairs, so a change
> to one and not the other shows up in the numbers rather than only on screen.

## Done 2026-09-10 — normal mapping

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

## Done 2026-09-09 — every texture was upside down

**Metal puts texture (0, 0) at an image's top-left; USD and OBJ put `st` (0, 0) at its bottom-left.**
Nothing reconciled them, so every textured asset had loaded flipped since the day textures were
added. `TextureStore` now loads with a bottom-left origin by default; `.topLeft` is available for
glTF-derived UVs.

**A change in behaviour, not only a fix** — it changes what existing code does, correctly.

### Why it survived

The sample's own textures are planks, brickwork and noise, and every one reads the same upside down.
It took a bought character whose texture is a **palette** — a 32×32 grid of swatches with a magenta
row along the bottom — for the flip to stop softening an edge and start putting the wrong colour on a
limb. The character tool photographs what it made, so there was a reference to compare against.

> **The lesson is about the test asset.** Four generated textures, none able to fail visibly. The
> regression fixture is red on top and blue on the bottom now, because an image that looks the same
> either way up tests nothing about which way up it is.

## Done 2026-09-09 — a real character, actually run

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

## Done 2026-09-09 — node transforms, and a correction

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

## Done 2026-09-09 — the shadow pass is extracted

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

## Done 2026-09-09 — what a real character needs

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

**The engine got a version number**, and the repository can now be depended on by URL.

- **`Engine.semanticVersion`** is the single source of truth; `Engine.version` formats it, and
  `SemanticVersion` is `Comparable` and refuses to parse anything that is not `major.minor.patch` —
  a `v` prefix included, because that is not what SwiftPM resolves.
- **`CHANGELOG.md`**, Keep a Changelog format, with everything so far and a list of
  the gaps a consumer will look for and not find.
- **A test is what keeps it honest.** `ChangelogTests` fails if the newest entry (1.0.0 while there is none) is not the version
  the engine reports, if entries are out of order, or if there is no `Unreleased` section. Nothing
  in a build cares whether a changelog was updated, so discipline was never going to be enough — and
  a changelog that has fallen behind is worse than none, because a reader believes it.
- **The conventions count as API** — reversed-Z, the depth clear value, the vertex-descriptor
  contract — because changing one makes a consumer's game compile and then draw nothing.

> **The numbers were withdrawn on 2026-10-13.** Nothing had been released, so the 0.x versions and their
> tags were deleted: the engine reports 1.0.0, the version its first release will be; `CHANGELOG.md` has one
> *Unreleased* section ("Initial release"); there are no tags. When 1.0.0 ships is the owner's call — never
> cut a release unasked. See README, "Versioning".

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

**This is the only "next" list. The top item is what "next" or "continue" means.** When one is
done it comes off, and the one below it moves up. Anything not being built goes under *Parked*
below, never in this list.

1. **The editor is checked — and its edited copy must follow the check's container first.** The editor is
   the one large thing in the sample with no automated cover at all: adding by kind, the lamp keys, undo,
   ⌘S, and the edited copy that shadows the shipped level. **A hazard to clear before any of that**:
   `SampleLevel`'s edited-level path (Sources/WindageSampleCore/SampleLevel.swift, the
   `.applicationSupportDirectory` one) is hard-coded to `WindageSample`, so a check that edits would write
   into the player's own folder — and the sample would load the check's edits in ordinary play. It wants
   the container the saves take (`SampleGame.container`, which a check names after its walk). Then: a walk
   that tabs in, adds a crate by kind, brightens a lamp and saves, checked against a recorded level file,
   and a frame with the editor's overlay open. **Proved by** the level file matching, the frame matching,
   and both failing when the lamp's step or the added kind changes.

2. **A course that is pushed, carried and turned.** The capstone covers what the body does on its own;
   it says nothing about the three things the world does *to* it — a lift under the feet, a slider into
   the ribs, a turntable beneath them — and every one of those is a game-supplied `motion` with its own
   claim to being rate-independent. The sample's movers are functions of absolute time, which is the
   right shape, but `SampleLevel.SlideRun` accumulates `dt` and eases, and nothing has ever asked it for
   the same answer twice. **Proved by** a second course walk, at the same four rates, riding the ruins'
   lift and taking the piston's shove — and by failing when a mover is stepped by its step count.

3. **Lines and rings that are as smooth as fills.** The Drift W (2026-09-15) feathered `HUDRenderer.fill(polygon:)` because the
   HUD has no multisampling and the W came out stair-stepped. `line(from:to:)` and `ring(center:…)` are drawn
   as bare quads in the same pipeline, so every diagonal line and every ring edge is still aliased — and a
   game's HUD is mostly those: a reticle, a mil ladder, a chevron, a scope's surround. Draw them through the
   same rim and feather rather than a second antialiasing path. **Proved by** a recorded frame holding a
   diagonal line and a ring, failing with the feather off, and by looking at the game with a window's HUD at
   full size, whose ladder and chevrons are lines.

## Parked — not next, and why

- **Cluster binning on the GPU.** The CPU version bins the sample's lights in well under a
  millisecond. Build it when a level has hundreds of lights.
- **Auto-exposure.** Contested; the README says why. A fixed exposure per level is the cheap
  middle step if a level needs one.
- **Soft shadows (PCSS or variance maps).** Fixed-radius filtering everywhere today. Nothing in the
  sample looks wrong for want of it.
- **LOD and instancing.** Needed once a scene is larger than the sample's. Nothing in it is yet.
- **A second key per action.** One per action answers "can I put this where my hand is". A secondary
  slot doubles every rule in `InputBindings` and waits for a title that asks.
- **Soft particles and sorting.** Particles are cut off hard where they meet a surface, and matter is
  drawn unsorted. Neither shows at the sample's sizes and opacities; dense smoke would show both.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0**, in `LICENSE` since 2026-10-13. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
- **An engine change that reaches a game is followed into that game in the same pass** — built,
  tested, run and recorded in its own repository. See "Start here".
