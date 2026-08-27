# Windage Engine

The studio's shared Swift/Metal foundation. **`WE`** prefix.

> Studio-level, per the "would a second title need this?" rule in `~/PixlaGames/CLAUDE.md`. It is
> **not** a title and does not live under one.

## What it is, and what it deliberately is not

It is the part of a native Pixla Games title that was identical every time it was written: frame
pacing, frames in flight, the depth convention, mesh loading, camera, input, the maths.

It is **not** a general-purpose engine, and it is not trying to become Unity. There is no scene
graph, no ECS, no material system, no editor. Those are the parts that cannot be designed correctly
from one game, and inventing them before a second title stresses them differently is how a studio
ends up maintaining an engine instead of shipping games.

**Everything here was extracted from working, tested code in Coldkeel — never designed speculatively.**
That rule is the whole quality control. If a thing has one consumer and no proven seam, it stays in
the title until a second title shows where the seam actually is.

## Priority: the engine comes first (2026-08-26)

**The extraction rule above is unchanged** — a capability enters this package only once real, working,
tested code has proved where the seam actually is. What follows is not a loosening of that. It is the
*sequencing* around it, which was previously implicit and got read as "the engine happens when a game
happens to need it".

1. **The engine comes first — above every title, including Coldkeel.** No engine, no games. Work that
   makes the foundation right outranks work that makes one title further along.
2. **Coldkeel is second**, and is the primary driver: the most active title, and the one whose working
   code is where extractions come from today.
3. **The other locked-in titles are third — but not deferred.** Each gets a **minimal, unpolished
   build now**, built specifically to exercise whatever makes that title's needs genuinely *diverge*
   from Coldkeel's and from each other's.

### Why the third point is not a contradiction

Extraction from one game is how you build a foundation shaped like that one game. Coldkeel is a
sniper title: long sightlines, few actors, a shot that takes a second to land. An engine extracted
only from it will be quietly excellent at that and quietly wrong everywhere else — and nothing will
say so until a second title is far enough along that the mistake is expensive.

A skeletal build of each locked-in title is the cheapest possible instrument for finding those
divergences **while they are still cheap to act on**. It is not a head start on those titles; it is a
test rig for this package.

**Not every title needs every capability, and that is the point.** The goal is that by the time full
development shifts to one of them, the capability it needs already exists here and is already proven —
rather than that title stopping for three months to grow the engine sideways.

> **What this does not license.** A divergence found by a skeleton is a *reason to look*, not a
> licence to build speculatively. The rule still holds: something enters this package when working
> code proves the seam. A skeleton that merely suggests a title *might* want something is a note, not
> a feature.

### Which titles

The shooter lane, from the catalogue in `~/PixlaGames/CLAUDE.md`: **Gunhollow**, **Brassgrave**,
**Sedgefall**, **Brinewake**. All four are Windage Engine titles by the studio's own stack rule, and
all four have names, domains and trademark screening done.

**Royal Valor is explicitly outside this**, and stays outside. It is the fantasy MMO, it is not in the
shooter lane, and nothing here is expected to reach it.

## The split

| Engine owns | A title owns |
|---|---|
| When things happen: pacing, frames in flight, the render pass | What happens: pipelines, uniforms, draws |
| Depth convention (reversed-Z), depth buffer, clear values | Shaders, materials, lighting values |
| Camera, input, simulation clock, mesh loading, maths | Scene content, game rules |

A title implements `GameLoop` (four methods) and hands itself to `FrameRenderer`.

## Reversed-Z is enforced here on purpose

Reversed-Z needs the projection, the depth compare function and the clear value to agree, and a
mismatch renders **nothing at all** rather than rendering badly. Three constants that must match,
spread across three files, in every title, is a trap that will eventually be sprung. So
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
no widgets** — those arrive when a title needs them and can show what shape they should be.

**Shapes and text share one pipeline.** `FontAtlas` reserves a fully opaque texel that solid
geometry samples, so "coverage" is 1 for a rectangle and the maths is identical either way. One
pipeline means one draw call, and — more usefully — that shapes and text composite in submission
order, so a panel drawn before its label lands behind it without any sorting.

`FontAtlas` rasterises an installed font at launch with CoreText rather than shipping a baked sheet:
a baked atlas is another asset to generate, version and keep in step with the metrics describing it,
and those drift apart. It is a bitmap, not signed distance fields — SDF is the right answer
eventually and a materially bigger piece of work, so this rasterises generously and scales *down*,
which is the direction that stays sharp.

## No App Store sandbox is baked in (2026-08-26)

The studio's distribution target is a **direct, notarized download outside the Mac App Store** — see
`~/PixlaGames/CLAUDE.md`. The consequence for this package is a constraint on what it may assume:

- **No sandbox assumptions.** Full filesystem access is available to a consumer; nothing here may be
  written as though a container were the only place a title can read or write.
- **No On-Demand Resources.** Assets are files a title ships and loads.
- **No App Store IAP.** Nothing here has an opinion about payment.

Notarization gets a build past Gatekeeper and asks nothing of the engine's design. **If the App Store
is ever pursued, sandbox compliance is retrofitted then** — the same deferred-until-needed posture as
Windows and licensing, both below.

> Coldkeel currently ships sandboxed because its Xcode template set it that way and it costs nothing
> there yet. **That is a title's local fact and must not become an engine assumption**, which is
> exactly why it is written down here.

## Conventions

- **`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`**, matching the game targets. Anything pure — maths,
  simulation, anything bound for a render thread — must say `nonisolated` explicitly. Making a type
  `public` also forces `Sendable` to be stated, which is a feature: it makes "is this safe to pass
  between concurrency domains?" a decision rather than an accident.
- **Swift 6 language mode**, tools version 6.2.
- **Metal 4 only.** `FrameRenderer.init` returns nil without `supportsFamily(.metal4)`.

## How a title consumes it

A local Swift package reference by relative path. From a title at
`~/PixlaGames/<Title>/<Title>-Client/`, that path is `../../Studio/WindageEngine`.

> **The consequence, stated plainly:** each title is its own git repository and the engine lives in
> the studio repo, so a title does **not** build from a fresh checkout of its own repo alone — the
> studio repo has to be checked out alongside it at the expected relative path. That is the price of
> one shared foundation with no package registry, and it is worth knowing before someone clones a
> title on a new machine and finds it will not build.

## Testing

`swift test --package-path Studio/WindageEngine`. Tests live with the code they cover; a title
keeps only the tests that are about *its* assets and *its* pipeline.

> **SwiftPM's CLI does not compile Metal.** Xcode compiles the package's `.metal` sources into
> `default.metallib` inside the resource bundle; `swift build` silently ignores them. So `swift test`
> exercises everything except the shaders, and anything needing a GPU has to be verified by running
> a title. The `.metal` file is declared in `resources:` so that SwiftPM still synthesises
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

1. **Keep the API honest about what it owns.** No title-specific assumptions leaking in; `MeshLoader`
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
- **Do not build an editor.** It is the single largest cost in an engine and the studio does not need
  one yet.
- **Do not take on support obligations.** A licence means answering questions on someone else's
  schedule; that is a business decision, not an engineering one, and it competes directly with
  shipping titles.

**Revisit when two things are true:** a Pixla Games title has actually shipped on this engine, and a
second platform exists. Before that, licensing would be selling an unproven foundation for a
single platform — which is a worse product than the games it is meant to be making.
