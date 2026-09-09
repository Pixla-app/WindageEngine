# Windage Engine

A Swift 6 and Metal 4 foundation for native macOS first- and third-person games. **`WE`** prefix.
**`windageengine.com`**.

> **This repository depends on no game.** It builds, runs and tests on its own, and everything it
> demonstrates it demonstrates through `WindageSample`, which lives here. Capabilities arrive here
> by being *extracted* from a working game — that is the quality rule below — but nothing that
> arrives keeps a reference to where it came from. A game is a consumer of this engine, never a
> component of it.

## Run it

```bash
swift run WindageSample
```

That is the whole set-up: no Xcode project, no scheme, no signing. A window opens on a small
courtyard you can walk around — **WASD** to move, click to capture the mouse, **esc** to release it.

**Its levels are files in this repository.** Open `Sources/WindageSampleCore/Resources/courtyard.json`,
find the first tower, move it, and run it again:

```json
{ "mesh" : "tower", "position" : [ -18, 0, -18 ], "anchor" : "absolute", "tags" : ["solid","landmark"] }
```

Change the first number and the orange tower moves. No compiler step you have to think about, and the
diff is the change. That is the point of it — see **The sample game** below.

> The sample prints which file it loaded. Once the in-game editor has saved, its copy lives in
> Application Support and **shadows the file above** — the console line says so, and **⌘⌫** throws
> that copy away.

## What it is, and what it deliberately is not

It is the part of a native macOS game that was identical every time it was written: frame pacing,
frames in flight, the depth convention, mesh loading, camera, input, the maths.

It is **not** a general-purpose engine, and it is not trying to become Unity. There is no scene
graph, no ECS, no material system, no editor. Those are the parts that cannot be designed correctly
from one game, and inventing them before a second game stresses them differently is how you end up
maintaining an engine instead of shipping something with it.

**Everything here was extracted from working, tested code — never designed speculatively.** That rule
is the whole quality control. If a thing has one consumer and no proven seam, it stays in that
consumer until a second one shows where the seam actually is.

## The extraction rule, and the trap it exists to avoid

A capability enters this package only once real, working, tested code has proved where the seam
actually is. That is the whole quality control, and it has a specific failure mode on the other side
of it.

**Extraction from one game is also how you build a foundation shaped like that one game.** A sniper
game has long sightlines, few actors and a shot that takes a second to land. An engine extracted only
from something like that will be quietly excellent at it and quietly wrong everywhere else — and
nothing will say so until a second game is far enough along that the mistake is expensive.

**A small probe of a genuinely different game shape is the cheapest instrument for finding those
divergences while they are still cheap to act on** — a scene that changes while it runs, geometry
that mostly cannot be seen, light that is not one sun, ground that moves. Each is a few hundred lines
and its tests, and it exists to stress this package rather than to become a game.

> **What that does not license.** A divergence a probe suggests is a *reason to look*, not a licence
> to build speculatively. Something enters this package when working code proves the seam. A probe
> that merely suggests a game *might* want something is a note, not a feature.

### It worked, and the first thing it produced is `Volume` (2026-08-26)

A probe for **ground that moves** — a deck under the player's feet — was written against a worry that
turned out to be a non-issue: world-space interpolation error at ship turn rates is a *micrometre*,
measured against the real 120 Hz step. It is worth more for having disproved that than it would have
been for confirming it.

Looking for that seam is what surfaced the real one. `SceneObject` coupled an `MTKMesh` to a
`BoundingBox`, and the hit test took scene objects, so **owning a GPU mesh was the price of being
hittable**. A shipping game had already paid it twice without the cost being visible as a seam: two
kinds of target each hand-rolled their own world bounds, the renderer ran four hit tests where three
were the same code, and ranging quietly asked a *different* set of things than shooting did — a
target could be shot but not ranged. A deck where everything moves is what made that untenable rather
than untidy: every crate would have been another special case.

So `Volume` — an extent plus a transform, no mesh — came in, and four hit paths became two (volumes,
then a terrain height march, which is legitimately different). **It arrived as working, tested code
with the duplication it removes already visible in a shipping game**, which is the bar.

Two details worth not undoing:

- **`worldBounds` is computed, not stored.** The old `SceneObject` stored it, which was only safe
  because its transform never changed. On anything that moves, a stored box is a box where the thing
  used to be, and the symptom is a round passing through a crate that is visibly in the way.
