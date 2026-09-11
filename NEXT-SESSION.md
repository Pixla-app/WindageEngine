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

**Reproduce a screenshot:** `WINDAGE_SAMPLE_LEVEL=1 WINDAGE_SAMPLE_CAMERA=-4,20,4,0,-62 swift run
WindageSample` — level index, then `x,y,z,yaw,pitch` with the angles in degrees. **A camera placed
this way flies** — a screenshot position is a viewpoint, not somewhere to stand, and gravity would
pull it to the floor before the first frame.

**Walk it without a keyboard:** `WINDAGE_SAMPLE_LEVEL=1 WINDAGE_SAMPLE_WALK="d:0.75 w:1.0 w:0.4 wait:1"
swift run WindageSample` — key names and seconds, **pressed through the same path a keyboard uses**,
and the log says where the feet ended each segment. `o:0.1 return:0.1 i:0.1 o:0.1` opens settings and
rebinds forward to I. **A script that changes settings writes the real settings file** in Application
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
- **A game adopts afterwards.** If a game already has its own version of something the engine now
  owns, replacing it is that game's work, on that game's schedule — not a prerequisite here.
- **A second sample arrives only when a capability needs a shape the courtyard cannot express.**
  Skinned animation was expected to be that case and **was not** — what it needed was a character
  standing *in* the courtyard, not a second scene around it. The bar is higher than it looked.

## State — 2026-09-10

454 tests. The sample is a complete small game: a lit and **shadowed** scene, two levels loaded from
JSON, an in-game level editor, positional audio, a win/lose loop, a save — and now **animated
characters** — all against the public API only.

**In the package:** frame pacing and frames in flight (`FrameRenderer`, `FixedTimestep`), the
reversed-Z convention, `Camera`, `InputState` (keyboard, mouse, gamepad), `MeshLoader`, `Math`,
`BoundingBox`, `Volume` and the one hit test, `Frustum`, `ShadowCascades`, `Level` and `LevelEditor`,
`HUDRenderer` and `FontAtlas`, `AudioEngine`, `SaveStore`, `ShaderLibrary`, `Skeleton`,
`AnimationClip`, `SkeletonPose` and `RigLoader`, `Material`, `TextureSlot` and `TextureStore`,
`ToneMapping`, `ProceduralSky` and `EnvironmentMap`, `PunctualLight` and `LightSet`,
`ClusterGrid` and `ClusteredLights`, `TransformHierarchy`, `CharacterController`, `ParticleSystem`
and `ParticleRenderer`, **`InputBindings` and `PlayerSettings`**, and — for the lamps that cast —
`ShadowMap`, `ShadowAtlas` and `ShadowCubes`.

## Done 2026-09-10 — braziers (0.6.10)

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

## Done 2026-09-10 — footsteps and landings (0.6.9)

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

## Done 2026-09-10 — keys a player can change (0.6.8)

**`KeyCode`, `InputBindings`, `PlayerSettings`**, `InputState.bindings` and `flagsChanged`, and
`AudioEngine.masterVolume`. The sample has a settings screen on **O** — eight keys, look sensitivity,
invert look, volume, brightness, reset — saved the instant anything changes.

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

## Done 2026-09-10 — particles (0.6.7)

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

## Done 2026-09-10 — a body with feet (0.6.6)

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

## Done 2026-09-10 — things that hang off other things (0.6.5)

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

### What it found in 0.6.4

**The sample assigned cube slices once, at level load** — correct for lamps that do not move, and the
first lamp that did move exposed it. A cube recorded from where the lamp *was* is a shadow that lags
the hand. Assigned every frame now; it is a sort of five elements.

### Measured

Two frames of the same figure, waving and not: the lantern is at the end of the outstretched arm in
one and raised with it in the other. The lantern lights change **24.5% of the frame** against having
none; their own cube shadows a further **4.7%**.

## Done 2026-09-10 — point lights cast too (0.6.4)

**Every lamp in the sample stops at a wall now**, aimed or not. `ShadowCubes` is a cube-array depth
texture, the six face matrices, and the pass that records them.

**A cube array, not tiles of the atlas — which is not what 0.6.3 predicted.** Two of the three things
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

## Done 2026-09-10 — shadows for the lamps (0.6.3)

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

## Done 2026-09-10 — clustered shading (0.6.2)

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

## Done 2026-09-10 — spot lights (0.6.1)

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

## Done 2026-09-10 — lights that are not the sun (0.6.0)

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

## Done 2026-09-10 — emission (0.5.2)

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

## Done 2026-09-10 — packed material maps (0.5.1)

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

## Done 2026-09-10 — a level says what sky it is under (0.5.0)

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

## Done 2026-09-10 — image-based lighting (0.4.1)

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

## Done 2026-09-10 — a microfacet specular (0.4.0)

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

## Done 2026-09-10 — tone mapping (0.3.0)

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

**This is the only "next" list. The top item is what "next" or "continue" means.** When one is
done it comes off, and the one below it moves up. Anything not being built goes under *Parked*
below, never in this list.

1. **Gamepad rebinding.** The keyboard is rebindable and the pad is not: its layout is the console
   convention written into `InputState`, with reserved buttons on purpose. The same `InputBindings`
   shape with a button per action, and the settings screen showing whichever device is connected.
   **Proved in the sample by** a rebound button in the settings file surviving a relaunch — the pad
   itself cannot be scripted, so the input path is tested in the package.

2. **A camera dip on landing.** The controller reports how hard a landing was and nothing shows it
   but the sound. A short dip of the view, scaled by impact speed, applied to the view and never to
   the aim — the same rule as the slide's. **Proved in the sample by** the scripted drop off the steps
   logging the dip's depth, and a screenshot mid-dip.

3. **Lights that belong to a placement.** A brazier and its lamp are two entries in the level file,
   kept together by a test. Move the brazier in the in-game editor and the lamp stays where it was —
   a bug waiting for the first person to edit a level. A placement should be able to carry its light,
   offset from it, placed through the transform hierarchy. **Proved in the sample by** moving a
   brazier in the editor and the pool of light going with it.

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
- **Standing up under something low.** The controller lets a crouched player stand up into a
  ceiling. Nothing in either level has an overhang to find it; it is a few lines when one does.
- **Standing on something that moves.** A deck or a lift. The engine's reference-frame probe is the
  shape of it; nothing in the sample moves yet.

## Standing reminders

- **Update this file before the session ends.** Do not wait to be asked.
- **The licence is PolyForm Small Business 1.0.0.** Settled; `LICENSE` reserves rights until the day
  the engine is handed to somebody. Not an open question.
- **Nothing enters this package speculatively.** Working, tested code proves the seam, or it stays
  where it is.
- **No game's name appears in this repository.** Describe the shape, not the product.