- **Ranging and hitting share one list.** They had drifted apart precisely because they were two
  loops. A reticle that reads a distance the round will not travel is worse than no readout, because
  the player acts on it.

## Skinned animation is tractable here — probed 2026-09-06

**The engine cannot animate a character, and that is its single biggest gap**: any game with a person
or a creature in it will want one. Before treating that as a plan, the load-bearing
assumption got tested — *does Model I/O actually import UsdSkel, or does it silently drop it?*

A hand-written eight-vertex, two-joint `.usda` loaded through `MDLAsset`:

```
can import usda: true
MDLObject  name=Root
  MDLMesh  name=Bar
    vertices=8  attributes=["position", "normal", "jointIndices", "jointWeights"]
    BIND skeleton=Skel joints=2
  MDLSkeleton  name=Skel
    jointPaths: ["Root", "Root/Mid"]
    bind transforms: 2
```

**All of it comes through** — joint indices and weights as vertex attributes, the skeleton with its
joint paths and bind transforms, and an `MDLAnimationBindComponent` tying the mesh to it. So the
parsing is not work this package owns, and no third-party importer is needed.

**`MeshLoader` needs no structural change either.** It already takes a `semantics` map from the game,
so asking for `MDLVertexAttributeJointIndices` and `MDLVertexAttributeJointWeights` is a dictionary
entry. The seam was already in the right place.

### What it would actually cost, and why the extraction rule does not bar it

Vertex format (joints + weights), a skeleton and clip value type, sampling to a joint-matrix palette,
and skinning in the vertex shader. Real, bounded, and **not speculative in the way the rule warns
about** — that rule protects against designing things that cannot be designed correctly from one
game, like a scene graph or a material system. Skinned animation has one standard shape, and Model
I/O hands over the data in it.

### The authoring half is proved too — 2026-09-06

Reading UsdSkel was only half the question; the other half is whether a bought rig *gets* into USD.
A two-bone armature with a skinned mesh, authored in Blender 5.2 and exported to `.usdc`, read back
through Model I/O:

```
MDLMesh Cylinder  verts=48  attrs=["position","normal","textureCoordinate","jointIndices","jointWeights"]
  BIND skeleton=Rig
MDLSkeleton Rig   joints=["Lower", "Lower/Upper"]
```

**The whole chain holds.** So a rigged model bought as FBX is a Blender import and a USD export away
from being loadable — the risky half (does USD carry the skeleton, does Model I/O read it) is the
half now proved, and FBX import into Blender is routine.

### And the FBX-into-Blender half, on a real character — 2026-09-07

The caveat below said that step was "ordinary". **It was not.** A Sidekick character taken through
Unity → FBX → Blender → `.usdc` and read back with Model I/O:

```
MDLMesh 'Scene'   vertices: 52866  attrs=[position, normal, textureCoordinate,
                                          textureCoordinate1, jointIndices, jointWeights]
MDLSkeleton 'root'  joints: 102    (ik_foot_root, ik_foot_root/ik_foot_l, …)
```

It holds — but three things had to be fixed first, and any of them would stop a bought FBX cold:

- **Unity's FBX Exporter writes ASCII by default and Blender refuses ASCII outright.** The project's
  Fbx Export setting is not consulted by the API path; the options have to be passed per export.
- **Blender's FBX importer refuses blendshapes** — *"FBX in-between Shapes are not currently
  supported"*, open since 2020. They have to be baked into the vertices and dropped, which is what
  the engine wants anyway.
- **Those shapes have in-between frames.** Baking the last frame and scaling it — the obvious
  implementation — is wrong at every weight but the top one.

**Two notes for the loader.** The vertex count is several times the modelled one because USD stores
normals and UVs per face-corner and Model I/O expands them; that is not a broken mesh. And
`MDLAnimationBindComponent` comes back with the skeleton attached but **`jointPaths` empty** — the
mapping is on `MDLSkeleton.jointPaths` instead, so a loader reading only the bind component will
decide a skinned character is a statue.

The tooling that does all of this is `Studio/Characters/` — see its README.

> **What the 2026-09-06 probe did *not* prove:** the export above came from Blender-authored data,
> not from an imported FBX. That is the gap the 2026-09-07 run closed.

> **The trigger is an asset, not a decision.** Building a clip and blending API with nothing to skin
> *is* the speculative version — you would be guessing at the interface with no consumer. Buy a
> rigged **USD** character first, then build against it.
>
> **And that changes what to buy: OBJ carries no skeleton.** An OBJ character is a statue by format,
> not by engine limitation. See the buying filter in `../docs/ASSETS.md`.

## The split

| Engine owns | A game owns |
|---|---|
| When things happen: pacing, frames in flight, the render pass | What happens: pipelines, uniforms, draws |
| Depth convention (reversed-Z), depth buffer, clear values | Shaders, materials, lighting values |
| Camera, input, simulation clock, mesh loading, maths | Scene content, game rules |

A game implements `GameLoop` (four methods) and hands itself to `FrameRenderer`.

## Reversed-Z is enforced here on purpose

Reversed-Z needs the projection, the depth compare function and the clear value to agree, and a
mismatch renders **nothing at all** rather than rendering badly. Three constants that must match,
spread across three files, in every game built on it, is a trap that will eventually be sprung. So
`FrameRenderer` owns the clear value, `makeDepthStencilState()` hands back the matching compare, and
`matrix_perspective_right_hand_reverse_z` is the projection. Use all three and they cannot disagree.

## The interface is drawn after tone mapping, and that is structural

`GameLoop.encodeHUD` runs after `encode`, in the same pass, and `HUDRenderer`'s pipeline applies no
curve. This is the one piece of ordering the engine enforces rather than documents, because the
failure is silent: a HUD drawn inside the scene's shading goes through exposure and a filmic curve
like everything else, and a brand colour arrives desaturated and shifted with nothing to say why.

**`UIColor` makes the distinction a type.** Scene colour is *radiance* — unbounded, linear, tone
mapped. Interface colour is a *specification* — it must land on screen as exactly the value it was
authored as. `UIColor` takes an sRGB hex, converts once to linear, and the `_srgb` drawable encodes
back on write, so the round trip is exact. Verified on-device by reading pixels back: `#00C2FF`
authored arrives as `#00C2FF` on screen.

`HUDRenderer` draws rectangles, lines and **text** in screen space. **There is still no layout and
no widgets** — those arrive when a game needs them and can show what shape they should be.

**Shapes and text share one pipeline.** `FontAtlas` reserves a fully opaque texel that solid
geometry samples, so "coverage" is 1 for a rectangle and the maths is identical either way. One
pipeline means one draw call, and — more usefully — that shapes and text composite in submission
order, so a panel drawn before its label lands behind it without any sorting.

`FontAtlas` rasterises an installed font at launch with CoreText rather than shipping a baked sheet:
a baked atlas is another asset to generate, version and keep in step with the metrics describing it,
and those drift apart. It is a bitmap, not signed distance fields — SDF is the right answer
eventually and a materially bigger piece of work, so this rasterises generously and scales *down*,
which is the direction that stays sharp.

## Distribution-agnostic, deliberately (2026-08-26)

**This package is not the thing being distributed — a game is — so it must not assume how.** It has
to run sandboxed or not:

- **Never assume a writable location outside the container.** No hard-coded absolute paths, nothing
  written beside the executable, no "documents folder".
- **Never require an entitlement a sandboxed app cannot get.**
- **Load resources from bundles**, not arbitrary disk paths.

**The expensive part of App Store distribution was never the sandbox — it is retrofitting file access
that assumed free rein.** Holding this constraint costs nothing and keeps both doors open, so a game
can ship direct *or* on the store without the engine changing.

A game picks its own store, and that is the game's local fact, never a constraint this package may
encode. **The engine must run sandboxed or not**, because it is not the thing being distributed.

## Conventions## Conventions

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**, matching the game targets. Anything pure — maths,
  simulation, anything bound for a render thread — must say `nonisolated` explicitly. Making a type
  `public` also forces `Sendable` to be stated, which is a feature: it makes "is this safe to pass
  between concurrency domains?" a decision rather than an accident.
- **Swift 6 language mode**, tools version 6.2.
- **Metal 4 only.** `FrameRenderer.init` returns nil without `supportsFamily(.metal4)`.

## How a game consumes it

A Swift package dependency — by URL, or by relative path for a checkout sitting beside the game.

> **A relative-path dependency means the consuming project does not build from its own checkout
> alone** — this repository has to be checked out beside it at the expected path. Depending on it by
> URL avoids that entirely and is the better default for anybody who is not developing both at once.

## The sample game (2026-09-07)

`Sources/WindageSample/` — a complete, deliberately dull first-person walkthrough, built against
**the engine's public API only**.

**It is not a demo, it is a test.** An engine extracted from one game and consumed only by that same
game will grow an API shaped like that game's source layout, and nothing will say so. The sample is
the standing check that somebody who did **not** write the engine can build with it: if it cannot be
made to work without reaching inside, the API is wrong and the engine gets fixed, not the sample.

It deliberately has:

- **Levels that are files, not code.** `courtyard.json` and `ruins.json` ship in
  `WindageSampleCore`'s resources and are loaded through `Level.load(named:bundle:)` — the same call
  a game makes. **They used to be Swift functions that built a `Level`**, generated to disk on first
  run, and that was the sample teaching the opposite of what the format claims: a level assembled by
  a function says the file is an export. The files were generated once from those functions, so the
  courtyard is byte-for-byte the courtyard it always was, and the functions are gone.
- **No art dependency.** Its three meshes are hand-written OBJ files of a box, a taller box and a
  ground quad. A sample that needs an asset pack cannot be run by whoever just cloned this.
- **No Xcode project.** `swift run WindageSample`. Anything requiring a project is a thing the reader
  must own before they can start.
- **No cleverness.** One directional light, no textures. A sample with impressive rendering teaches
  the reader about the rendering. It does draw **cascaded shadows**, because a sample with no
  shadows cannot show that the shadow maths in this package works — see below.

**It found an engine bug on its first run, which is the entire argument for it.** `swift build`
compiles no Metal at all — Xcode does, SwiftPM's CLI does not — so anything calling
`makeDefaultLibrary(bundle:)` failed outside Xcode, with a blank window and nothing useful logged.
`ShaderLibrary` now falls back to compiling the `.metal` source at runtime, and both the HUD and the
sample go through it. That bug had been latent since the engine was written and could not have been
found by a consumer that is an Xcode app.

Two smaller ones it also surfaced: Swift's `print` is fully buffered when stdout is not a terminal,
so a piped run of the sample showed nothing at all until it set `setbuf(stdout, nil)`; and a sun
direction that sounds pleasant is not the one that lights the shot — the first courtyard lit only
the faces the camera could not see and read as black boxes.

## The editor (2026-09-07)

`LevelEditor` — selection, move/rotate/scale/duplicate/delete, undo/redo, a dirty flag, save. Press
**Tab** in the sample to use it: crosshair at something and **click** (or space) to pick, arrows to
move, **q/e** up and down, **a/d** to turn, **-/=** to scale, **b** to copy, **⌫** to delete,
**⌘S** save, **⌘Z** undo, **⌘⌫** discard the saved copy and go back to the level this repository
ships.

**All of the editing lives in the engine and none of it needs a window.** A selection, a set of
operations, an undo stack and a dirty flag have nothing to do with rendering and everything to do
with the format — so they run in `swift test` in milliseconds, and the sample only turns keys into
them and draws the result. It is the same argument for splitting a game's logic out
of its app target: an editor testable only by clicking is an editor nobody tests.

It also means **the game that ships is not the editor**. A game can embed one, a separate tool can
drive one, and neither reimplements what "nudge the selected thing 0.5 m" means.

Deliberately absent: gizmos, snapping, multi-select, prefabs, a scene graph. Those cannot be designed
correctly before a second game has pushed on them — the same rule the rest of this engine is built
under.

> **Three things running the sample found that its own tests could not.** The `"solid"` tag was in
> the level file and nothing read it, so you walked through every wall — a file saying something
> untrue is worse than a file not saying it. `BoundingBox` had ray and segment tests but no
> point-in-box test, the most basic query it could have. And the engine logged gamepad connections
> under the name of the *game* it was extracted from — a product that was not running, which
> anybody else would have seen in their own console.

## A game loop, and what it needed (2026-09-07)

The walkthrough proved the engine could **load and draw** a level. It could not say whether anything
with *state* worked — a pause that is not a stall, an outcome, progress kept between runs. So the
sample became a small game: touch every marked crate before the clock runs out.

**`SaveStore` is the one thing that had to come into the engine.** The distribution rule says the
engine may never assume a writable location outside its container, because a game may go to the App
Store — and that rule is easy to state and easy to break, since the natural thing to write is a path
and a path beside the executable works right up until somebody sandboxes the app. So there is one
place that knows where a game may write. It writes atomically, because a crash mid-write leaves a
truncated save, and it returns `nil` rather than throwing on a file it cannot decode: losing a high
score is a disappointment, refusing to launch is a bug report.

**Almost nothing else was needed, which is the useful finding.** A pause is "do not advance", not
"stop the loop" — the frame loop keeps running, the scene still draws, the window still resizes — so
pausing is a game's decision and the engine does not have to provide it. Modes, objectives, scoring
and win conditions all sat in the game with no engine change at all.

### The sample is split the way a game should be

`WindageSampleCore` (logic, no window) + `WindageSample` (the app) + tests against the core — the
same split this package recommends to any game, for the same reason: a win condition, a
clock, a pause and a save are exactly the things that fail quietly, and none of them need a drawable.

> **And one the tests found that running it did not.** `SampleRun` kept its progress in a shared
> `static` store — fine for a game with one process, wrong the moment there are two of anything.
> Swift Testing runs tests in parallel, they all wrote the same file, and results depended on which
> finished first. The store is injected now, which is also what a game with save slots or profiles
> would need.

> **Two things running it found that its tests did not.** The HUD asked for text at "20" and got ten
> points, because the viewport is in *pixels* and a Retina drawable is twice the points — reported as
> unreadable. It scales against a 1080-pixel reference now. And the collect
> radius was measured to a crate's centre without allowing for the crate's own width, so the player
> stood visibly against one and nothing happened.

## Sound in the sample (2026-09-08)

`AudioEngine` had exactly one consumer, which is the position every other part of this engine was in
before the sample existed. The sample now plays a pickup **at the crate**, and a win or a loss flat
at the listener.

**Positional on purpose.** The whole reason this engine spatialises is that a sound should come from
where the thing is; a sample that played everything flat would leave the positional path — the part
with the head-related work in it — exercised by nothing in this repository.

**The sounds are generated, not shipped.** `Tools/make_sample_sounds.py` synthesises three short WAVs
from sine partials, the same way the meshes are hand-written OBJ. Somebody who clones this repo can
build and run it without downloading anything, and that is the point of the sample.

**Audio is optional and never fatal.** A machine with no output device, or an audio engine that will
not start, prints a line and the game runs quiet. Sound is the first thing to go wrong on somebody
else's hardware and the last thing that should stop them seeing the sample.

> **`AudioEngine.load` takes a bundle with no default, and that was a change rather than a note.**
> It defaulted to `.main`, which is right for an app bundle and wrong for a SwiftPM executable —
> there `.main` is the executable itself and holds no resources, so every load failed and printed.
> This was first written down as a papercut worth leaving; it was not. There is no default correct
> for both, and one silently wrong for either is worse than making every caller say where its sounds
> are. An app passes `.main`, a package target `.module`.

**A step reports what happened rather than calling back.** `SampleRun.step` returns an `Events` value
naming what was collected and where. A callback from inside a simulation step runs on whatever thread
the step is on and invites the caller to mutate the run mid-step; a returned value cannot, and it
keeps the run testable without a spy.

## A second level (2026-09-08)

The sample ships two: **COURTYARD** and **RUINS**. `n` switches, and winning moves you on.

**One level is not enough to find out what assumed there would only ever be one**, and three things
had. Meshes were loaded once at startup from the first level's list, so anything new in the second
drew nothing. The camera was placed in `init`, so a new spawn was ignored. The run was sized once, so
a level with a different number of objectives could not be finished.

**None of those would have been found by a second *copy* of the first level.** RUINS differs
deliberately, in exactly the ways that break each one: a mesh the courtyard never uses, a different
spawn and facing, nine objectives against six, and its own sun.

**The save format's version field earned its keep on its first use.** `Progress` held one
`bestSeconds`, which was right with one level and silently wrong with two — the second level's first
win would have overwritten the first's record. Best times are per level now, and a v1 save *migrates*
rather than being discarded, so nobody loses a time to a format change. Migration runs one way: a
save written now is v2 and never writes the old field back.

## Shadow cascades (2026-09-09)

`ShadowCascades` — the split distances, the light basis, texel snapping, per-cascade depth bias and
the blend bands. **Extracted from a shipping game**, where they had worked and been tested for two
weeks.

**The extraction is what turned its constants into parameters, and that is the whole value of doing
it.** It was written for one valley: four splits ending at 850 m, because that is the shot that game
is about. None of the maths cares — but they were `static let`s, so a second game could have the
mechanism only by taking a sniper range's geometry with it. The sample's courtyard is sixty metres
across and would have spent 99% of every shadow texel on empty ground.

So a cascade set is a value you configure, and a game's numbers live with the game:

```swift
let far  = ShadowCascades(splits: [30, 90, 260, 850])   // a long-range outdoor game
let near = ShadowCascades(splits: [8, 22, 55, 120])     // an interior, or a small arena
```

Three things in it are load-bearing and easy to undo by accident, all inherited from the game that
proved them:

- **The light matrix snaps to whole texels.** Without it, moving the camera slides the sampling grid
  across the world by sub-texel amounts every frame and every shadow edge crawls.
- **Bias scales per cascade.** A cascade covering 8× the world per texel needs roughly 8× the bias;
  one constant for all four either leaves acne in the far cascades or detaches contact shadows in the
  near one.
- **Each cascade fades into the next over the last 12% of its own span** — measured from its own
  span, not from zero, because the splits are geometric and a fixed fraction of the far split would
  be wider than the whole near cascade.

**The tests moved with the code rather than being rewritten from it**, and still run against
the same numbers — so the extraction is checkable against the behaviour it had before it moved.
That is the standing rule after a rewrite-from-memory of this exact light basis was very nearly
committed, wrong, during an earlier split.

**What did not come:** the pass itself. A texture, a pipeline and an encoder either work or draw
nothing, and one game's arrangement of them has proven no seam.

## Shadows in the sample (2026-09-09)

The sample draws four cascaded shadow maps. It exists as a second implementation of the pass, and it
earned its keep before it drew anything:

**The depth bias was silently coupled to the scene's scale, and no one game could have shown it.** It
was a literal in the light's *normalised* depth units — `0.00035 * cascadeBiasScale` — which means a
different number of metres for every value of `lightDepthRange`. At a range of 1500 the far
cascade's bias worked out to **sixteen metres**, so in a courtyard whose tallest object is three
metres, every fragment biased itself to "lit" and not one shadow appeared. Nothing was wrong while
there was only one scene scale, which is exactly the class of fault a second consumer exists to find.

`ShadowCascades.normalizedDepthBias(forCascade:)` derives it from the **world size of a texel**
instead, because that is what the error inside a texel is proportional to; `biasTexels` is therefore
in texels and is scale-free. Three tests pin it.

**The pass itself is still in the sample, not in this package.** A shadow pass has to bind a
particular vertex layout and a particular per-object uniform buffer, and what the general seam looks
like is a question a *third* implementation answers better than a second one guessing. What the two
already agree on — the texture array, the front-face cull, the reversed-Z depth state, the
slope-scaled bias — is the shape to extract when something else needs it.

> **The sun moved, and it is level data, not code.** Both sample levels had the sun behind the
> camera, which is invisible without shadows and useless with them: every shadow falls away from the
> viewer and hides behind its own caster. A side sun lights the faces the player is looking at *and*
> throws its shadows across them. That is a `sunYaw` in `courtyard.json`, which is the point of
> levels being files.

## Culling (2026-09-08)

`Frustum` — the planes of a view-projection and a conservative box test. **Extracted from a probe**,
which is what a probe is for.

It was written for a different game shape: trenches are dense, close, occluding geometry. It carried
a note saying an open plain does not need culling, because a plain is somewhere nearly
everything is in front of the player. **That stopped being true** when the range gained a colony,
ruins and 260 sprigs of flora — a 65° field of view is under a fifth of the circle, and the rest of
an 854-object scene is behind the player's shoulders. Measured in a game using it:

| facing | drawn of 870 |
|---|---|
| down the range | 611 |
| across the valley | 111 |
| back up the hill | 9 |

Two consumers and working, tested code, which is what the extraction rule asks for.

**The finding it was written to produce still stands: a Windage Engine frustum has five planes, not
six.** The projection's far plane is infinite, so the far row extracts as a zero normal; code written
expecting six either carries a plane that always passes or divides by zero normalising it.

> **Shadow casters are culled per *cascade*, never by the view.** Something behind the player still
> casts into the scene in front of them, and testing casters against the camera's frustum is the
> classic way to make shadows vanish when you turn round. Each cascade's own frustum is the exact
> test, because it is the volume that cascade renders.

## Testing

`swift test`. Tests live with the code they cover; a game
keeps only the tests that are about *its* assets and *its* pipeline.

> **SwiftPM's CLI does not compile Metal.** Xcode compiles the package's `.metal` sources into
> `default.metallib` inside the resource bundle; `swift build` silently ignores them. So `swift test`
> exercises everything except the shaders, and anything needing a GPU has to be verified by running
> a game. The `.metal` file is declared in `resources:` so that SwiftPM still synthesises
> `Bundle.module`, which is where the pipeline looks for its library.

## Building it as if it were licensable

**The posture, decided 2026-08-24: build it to a standard that would survive being licensed, but do
not chase licensing yet.** The discipline is free and pays for itself in-house; the productisation is
not, and the one change that would matter most to an outside licensee — running on Windows — is the
thing Mac-first deliberately defers.

### What the competition actually looks like

| | |
|---|---|
| **Unity, Unreal, Godot** | General-purpose, enormous, free or cheap at small scale. Nobody licenses a new general engine into this. |
| **Genre-specialised engines** | Almost nothing licensable. id Tech, Source 2 and CryEngine are effectively unavailable or bundled with a publisher relationship. |
| **Rendering libraries** (bgfx, Diligent, Forge) | Cross-platform renderers, not engines. They solve the platform layer this project deliberately does not have. |
| **Mac-native game engines** | Essentially an empty field — **and that is the honest problem, not the opportunity.** The field is empty because the addressable market is small, not because nobody thought of it. |

**So the realistic niche is narrow: a Mac-native, Metal-4, first/third-person shooter foundation.**
That is a real gap, and it is a gap of a few dozen potential users, most of whom would need Windows
before they could ship commercially.

### What to do now, because it costs nothing

These are good practice for one consumer and prerequisites for many, so they are worth doing whether
or not a licence ever happens:

1. **Keep the API honest about what it owns.** No game-specific assumptions leaking in; `MeshLoader`
   taking a semantics map instead of importing a game's `ShaderTypes` is the model.
2. **Semantic versioning from the first outside consumer**, and a changelog. Cheap now, impossible
   to reconstruct later.
3. **Every feature arrives with a test and a paragraph on *why*.** The reasoning is what makes an
   engine teachable; the code alone is not.
4. **A sample that is not a game.** The smallest project that draws a lit, shadowed scene with a
   moving camera — the thing an evaluator runs in five minutes.
5. **Keep the extract-when-proven rule.** It is also the best defence against the failure mode a
   licensable engine invites: building features nobody has needed yet.

### What NOT to do yet

- **Do not add a platform abstraction layer speculatively.** Windows support is a real port, not an
  `#ifdef`, and writing the abstraction before the second platform exists produces the wrong seams —
  the same trap as designing an engine from one game.
- **Do not build a standalone editor application.** It is the single largest cost in an engine, and
  `LevelEditor` already covers the shape that matters: a game embeds it and edits its own levels in
  place.
- **Do not take on support obligations.** A licence means answering questions on someone else's
  schedule; that is a business decision, not an engineering one, and it competes directly with
  shipping games.

### The repository says "all rights reserved", on purpose (2026-09-08)

`LICENSE` reserves every right and grants nothing. **It is not the licensing decision** — that is
still the one deferred below. It exists because a repository with no licence file is *already* all
rights reserved, and leaving the file out means a reader cannot tell whether that was a decision or
an oversight. Here it was an oversight.

**The asymmetry is the whole argument for reserving first.** A permission granted publicly cannot be
withdrawn from anyone who already has the code; a reservation can be relaxed whenever you like. So
the cautious file today costs nothing and keeps every option, and a generous one today closes most of
them permanently.

### The licence is PolyForm Small Business 1.0.0 (decided 2026-09-08)

Settled. Source-available, not open source: free to use, modify and ship commercially for an
organisation under 100 people and under USD 1,000,000 prior-year revenue, a paid licence above
either, and no royalty, report or audit clause to administer. Attribution rides along on the
licence's own `Required Notice:` mechanism.

`LICENSE` reserves every right until the PolyForm text goes in, which happens when the engine is
actually handed to somebody. That is a five-minute swap on the day, not an open question.

**Revisit when two things are true:** a game has actually shipped on this engine, and a
second platform exists. Before that, licensing would be selling an unproven foundation for a
single platform — which is a worse product than the games it is meant to be making.
