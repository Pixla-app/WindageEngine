# Changelog

Every release of Windage Engine, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) under the pre-1.0 rules set out in
`README.md` § "Versioning".

**Written for somebody upgrading**, which means the entries that matter most are under *Changed* and
*Removed*. A new type costs a reader nothing; a changed one costs them a build.

## [Unreleased]

Nothing yet.

## [0.6.11] — 2026-09-10

**Controller rebinding.** Jump, crouch, sprint and brace can be moved to any face button, shoulder or
L3. The sample's settings screen shows the controller's rows whenever one is connected, and can be
driven entirely from the pad.

### Added

- **`PadButton`** — a button by position (`south`, `east`, `west`, `north`, the shoulders, the stick
  clicks), and `name(on:)` for what the connected pad prints on it.
- **`PadBindings`** — the four actions that are buttons, with swap-on-conflict, R3 refused, and
  tolerant decoding; **`PlayerSettings.padBindings`**.
- **`InputState.padBindings`**, **`useGamepad(_:)`**, **`acceptsPadActions`**,
  **`padButtonsPressed`** and **`padMenuPressed`**. `gamepad` is public.

### Changed

- **`InputState` reads the pad's buttons through `padBindings`**, with one press-edge set for every
  button instead of a remembered flag per fixed button. The standard layout is the old fixed one.

### Decisions

- **By position, not by name.** The bottom face button is A on an Xbox pad and Cross on a DualSense;
  the thumb learned the position, so that is what is stored. The name shown is the connected pad's own.
- **Only the buttons that are actions.** Sticks move and look, triggers aim and fire, the d-pad steps,
  the menu button opens the menu — the convention stays put. **R3 is refused**: it is the engine's
  scroll notch, as the arrows are its steps.
- **Square, Triangle and R1 are only unbound by default.** They are kept free so a title can grow a
  reload or a second weapon; a title that has one reserves it, and a player of one that has not may use
  them.
- **A menu that has the pad turns its actions off.** A keyboard key the menu takes never reaches
  `InputState`; a pad is polled there, so a Circle pressed to leave the settings screen would also have
  crouched the player behind it. The presses are still reported for the menu to read.
- **The menu reads raw presses, not the bindings** — it is where the bindings change, and a menu that
  followed them would move its own "change" button the moment somebody rebound jump.

### A pad nobody holds

**`GCController.withExtendedGamepad()` makes a controller whose buttons are set from code**, and
`useGamepad(_:)` points `InputState` at it — the system never makes one `current`, since it is not
connected to anything. The engine's tests press real `GCExtendedGamepad` buttons now, and the sample's
scripted walk takes `pad.south`, `pad.menu`, `pad.down` and the rest.

**The virtual pad's d-pad only moves through its axes.** Setting `dpad.down` as a button is accepted
and does nothing; the first scripted run opened the settings screen with the menu button and could not
leave its first row.

### Verified by driving it

Two launches, controller only: open settings with the menu button, d-pad down to *Pad jump*, Cross,
R1. R1 then jumps **0.97 m** and Cross does nothing; the file reads `"jump" : "rightShoulder"`.
**Relaunch**: R1 still jumps, Cross still does not; *Reset to defaults* from the pad puts jump back on
Cross. The hint line reads "r1 jump" from the bindings. The test settings file was deleted afterwards.

## [0.6.10] — 2026-09-10

**Braziers.** The ruins' two lamps stand over iron braziers now, with coals that glow from an emissive
map and embers that come off the coals rather than out of the air. No engine change; the sample, its
level and its tools.

### Added — in the sample

- **`brazier.usda`** and its three maps, from a new **`Tools/make_sample_brazier.py`**.
- **A test that every coneless lamp in a level stands over a brazier, above its rim, and every
  brazier has its lamp.** A level stores lights and meshes separately; nothing else keeps them
  together.

### Fixed — in the sample, and it was shipped

**The ruins had flat white pillars and steps whenever you walked into them from the courtyard** —
which is the only way a player reaches them. `init` loaded the first level's meshes and resolved their
textures; the path that loaded the *next* level's meshes resolved none. **Every screenshot for a week
had opened the ruins directly with `WINDAGE_SAMPLE_LEVEL=1`**, which goes through `init`, so the
override written to make pictures repeatable was exactly what kept this one out of them. One loading
path now, for both.

### Why USD, and the second thing the loader needed

**Model I/O reads no emission from an OBJ** — measured at 0.5.2 — so the one level object that makes
its own light cannot be one. The sample's level loader only ever looked for `<name>.obj`; it now tries
OBJ and then USD, since a level names a mesh without an extension.

### Placing it taught three things

- **A lamp half a metre above a bowl shadows the ground under it**, a disc a metre across. That is what
  a brazier does, and it is kept; the flame sits 0.72 m above the rim so the disc stays smaller than the
  pool around it.
- **Close light blows out a clean metal.** Iron at a bare metal's mid-grey read as cream under a lamp
  half a metre away. It is blackened now — dark, with rust catching the firelight.
- **The second lamp had been floating over a crate**, 2.4 m up to clear it, so the first brazier put
  under it stood inside the crate. Both moved to open ground.

The glow's strength is the game's (×2.5), in a table by mesh name: a file connecting `emissiveColor` to
a texture has no scalar, and ×6 read white-hot rather than orange.

## [0.6.9] — 2026-09-10

**Footsteps and landings.** The controller says when a foot comes down, when the body lands and how
hard, when it jumps, and what it is standing on. The sample plays dirt and stone footsteps, heavier
landings, and a push-off when you jump.

### Added

- **`CharacterController.events`** — this step's `.stride(foot:speed:)`, `.landed(impactSpeed:)` and
  `.jumped`, cleared at the start of every step.
- **`CharacterController.groundSolid`** — which solid is underfoot, or nil for terrain or air.
- **`Tuning.walkStride`, `sprintStride`, `crouchStride`, `firstStepPhase`.**

### Decisions

- **Footfalls come from distance actually covered, not asked for.** Pushing into a wall asks for six
  metres a second and covers none; counting what was asked for is the classic bug where a player
  standing against a wall marches on the spot.
- **Strides are longer than a person's, because these speeds are.** A walk here is 6 m/s — a jog — and
  a footstep every real 0.7 m would be eight a second. 2.6 m walking, 5 m sprinting and 1.6 m crouched
  give about 2.3, 3.6 and 1.7 steps a second: a cadence the ear takes for feet.
- **The first step comes 40% of a stride after setting off**, not a whole stride — or the start of every
  walk is silent.
- **No footsteps in a slide.** A skid with feet under it at sprint cadence would be nine footsteps a
  second from feet that are not moving.
- **A step down a stair is not a landing.** The body never left the ground; only a fall or a jump
  reports one, with the speed at contact.

### Found by the tests: stairs were climbed in half the footsteps

A stride is longer than a tread, so four treads sounded like two. The fix — a foot on every rise — was
written into the step-up in `move`, and **a test counting footsteps per tread still found two**. The
leading edge of the footprint reaches a tread before any move is refused, so the ground-following in
the vertical step lifts the body and the step-up never runs. The rule now sits in both places a body
rises; four treads, four footsteps.

### The sample's sounds

Three recordings each of dirt and stone, played in an order that takes six steps to repeat — one
recording twice a second is a machine gun. Synthesised by `Tools/make_sample_sounds.py`, seeded so a
re-run writes the same files. **The first pass clipped** every landing and every stone step; they are
normalised now. Measured, dirt sits around 1 kHz and stone around 6.5 kHz.

The player's own footsteps are **not positioned**: the engine's own rule for a sound that happens to
the player, since the ears are 1.7 m above the feet and moving with them.

### Verified by walking

The scripted walk now reports footsteps and landings per segment. On the ruins: 2 footsteps on dirt
over 4.5 m; **4 on stone** up the four treads; a landing at **7.0 m/s** off the 1.2 m drop (the physics
says 6.9); 6.2 m/s back from a jump; 5 over 12 m walking, 3 over 4 m crouched, 4 over 18 m sprinting.

## [0.6.8] — 2026-09-10

**Keys a player can change, and settings that are still there next time.** The sample has a settings
screen on **O**: the eight movement keys, look sensitivity, invert look, volume and brightness, saved
the moment anything changes.

### Added

- **`KeyCode`** — a physical key, stored by name so a settings file says `"forward" : "W"`.
- **`InputBindings`** — which key does what, with swap-on-conflict and a refused set.
- **`PlayerSettings`** — bindings, look sensitivity, invert look, volume, brightness.
- **`InputState.bindings`** and **`InputState.flagsChanged(keyCode:modifierFlags:)`**.
- **`AudioEngine.masterVolume`**.

### Changed

- **`InputState` reads every rebindable key through `bindings`.** The standard layout is the old
  hard-coded one, so nothing changes until a game changes it. `setSprinting(_:)` still works and
  combines with the bound sprint key.

### Fixed — in the sample, and it was shipped

**Shift did nothing, while the screen said "shift sprint".** macOS sends Shift, Control, Option and
Command as a change of modifier flags, never as a key press, and the sample's window did not listen for
that event. Modifiers are keys now: the window forwards `flagsChanged`, `InputState` treats a modifier
like any other key, and sprint can be bound to anything including Control. The on-screen hint is built
from the bindings, so it cannot print a key that does not work again.

**The em dash never rendered in the sample's HUD** — "PAUSED — p to resume" has shown a gap since the
HUD existed, and the engine said so in the log every run. It was not in the font atlas's extra
characters.

### Decisions

- **A key in use is swapped, not stolen.** Taking W for jump gives forward jump's old key; stealing it
  would leave a player who cannot walk and does not know why.
- **Escape, Tab and the arrows are refused**, and a game adds its own always-on keys. Escape is the way
  out — bound to anything, the player cannot get their pointer back or reach the screen that would undo
  it. A key the game consumes first is a key a binding never sees.
- **One key per action.** A secondary slot doubles every rule above and can arrive when a title asks.
- **Tolerant decoding, field by field.** `SaveStore` returns nothing for a file it cannot decode, and
  for settings nothing means everything reset — a player loses eight rebound keys because a later build
  added a ninth. A missing field takes its default, an unknown one is ignored, a key name this build
  does not know costs only that binding.
- **No apply button.** Every change is written at once; a screen that can be closed without saving is
  one a player closes without saving.
- **The tone-map curve is not a setting.** `M` still cycles it for comparison; a player's dial is
  brightness, which adds to the game's own exposure.

### Verified by driving it

`WINDAGE_SAMPLE_WALK` now presses and releases **real keys through the same path a keyboard does**,
game first and then `InputState` — it used to hand the controller a movement directly, which tested
the body and skipped everything in front of it, the Shift bug included. Two launches of the sample:

1. Open settings, rebind forward to I, close. I walks **6.05 m** in a second; W does nothing; I with
   Shift sprints **18.15 m**. The file on disk reads `"forward" : "I"`.
2. **Quit and relaunch**: the log reads `forward I`; I still walks, W still does not. Reset to
   defaults from the screen, and W walks again.

The refusal ("P is one of this game's own keys") and the swap ("Jump is W — Forward moved to Space")
were both seen on screen.

## [0.6.7] — 2026-09-10

**Particles.** Embers rise off the ruins' braziers and the figures' lanterns, a collected crate
throws a burst of green sparks, and landing from a drop kicks up dust.

### Added

- **`ParticleSystem`** — a fixed pool, deterministic bursts, oldest-recycled when full.
- **`ParticleRecipe`** — what one kind of particle is, defined by the game.
- **`ParticleEmitter`** — a steady rate, in particles per second.
- **`ParticleRenderer`** — camera-facing quads in one instanced draw, its shaders in the engine, and
  `matterLight(under:)` for lighting dust.

### Extracted, and three things changed on the way

The simulation came from a working game: fixed step, deterministic, fixed pool, and **the oldest
particle recycled when full, never the newest** — the newest burst is the one the player is looking
at.

- **Kinds became recipes.** The game had an enum of its own kinds. An engine cannot; the next game's
  kinds are different ones. What was shared was the shape of a kind, which is `ParticleRecipe`.
- **"Every eighth step" became a rate.** The game's continuous effects emitted on a step count, which
  ties their density to the fixed timestep. `ParticleEmitter` carries the fraction owed between steps,
  so twelve a second is twelve a second at any step size — tested at 30, 60, 120 and 240 Hz.
- **The spread's randomness was quantised, and nobody could see it.** It used `fract(sin(x) ×
  43758.5453)`, the shader one-liner, in 32-bit floats. Measured: **300,000 draws gave 8,923 distinct
  values** — about thirteen bits. It is now an integer hash: 297,320 distinct in the same draws, which
  is what a perfect 24-bit output does.

### Light and matter, one pipeline

A spark makes light; dust covers what is behind it. **Premultiplied alpha serves both**: matter writes
its opacity as coverage, light writes zero, and the same blend becomes an add. One pipeline, one draw,
no sort between two kinds.

### Dust is an albedo, and needs lighting — found in the sample

The first landing threw a 0.5-grey dust cloud onto ground in shadow, and it came out as **a white
glow several times brighter than the floor**. A particle's colour is radiance for a spark and albedo
for dust; drawn as radiance, grey dust is a grey lamp. Dust is now lit by the sky's mean radiance plus
the sun's irradiance over 4π — the isotropic answer, computed once per level, unshadowed.

### Also found in the sample

A crate's burst was thrown from 1.2 m, inside a crate 1.5 m tall, so depth hid half of it. Now thrown
from above the lid.

### Verified in the running sample

Embers seen rising off the brazier and a lantern; a scripted walk collecting a crate shows the burst
spreading above it with the crate's lid hiding the ones behind; the landing dust reads as a dim tan
puff after the lighting fix, where it was a white blob before it.

## [0.6.6] — 2026-09-10

**A body with feet.** `CharacterController` walks, stands on things, steps up, falls off, jumps,
crouches and slides. The sample walks on it instead of pinning the camera to one height.

### Added

- **`CharacterController`**, with `Surroundings` (terrain plus solid boxes) and `Tuning`.
- **`InputState.isJumpHeld`** — Space, or Cross on a pad.

### Changed

- **`Camera`'s documentation**: it is an eye, not a body. `advance(_:deltaTime:)` still flies, which
  is right for a photo mode or an editor; a game with feet moves a `CharacterController` instead.
  No code change.

### Extracted, then finished

The walking half is not new. A game on this engine has shipped it for a while — movement along the
ground plane rather than the look direction, a crouch that costs speed, a slide that carries a
sprint into it, an eye that settles over rough ground — and its numbers came across tuned, with their
reasons. **What it lacked was anything to stand on but a height function**, so it had no gravity, no
step height and no obstacles. The sample's crates and steps are what showed the seam: the ground is a
question the controller asks, which is `Surroundings`.

### Decisions

- **The body is a box.** Against a world of axis-aligned boxes that is exact — no contact normals,
  nothing to resolve. A capsule glances off corners where a box catches; moving one axis at a time
  takes most of that back.
- **The feet move at once; the eye follows.** Collision is resolved against the feet, exactly. Every
  change in the height under a grounded player — a step, a kerb, the next bump of a terrain — is eased
  into the eye over a moment. That is what makes stairs read as stairs. A fall is never eased.
- **Step height 0.45 m, jump about a metre.** A stair and a low plinth are walked up; a crate is not,
  and cannot be jumped onto. A crate you could walk onto would not be cover.
- **Gravity 20 m/s², about twice real.** At 9.8 a fall reads as floating: a first-person camera has
  no body in view to give the drop a scale.
- **Coyote time and a jump buffer**, a tenth of a second each, so a jump on the last frame of a ledge
  or just before landing is not eaten.
- **No jump out of a slide.** A slide is committed, and a jump from sprint speed is exactly the
  movement tech its tuning forbids.

### What the sample found

**A blocked step stopped the player where the last whole step ended.** The first in-app run had the
player halt 4 cm short of a crate at a walk; the arithmetic says 15 cm at a sprint, a gap visible when
you turn to look. A blocked axis now moves to the face. The test for it fails without the fix.

### Verified in the running sample

The sample gained `WINDAGE_SAMPLE_WALK`, a short scripted walk that replays keys and logs where the
feet end each segment. On the ruins: up four 30 cm steps to **1.20 m**; off the end, in the air, down
to **0.00**; a jump peaking at **0.97 m**; stopped at the crate's face, **z −12.95** against a face at
−13.25 less the 0.3 m radius, at a walk and at a sprint; a jump into the crate does not get onto it.

## [0.6.5] — 2026-09-10

**Things that hang off other things.** `TransformHierarchy` is parenting — one transform expressed
relative to another, resolved in the right order — and the sample's figures now carry lanterns.

### Added

- **`TransformHierarchy`** — attachments, local transforms, and one forward pass to world transforms.
  Parent-first is checked at construction, as in `Skeleton`.
- **`matrix_without_scale(_:)`**.

### It is parenting, and deliberately not a scene graph

A scene graph is an *object model*: nodes that own children and components, are looked up by name,
and become the unit everything else is written against. That decision is in the README's contested
list and stays there. **What a game runs into first is much smaller**, and this is that: a list of
attachments and a list of matrices, owning no objects at all, so the same hierarchy can drive a
drawable, a light and a collision volume without knowing any of them exist.

### The interesting case is the one that reaches outside

A rig is already a hierarchy and `SkeletonPose` already resolves it. What it cannot do is reach
*out* — and the canonical attachment, a weapon in a hand, is exactly that: **the parent is a joint,
inside a pose, that is itself placed by an object's world transform.**

`Attachment.external(_:)` makes that first-class. The node's own local transform stays what it should
be — the grip, authored once — instead of being rewritten every frame by a caller who then has to
keep the grip somewhere else anyway. How many external transforms will arrive is declared up front,
so an out-of-range attachment is a load-time error rather than an identity substituted at sixty hertz.

### Scale is inherited, and that is wrong for a held object

**A rig authored in centimetres hands its wrist a hundredfold scale.** It belongs to the arm — the
forearm genuinely is fifty units long in that space — and it is exactly wrong for something merely
hung there: the lantern comes out at one percent of its size, in a position that is otherwise
correct, which reads as the wrong mesh rather than as the wrong space.

`matrix_without_scale` at the call site, rather than a "do not inherit scale" flag inside the
hierarchy, because it is a decision about *what is being attached* and only the caller can see that.

### A joint's frame is not a promise about where the mesh got drawn

The bind pose puts the sample figure's forearm joint 48 cm along the arm and the mesh reaches 74, so
26 cm along the joint's +X reads as "the hand" — and with the arm down it is exactly that. **Raised,
it is not**: the drawn limb stops a hand's length short of where that arithmetic says the hand went.

That gap is the asset's business rather than the engine's, and the useful form of it is a warning: a
grip derived from bind-pose arithmetic is a guess. It is a number set by looking, which is what an
attachment point in a tool is for.

### What it found in 0.6.4

**The sample assigned shadow cubes once, at level load.** Correct for lamps that do not move, and the
first lamp that did move exposed it — a cube recorded from where the lamp *was* is a shadow that lags
the hand. Now assigned every frame, which is a sort of five elements.

### Measured

Two frames of the same figure, one waving and one not: the lantern is at the end of the outstretched
arm in one and raised with it in the other. The lantern lights change **24.5% of the frame**, and
their own cube shadows — the figure's body blocking the lamp in its own hand — a further **4.7%**.

## [0.6.4] — 2026-09-10

**Point lights cast now.** Every lamp in the sample stops at a wall, aimed or not, which finishes what
0.6.3 started and left costed.

### Added

- **`ShadowCubes`** — a cube-array depth texture, the six face matrices, and the pass that records
  them. Six render passes per light, with two culls that take most of that back.
- **`ShadowMap.Batch.bounds`** — an optional world-space box per drawable. Additive and defaulted to
  `nil`, so existing batches compile and behave exactly as before.
- **`BoundingBox.expanded(by:)`**.

### A cube array, not tiles of the atlas — which is not what 0.6.3 said it would be

The atlas's own note said the missing feature was "cube tiles in the atlas, six passes per light, and
a shader that picks a face before it picks a tile". Two thirds of that survived the work. **The tiles
did not**, for two reasons that only appear once the shader is written.

**The face maths has to agree with six matrices, exactly.** Picking a face by hand means reproducing
the cube convention — which axis becomes *u*, which becomes *v*, which of the six sign flips applies —
in a shader, and matching it against six matrices built on the CPU. Every one of those is a place for
a face to come out rotated or mirrored, and what that produces is a *plausible* shadow in the wrong
direction.

**And a filter kernel cannot cross a tile edge.** A tap that steps off the edge of a face does not
land on the next texel of that face; it lands on a different face at a right angle. Clamping draws a
bright seam down all twelve edges of the cube, and not clamping reads a neighbouring lamp's tile.

A `typeCubeArray` texture hands both to the hardware: the sampler takes a **direction**, picks the
face itself, filters across the seams itself, and compares itself. What is left on this side is the
six view matrices — and those are pinned against the same convention in the tests.

### The bias is in metres, not in depth

A cube face stores `near / distance`, so a constant added to that depth is **a third of a millimetre
at one metre and most of a metre at ten**. A bias tuned to remove acne beside the lamp deletes contact
shadows across the room. Taken off the *distance* instead — scaled by the face's own texel size — it
is one number at every range.

### Six passes, and what the culls give back

**A caster outside the light's range is skipped for all six faces; one outside a face's `Frustum` is
skipped for that face.** In the sample's ruins, two casting point lights across 32 drawables:
**35 objects recorded against 384 unculled**. Thirty-two drawables is what one unculled pass costs, so
all twelve passes together came to barely more than one of them.

`Frustum` has been in the package since 0.4 and had no consumer inside this repository until now.

### Two smaller ones

- **`right × up == forward` for a cube face, which looks like the wrong handedness and is not.** A
  cube is sampled from the inside, so its faces are mirrored relative to a camera looking out. The
  same relation already held for the spot's view and for the cascades, so the winding — and the
  front-face cull — is unchanged in all three.
- **The near plane travels with the light** rather than sitting in a shader constant, because it is
  what the shader's reference depth is made of.

### Verified twice

The six matrices are checked against the sampler's own rule on the CPU: for a spread of directions,
the face the rule picks and the *uv* it gives have to be where that face's matrix actually lands the
point. That is the half a screenshot cannot show — a mirrored face still casts a shadow.

The other half was a difference: the same frame with the per-light cube flag on and off changed
**1.77% of it**, all of it around the two braziers.

## [0.6.3] — 2026-09-10

**Shadows for the lamps.** A spot light casts now, so a wall stops it — which it had not, and which
was the reason the sample's ranges were kept short.

### Added

- **`ShadowAtlas`** — one depth texture cut into tiles, a spot's view-projection, and the pass that
  records every caster into its own tile.

### An atlas rather than a texture each

A texture per light is an allocation and a residency entry appearing and disappearing as levels load,
a render pass each, and a shader indexing an array of textures. One texture cut into tiles is a fixed
allocation, **one render pass for every light** — the viewport moves between them — and a single
binding sampled with an offset.

**Scissored as well as viewported**, which is not redundant: a viewport limits where geometry lands
and does *not* stop a clear or a wide triangle touching a neighbour's tile. One lamp bleeding into
another's map is a shadow that appears in the wrong room.

### Spot lights only, and the cost of the rest is written down

A spot's shadow map is one perspective render, the same shape as a cascade and sharing its pipeline.
**A point light needs six** — a cube, one face per direction — so shadowing every lamp costs six times
what shadowing the aimed ones does. `viewProjection(for:)` returns **nil** for a light with no cone
rather than silently shadowing one direction of six.

### Four smaller ones

- **The field of view is the cone's outer angle doubled** (and a little more), so the map covers what
  the light reaches — no less, which cuts the shadow off inside the lit circle, and no more, which
  spends resolution on nothing.
- **A lamp pointing straight down is the common case and exactly where a fixed up vector is
  degenerate.** The cross product is zero, the basis becomes `NaN`, and nothing draws.
- **The shader's constant bias is positive where the rasteriser's is negative.** They are different
  quantities in different spaces — one is normalised light depth, the other a rasteriser offset — and
  reversed-Z inverts the sign of only one of them.
- **Tiles go to the brightest, longest-reaching lamps.** A light nobody can see casting a shadow
  nobody can see is the tile to give away first.

### Verified by difference, not by looking

A spot shadow on open ground is subtle enough that "looks about right" is not verification. The same
frame was rendered with the per-light shadow flag on and off: **1.2% of the frame changed**, confined
to the lit ground. That is what said the atlas was working before any effort went into finding a
camera angle that showed it off.

## [0.6.2] — 2026-09-10

**Clustered shading.** A fragment asks which lights reach *it*, instead of inheriting a list chosen
for the whole mesh it belongs to.

> **A large addition on a patch number**, which is the versioning rule working as intended: the number
> tracks compatibility, not significance. Nothing that compiled against 0.6.1 changes.

### The problem it fixes, which 0.6.1 found and could not solve

`LightSet` picks a few lights per object — correct, cheap, and **only as good as the draws are
small**. The sample's ground is one eight-hundred-metre quad, so a single draw got four lights for an
entire level and a spot five metres up lost to lamps standing closer to the plane. No budget and no
ordering rule fixes that; the object is simply the wrong unit to choose lights for.

A cluster is the right unit: a small box of the world, so the lights reaching it are few by
construction, and a fragment belongs to exactly one.

### Added

- **`ClusterGrid`** — the frustum cut into tiles and depth slices, with the slicing a shader needs as
  two constants and a logarithm.
- **`ClusteredLights`** — bins lights into the clusters they reach, as the two arrays a shader reads.

### Three decisions worth the words

- **Slices are exponential.** Cut the depth evenly and the near slices are microscopic while the far
  ones are hundreds of metres deep — a perspective frustum's cross-section grows with distance, so an
  even cut puts almost every cluster where there is almost no screen. Slicing by the logarithm makes
  each cluster roughly cubic.
- **Clustering needs a finite far and this engine's projection has none.** The infinite far plane is
  deliberate — no view distance to tune, nothing to clip at range — so `ClusterGrid` carries its own
  `lightRange`. Honest rather than awkward: a punctual light has a finite range by definition, so
  there is a distance past which none of them reaches.
- **An offset and a count per cluster, not a fixed list.** A fixed list means every cluster pays for
  the worst one — three thousand cells times a budget of eight is twenty-four thousand entries, nearly
  all empty. A range into a shared list costs an empty cluster nothing and puts no ceiling on a full
  one.

### Measured

Sixty-four lights in a test scene: **busiest cluster 9, average 2.2**. The sample's ruins: ten lights,
**busiest 6**. That ratio is the whole point — the worst fragment loops nine times instead of
sixty-four, and the typical one twice.

### The bug that made it render as nothing at all

The first working version drew **no local light whatsoever**, with the CPU side provably correct: six
lights, 222 cluster entries, 173 cells occupied.

**A `SIMD3<Float>` used as padding has 16-byte alignment in Swift; the shader's three trailing scalars
have four.** The struct came out 48 bytes on one side and 32 on the other, so every field after it in
the frame uniforms was read from the wrong address. It compiled, it ran, and it looked exactly like a
feature that had not been wired up.

There is a test pinning the layout now — size, stride *and* alignment — because a struct that agrees
on its fields and disagrees on its padding is the worst kind of mismatch.

## [0.6.1] — 2026-09-10

**Spot lights** — a cone, for the lamps that are aimed.

### Added

- **`PunctualLight.Cone`** — a direction and two angles: full brightness within the inner, nothing
  beyond the outer, smooth between. **Two angles rather than one**, because a single cutoff gives a
  hard-edged circle that reads as a stencil rather than as a lamp.
- **`PunctualLight.angularAttenuation(at:)`** and **`.radialAttenuation(at:)`**, the second being
  distance alone.
- Levels write a cone by naming a `direction` and angles **in degrees**, like the sky's. No direction
  means no cone, so every lamp already written stays a point light.

### A point light is a spot with no cone, and the shader does not branch

Its `angleScale` is 0 and its `angleOffset` is 1, which makes the angular term evaluate to exactly 1
everywhere — from the same two multiplies. One code path, no branch, and nothing that behaves
differently depending on which kind of lamp a level happens to hold.

### A cone cannot be tested at one point, and the error has a direction

The nearest point of a box gives the best *distance*, and for a point light that settles which lights
reach it. For a spot it does not: **the nearest corner of a wall can be outside the cone while the far
end of the same wall is brightly lit.** Testing that one point drops the light and the lit end goes
dark.

**A false positive costs one iteration of a shader loop; a false negative deletes light the player can
see.** Those are not comparable — the same asymmetry `Frustum` is built around — so the cone is tested
against the box's bounding **sphere**, which can say yes when the answer was no and never the reverse.
Ranking is by distance alone for the same reason.

### And a finding that was not about spot lights at all

The sample's new spot lit nothing, and over-subscription was not why — `isOverSubscribed` reported the
level clean at every point a player stands. **The cause is that the ground is one 800-metre quad.**
Per-draw selection gives it four lights for the entire level, so the objective lamps standing 0.6 m
above it beat a spot 5 m up, and the spot never reaches the shader.

**Per-draw light selection is only as good as the draws are small**, and no budget or ordering rule
fixes an oversized one — that is what clustered and tiled shading exist for. The sample aims its spot
at a pillar instead, which is a normal-sized draw, and the limitation is written down rather than
tuned around.

### Also

The sample **reports over-subscription at load**, sweeping the points a player actually goes. A
condition nobody checks is a condition nobody meets.

## [0.6.0] — 2026-09-10

**Lights that are not the sun.** A directional sun and an environment map light an outdoor scene
correctly and have no answer at all for an interior — the sun does not reach inside, and a
sky-coloured ambient lights a cellar as though the sky were overhead.

**Extracted from a probe built to ask exactly this**, and stripped of the game that asked it.

### Added

- **`PunctualLight`** — a position, a radiant intensity, a range, and a physical windowed
  inverse-square falloff.
- **`LightSet`** — a budget and the rule for choosing which lights fill it, plus
  `isOverSubscribed(at:)`.
- **`Level.lights`**, a named list in the level format.
- **`BoundingBox.closestPoint(to:)`**.

### Changed

- **`Level` decodes explicitly and tolerantly now.** Every field but the version is optional, because
  the synthesised decoder throws on a missing key — so adding `lights` would have refused every level
  already written, including any a player edited into Application Support.

### What the probe had wrong

It ranked lights by **falloff alone**, ignoring how bright they are — so a candle at one metre
outranked a floodlight at ten, and the floodlight was the one dropped. Influence is weighted by
luminance now, which costs a dot product and makes the ordering mean what it claims.

### What the probe had right, and it is the important part

**A hard budget cannot promise a smooth hand-over in an arbitrary level.** If five lights all
contribute at a point, one is dropped, and how visible that is depends entirely on how the level was
built. Ordering by influence does not save it and a bigger budget only moves the number.

So the promise is conditional: **where no more than the budget are above `negligible`, nothing the
player can see is ever dropped** — and `isOverSubscribed(at:)` is what makes that checkable before a
corridor ships with a flicker in it.

### Four smaller ones

- **Selection is per draw and uses the box's nearest point, not its centre.** A long wall whose middle
  is out of a lamp's reach still has an end inside it.
- **The falloff needs a floor.** A fragment exactly at a lamp's position is a division by zero, and
  the pixel that produces is not "very bright" — it is `NaN`, which draws black.
- **Local lights cast no shadows.** There is one shadow map and the sun has it, so a lamp reaches
  through a wall. That is why the sample's ranges are short: it is only obvious when a lamp reaches
  far enough for it to be.
- **A lamp in daylight does almost nothing**, which is correct and is why the sunlit level has none.
  Its local lighting is the objectives, which are dynamic — so between the two levels both paths are
  exercised: lamps from the file, and lights the game owns.

## [0.5.2] — 2026-09-10

**Emission** — the last material slot with nothing reading it. Every slot `Material` carries now
reaches a pixel.

### Fixed

- **The identity-scalar rule extended to emission.** Third instance of the same trap: a file that
  connects `emissiveColor` to a texture supplies no scalar, so the field kept `Material`'s default of
  zero and multiplied the map away. **Three slots needed this for the same reason** — base colour, the
  metallic-roughness pair, and emission — which is what makes it a rule rather than three fixes.

### Added

- **The sample's figure has glowing seams**, from an emissive map in its USD material.
- **Objectives emit instead of swapping colour.** An uncollected crate is lit from within and a
  collected one is not. It used to change its albedo, which is a colour a surface *is* — so the two
  states differed the way two paints differ.

### What OBJ carries, measured

**Nothing.** `Ke` and `map_Ke` are both read and discarded; the emission property comes back as an
always-black `.color` regardless of the file. Emission joins metalness and roughness maps as USD-only.
(`map_Ka` does arrive as an emission *texture* — the ambient map mapped onto the emission semantic,
which is a legacy quirk rather than a path worth relying on.)

### Three things about emission itself

- **It is added, not lit.** Nothing multiplies it: not the sun's angle, not the shadow map, not the
  ambient occlusion. A glowing seam that dimmed when a shadow crossed it would be a lamp that goes
  out when you stand in front of it.
- **A whole object that emits looks flat**, and correctly so — an emitting surface has no light
  direction. Real emissive surfaces are a strip or a panel, confined by a *map*, which is exactly
  what an OBJ crate cannot have. So the sample's crates glow gently enough that the planks and the
  sun still carry their shape.
- **A PNG cannot hold a value above 1**, so an emissive map alone is never brighter than white — and
  a seam that is exactly white does not read as lit. How much brighter is a look decision, so it is
  the game's multiplier rather than the texture's.

### And one about who owns the value

**The game's emission is authoritative, not the material's times the game's.** Multiplying them was
the first attempt and it silently produced nothing: an OBJ material's emission is always zero, so a
crate the game wanted lit was zero times whatever it asked for. The material's emission is a
*default* the caller may use, override or ignore — because only the caller knows whether this surface
is powered right now.

## [0.5.1] — 2026-09-10

**Occlusion, roughness and metalness from a texture**, which were the last material slots with
nothing behind them.

### Fixed

- **A slot with a map now takes the identity scalar.** *The 0.18 trap in a second place, and it was
  nearly shipped.* A file that connects `metallic` to a texture supplies **no scalar at all**, so the
  field kept whatever `Material` initialises it to — and `metallic` initialises to 0. Multiplied by
  the map, that is zero everywhere: a metal character renders as a dielectric one with nothing to say
  why. Mapped slots take 1, which is the identity for a multiplied factor.

### Added

- **`TextureSlot.packedChannel`** — which channel of its texture a slot reads: **R occlusion, G
  roughness, B metalness**, glTF's packing.
- **The sample's figure carries a packed ORM map**, and its shader multiplies the three through.

### What Model I/O does and does not carry, measured

- **USD carries all four**: metalness, roughness, occlusion and emissive arrive as textures on the
  right semantics.
- **It drops which channel each reads.** A `UsdPreviewSurface` with roughness connected to a texture's
  `.g` and metalness to its `.b` arrives as two properties naming the same file, with nothing to
  distinguish them. The convention has to be assumed, which is what `packedChannel` writes down.
  **It is also right for an unpacked map** — a standalone roughness map is greyscale, so its green
  channel is its value, and that is why glTF fixed a convention at all.
- **OBJ carries none of it.** `map_Pr` and `map_Pm` are read and discarded, like the scalars before
  them. What *does* arrive is `map_Ns` as a **`specularExponent` texture** and `map_Ka` as emission —
  so an OBJ can vary shininess spatially, in exponents rather than roughness. Not wired up: it is a
  differently shaped quantity needing its own conversion, and nothing needs it.

### Two decisions in the shader

- **White is exactly the right fallback**, because the three are multiplied: a surface with no map
  keeps its material's own values untouched.
- **Occlusion applies to the ambient terms only.** It stands for light a crevice does not receive from
  its surroundings; applying it to the sun as well would darken a surface the sun is plainly shining
  into, which is a shadow the shadow map already has an opinion about.

## [0.5.0] — 2026-09-10

**A level says what sky it is under.** It said where the sun was — two entries in `settings` — and
everything else about the light was hard-coded in the game, so two levels could differ in the sun's
angle and in nothing else.

**Behaviour change**: `ProceduralSky`'s default `sunRadiance` is now a physically coherent figure
rather than the hand-picked one it started with. See below.

### Added

- **`Level.sky`** — an optional `ProceduralSky`, encoded as a named block rather than more scalars.
  A sky is three colours, two angles and a sun size; flattened into `[String: Double]` that is
  fifteen keys with no structure and nothing to stop `skyZenithB` being set and `skyZenithG`
  forgotten.
- **`Level.resolvedSky`** — the sky to light a level with, whatever the file did or did not say.
- **`ProceduralSky` is `Codable`**, written as **angles and colour triples with every key optional**.
  A level file is edited by hand as often as by a tool, so a sky naming only `sunPitch` has to be
  legal — otherwise the simplest edit is the longest one.
- **`ProceduralSky.sunIrradiance`**, **`.sunPitchDegrees`**, **`.sunYawDegrees`**,
  **`ProceduralSky.direction(pitchDegrees:yawDegrees:)`**, and **`radians_to_degrees`**.

### Radiance is not irradiance, and they differ by about 130×

**The one that would have been a silent disaster.** `sunRadiance` is how bright the disc *is*, looked
at. What a surface receives is that times the solid angle the disc subtends — and a 0.05 radian disc
subtends 0.0079 steradians. Use the radiance as a directional light's intensity and the scene is a
hundred and thirty times too bright.

Deriving one from the other is what stops the sun you *see* and the sun that *lights the scene* being
two numbers that can disagree, and it makes a physically true thing fall out for nothing: **a wider
sun is both softer and stronger**, because it is more sky.

The default `sunRadiance` moved from 28 to 330 as a consequence — the old figure was chosen to look
right in a reflection, before anything derived a light from it.

### Migration, in the engine rather than in each game

Levels already exist on disk saying `sunPitch` and `sunYaw` in `settings` — including any a player
edited and saved, which live in Application Support and cannot be rewritten from here. `resolvedSky`
reads them when there is no `sky` block. Doing it in `Level` is the difference between one migration
and one per consumer.

### Two things found doing it

- **Overcast is dimmer, not just a dimmer sun.** The first attempt kept a bright sky and only dimmed
  the sun, which lit everything flatly and washed the stone out to near-white. An overcast scene is
  darker *and* flatter.
- **Adding a stored property to `Level` segfaulted a test in another target.** Not a crash in the new
  code: `WindageSampleCore` was still linked against the old struct layout, so a decoded `Level` read
  a garbage array. `swift test` reported a `signal code 11` with no summary and the crash log pointed
  at an unrelated assertion. **Delete the build directory when a shared type gains a field.**

## [0.4.1] — 2026-09-10

**Image-based lighting.** A surface takes light from its whole environment, and how it takes it
depends on how rough it is — a mirror reflects one direction, chalk gathers the hemisphere. Both are
precomputed now, so a metal object reflects its surroundings instead of a gradient.

### Added

- **`ProceduralSky`** — a sky as a function of direction: gradient, horizon, ground bounce and a sun
  disc, in radiance rather than colour.
- **`EnvironmentMap`** — that environment convolved twice: `specular`, a cube whose mips are the GGX
  lobe at increasing roughness, and `irradiance`, a small cube convolved with a cosine lobe.
- **The sample draws its sky from the same cube it reflects**, and shades with both.

### Built on the CPU, deliberately

Every part of this that can be *wrong* is arithmetic — cube face projection, importance sampling, two
convolutions — and this repository's rule is that such halves want tests and tests should not want a
GPU. A compute prefilter would be faster and would put all of it somewhere only a screenshot could
check.

**Cost: 92 ms in a release build, 2.6 s in a debug one.** The debug figure is what somebody running
`swift run WindageSample` sees, and it is the honest price of doing this in Swift on the CPU. It
prefilters a *function*, not a photograph; an engine wanting to prefilter a captured HDR panorama
will want the compute version, and this maths is what that would be written against.

### Three things the tests found

- **Fireflies at high roughness.** At a fixed 96 samples the chain stops getting blurrier around
  roughness 0.6 and starts getting *brighter* — 0.72 rising to 1.67 at roughness 1.0, where the truth
  falls to 0.60. A wide lobe over a small, very bright sun means the estimate is decided by whether a
  sample happened to land on the sun. **Fixed by quadrupling the sample count per mip, which is
  free**: each level has a quarter of the texels, so the cost per level is flat and the roughest mips
  — which need it most — are the cheapest place to spend it.
- **The irradiance integral was out by a factor of π.** It is a Riemann sum over dφ dθ, so each term
  is worth `step²` of measure; dividing by the sample count gives an *average* instead. Caught by
  asserting that a uniform sky of radiance L integrates to πL.
- **The lower hemisphere must not be black.** A surface facing down is lit by the ground, and a black
  ground is the commonest reason an image-based lit object looks like it is floating in a void.

### And one in the shader

**Irradiance is not radiance.** The cube holds light integrated over the hemisphere; Lambert's BRDF
is `albedo / π`, and skipping the division makes every ambient-lit surface π times too bright.

## [0.4.0] — 2026-09-10

**A microfacet specular, and the material data to drive it.** The sample's shading was Lambert plus a
Blinn-Phong lobe; it is Cook-Torrance with a GGX distribution now, which is what makes metal look
like metal rather than like plastic with a bright spot on it.

**Behaviour change**: an OBJ material's `roughness` is now derived from its specular exponent instead
of being Model I/O's invented 0.9.

### Fixed

- **`Material` derives roughness from `specularExponent` when a file supplies one.** Measured across
  five materials: Model I/O's OBJ reader returns roughness 0.9 and metallic 0.0 **whatever the file
  says** — `Ns`, and the `Pr`/`Pm` PBR extensions alike. The specular exponent is the only shininess
  an OBJ carries through, and it does arrive.

### Added

- **`Material.specularExponent`** and **`Material.roughness(fromSpecularExponent:)`**. Its presence is
  a reliable tell for a Blinn-Phong material: a USD `UsdPreviewSurface` carries real roughness and
  metallic and no exponent at all.
- **The sample shades with GGX** — Smith height-correlated visibility, Schlick Fresnel, Karis's
  analytic environment BRDF, and a two-colour analytic sky standing in for an environment map. Its
  figure is metal, deliberately.

### Where the BRDF lives, and why it is not here

**In the sample.** The engine owns when things happen, the depth convention and the tone map; what a
surface *is* — its BRDF, its lighting model, how many lights it takes — is a game's, and no two games
will agree. **If a second consumer writes this same function, that is the moment to extract it** —
which is the lesson the shadow pass taught, applied forward rather than after the fact.

### Five things worth knowing

- **Metal with no environment is black.** A metal surface has no diffuse at all; its entire appearance
  is what it reflects. With only a sun in the scene it is black except for one small highlight, so
  something has to stand in for an environment — here, a two-colour sky gradient and a `mix`.
- **`alpha` is roughness squared, and the squaring is not decorative.** Roughness is authored
  *perceptually* so a slider steps evenly; the distribution wants the physical quantity, and feeding
  it the perceptual value bunches all the useful range into the first third.
- **Fold `1 / (4 NdotL NdotV)` into the visibility term.** Written separately, both it and the
  geometry term vanish at grazing angles and the division is a ratio of two vanishing numbers — a
  bright rim of fireflies along every silhouette. Combined, the zeros cancel algebraically.
- **Roughness has to be clamped away from zero.** A perfectly smooth surface is a delta function:
  infinitely small, infinitely bright, and on screen a single crawling pixel.
- **`kD = 1 − F`.** What is not reflected is what is available to scatter. Skipping it makes a shiny
  surface brighter than the light falling on it, which is the usual way a first PBR shader breaks
  energy conservation.

### Still missing

A real prefiltered environment map. The analytic sky is enough for metal to read as metal and is not
enough for a metal object to reflect its surroundings.

## [0.3.0] — 2026-09-10

**The scene stops being written straight to the screen.** Shading does not stop at 1 — the sample's
own lit faces reach about 1.13 before anything shiny is involved — and every value above it was
clipping to the same white.

**Breaking**: a game's scene pipelines must declare `sceneColorPixelFormat`, not `colorPixelFormat`.

### Changed

- **`FrameRenderer` renders in two passes.** The scene draws into an HDR target
  (`sceneColorPixelFormat`, `rgba16Float`); a full-screen triangle then applies exposure and a curve
  and writes the drawable, with `GameLoop.encodeHUD` running in *that* pass so the interface never
  sees the curve. The ordering `encodeHUD` was designed around is now literally true.
- **`FrameRenderer.colorPixelFormat` still means the drawable** — what a view's layer is set to and
  what an interface pipeline draws into. Scene pipelines want the new one.
- **`clearColor` is radiance now**, not a screen colour: it is tone mapped like everything else.

### Added

- **`ToneMapping`** — a curve (`clamp`, `reinhard`, `aces`) and an exposure in stops.
  `FrameRenderer.toneMapping` is settable per frame. `apply(_:)` runs the curve on the CPU, which is
  what makes it testable and what a game needs to pick an interface colour that matches a scene.
- **The sample cycles curves with `m`**, so the difference can be looked at rather than argued about.

### Two things worth knowing

- **ACES lifts midtones by about a third** — middle grey 0.18 maps to 0.267. A scene tuned before
  there was a curve comes out *brighter* when one is switched on, not darker, and looks washed until
  its exposure is set. The sample sits at −0.5 stops for that reason.
- **Narkowicz's fit is not asymptotic**: it passes 1 at an input of about 6.6, so the clamp after it
  is doing real work rather than guarding an edge case.

### Not here

No auto-exposure — metering, what "correct" means for a game, and adaptation over time are contested,
and the game's needs decide them. No bloom, colour grading or vignette: those are a look, and this is
the part without which there is no picture.

## [0.2.1] — 2026-09-10

**Normal mapping**, which was the last of the material slots with nothing behind it.

### Added

- **`MeshLoader` generates a tangent basis** when the pipeline's semantics ask for
  `MDLVertexAttributeTangent` and the file did not supply one. A file that brings its own is left
  alone.
- **`MeshLoader.load(…, reportingTo:)`** — says when tangents could not be generated, which happens
  when a mesh has no normals or no texture coordinates. Neither can be invented.
- **The sample is normal mapped throughout**: crate, stone, ground and the figure, with maps derived
  from the same height fields that draw their colours so the two cannot drift.

### Four things worth knowing before writing a tangent basis

- **Model I/O's OBJ reader recognises only `bump`.** `map_Bump` — which is what Blender and Maya
  write — and `norm`, the modern PBR spelling, are both read and silently dropped: no property on the
  material, nothing logged. Measured against all five spellings.
- **Tangents must be generated *before* the vertex descriptor is applied.** Handing a descriptor to
  `MDLAsset(url:vertexDescriptor:bufferAllocator:)` converts the file to that layout immediately, and
  a tangent attribute the file lacks is filled with zeroes — a *degenerate* basis rather than a
  missing one, which normalises to NaN and deletes the triangle.
- **The tangent is a `float4` and `w` is handedness, ±1.** A UV island mirrored across the model —
  which is most of any character, whose halves share one texture — has its bitangent the other way
  round. Drop the sign and every mirrored surface is lit from the wrong side.
- **A tangent transforms by the model matrix, not the normal matrix.** It lies *along* the surface;
  the inverse transpose is for things perpendicular to one, and using it shears the tangent off the
  surface under non-uniform scale.

### And one about shadows

**The shadow lookup keeps the geometric normal.** Biasing a shadow sample along a *mapped* normal
moves it off the surface it belongs to, and the contact shadow detaches from its caster.

## [0.2.0] — 2026-09-09

**Every texture was upside down, and nothing could tell.** Metal puts texture coordinate (0, 0) at an
image's top-left; USD and OBJ put `st` (0, 0) at its bottom-left. Nothing reconciled them, so every
textured asset loaded flipped — invisibly, on anything roughly symmetrical, which is most textures.

**A minor bump rather than a patch**, because it changes what existing code does: a consumer's
textures will flip, correctly.

### Fixed

- **`TextureStore` loads with a bottom-left origin by default**, matching every format Model I/O
  reads — USD, USDZ, OBJ, PLY, STL, Alembic.

### Added

- **`TextureStore.TextureOrigin`** and an `origin:` parameter on `texture(_:isColor:origin:bundle:)`
  and `textures(for:origin:bundle:reportingTo:)`. `.topLeft` is there for glTF-derived UVs, which are
  the other way round, and for anything a game generates itself. The cache key includes it.

### How it was found, since it explains why it survived this long

The sample's crate, stone and ground textures had been flipped since the day they were added, and
looked entirely correct: noise and brickwork read the same upside down. It took a bought character
whose texture is a **palette** — a 32×32 grid of swatches with a magenta row along the bottom — for
the flip to stop softening an edge and start handing a limb the wrong colour. Compared against the
photograph the character tool produces, it was unmistakable.

The regression test uses a fixture that is red on top and blue on the bottom, for the same reason.

## [0.1.4] — 2026-09-09

**A real character was loaded into the sample rather than probed with a script**, and it found a gap
no fixture could: the engine could only load from its own bundle.

### Added

- **`MeshLoader.load(url:device:vertexDescriptor:semantics:)`**, **`RigLoader.load(url:)`**,
  **`RigLoader.load(url:clipURLs:reportingTo:)`** and **`RigLoader.clips(url:)`** — loading from a
  file anywhere on disk. The bundle calls delegate to these. A character in a pipeline's output
  folder, a mesh a level editor opens, a mod: all of them are a URL and none is a bundle resource.
- **The sample loads an external character** from `WINDAGE_SAMPLE_CHARACTER=/path/to/Name` — a path
  with no extension. It reads `<path>.usdc` for the rig and mesh, every `<path>_*.usdc` beside it as
  a clip, and `<path>_ColorMap.png` as the base colour.

### What running it confirmed

93 joints against a 128-joint palette, 39,360 vertices, four influences per vertex genuinely in use,
the node scale, clip-per-file loading, the clip files' wrong rest poses and the declared up axis — all
handled, by the fixtures built for them. What was **not** predicted: bundle-only loading. What was
predicted and confirmed: facing is per asset and is not in the file, and the material names no
texture because the tool builds its colour map in memory.

## [0.1.3] — 2026-09-09

**A correction, and the defect behind it.** 0.1.1 said a real character "arrives Z-up and in
centimetres", and treated the scale as something the file failed to record. That was wrong: the
conversion sits on a parent node, and **the loaders were ignoring node transforms entirely**.

### Fixed

- **`MeshLoader` and `RigLoader` now compose the file's node hierarchy.** They read a mesh's bounds
  and a skeleton's joints and never walked the nodes above them, so any asset with a parent transform
  loaded a hundred times too big — harmless for a hand-written OBJ at the origin, which was every
  asset this repository had until a real one arrived.
- **`SceneObject` composes the mesh's node transform** into its volume, so a placement means the same
  thing whatever the geometry came from.

### Added

- **`LoadedMesh.nodeTransform`** and **`Rig.nodeTransform`** — where the mesh or rig sits in the
  file's own hierarchy, composed from the root. Applied in front of the model matrix, like
  `AssetOrientation`, because skinning happens in model space.

### Changed

- **The sample's figure is written in centimetres under a node scaled by 0.01**, Y-up, which is the
  shape a real export actually has. It previously wrote hand-converted Z-up coordinates, on the same
  wrong diagnosis.

### Correcting 0.1.1

That entry's "Z-up" half stands — Blender's USD exporter writes Blender's convention unless told
otherwise, and `AssetOrientation` handles it. Its "in centimetres, and the file does not say so" half
does not: the file says so, on a node. **The probe that produced the wrong answer read
`MDLMesh.boundingBox` and stopped**, never asking what the mesh hung off.

## [0.1.2] — 2026-09-09

**The shadow pass stops being written twice.** The arithmetic has been here since `ShadowCascades`;
the pass — the texture, the depth state, the descriptors, the encoder loop — existed in two
repositories, where a fix to one did not reach the other. Additive: nothing that compiled against
0.1.1 changes.

### Added

- **`ShadowMap`** — the depth texture array and its per-cascade slices, the reversed-Z depth state,
  the front-face cull, the slope-scaled bias, the per-cascade pass descriptors, the light matrices
  per frame in flight, and the encoder loop.
- **`ShadowMap.Batch`** — a pipeline plus closures reaching each drawable's mesh, uniforms and
  optional joint palette. Batches rather than one loop because a skinned mesh has a different vertex
  layout, so pipeline state changes once per kind rather than once per object.
- **`ShadowMap.pipelineDescriptor(vertexFunction:vertexDescriptor:label:)`** — the three things a
  shadow pipeline must get right and none of which is obvious: no fragment function or colour
  attachment, one raster sample, and a depth format matching the texture.
- **`ShadowMap.BufferIndex`** — where the argument table puts the uniforms, the light matrix and the
  joint palette. A mismatch does not fail; it reads a matrix out of the wrong buffer and records the
  scene from nowhere.
- **`ShadowCascades.constantDepthBias`** and **`.slopeScaledDepthBias`**, beside `biasScales`,
  because the three numbers are one tuning. Both negative: under reversed-Z, pushing an occluder away
  from the light is a *smaller* value, so the sign is the opposite of every textbook.

### What a game keeps

The **pipelines** — compiled against its own shaders and vertex descriptor, so they cannot come from
here — the **uniform layout**, the joint palette, and the cascade **numbers**. A courtyard seventy
metres across and a range where the target is at 800 m want different splits.

A game with its own copy of the pass is not obliged to change. Replacing it is that game's work on
that game's schedule.

## [0.1.1] — 2026-09-09

**Everything a real character needs that a generated one did not show.** An 87-joint rigged character
from an actual toolchain was loaded, and it arrives in three shapes the engine had no answer for.
Additive: nothing that compiled against 0.1.0 changes.

### Added

- **`AssetOrientation`** — the up axis and unit scale an asset was authored in, and the one matrix
  that corrects it. A character out of a game-engine toolchain by way of Blender arrives **Z-up and
  in centimetres**; applied in front of the model matrix, one matrix corrects the mesh, the rig and
  the animation together, because skinning happens in model space.
- **`RigLoader.clips(named:withExtension:bundle:)`** — reads only the animations from a file.
- **`RigLoader.load(named:withExtension:clipFiles:bundle:reportingTo:)`** — a rig from one file and
  its animations from others, which is how a character exported one clip at a time arrives. A file
  holding one clip has it renamed to the file's own name. A clip that drives none of the rig's joints
  is dropped and reported; a clip file that is missing is reported, not thrown.
- **`Rig.adding(_:)`** and **`Rig.jointsNotDrivenBy(_:)`**.
- **`AnimationClip.renamed(to:)`** — for the names an exporter produces.

### Changed

- **The sample's figure is now written the way a real export arrives**: Z-up, a hundred units to the
  metre, and its second clip in a file of its own whose copy of the skeleton has the wrong rest pose.
  It renders identically to the Y-up metre version it replaced, which is the point. A sample that
  only ever loads tidy assets leaves the untidy path untested.

### Notes for anyone loading a real character

- **A clip file's skeleton is not the rig's skeleton.** Its rest pose is wherever the exporter left
  the rig — usually the clip's first frame. Measured: one joint reports (10.42, 4.08, 7.84) in the
  base file and (3.16, 1.17, 7.84) in the walk file. Merge them and every joint a clip does not
  animate stands in the wrong place, and the fault changes with which files were loaded.
- **Model I/O exposes `upAxis` and not `metersPerUnit`.** The axis can be read; the scale has to be
  measured once and written down.
- **Each per-clip export carries a whole copy of the mesh.** Model I/O offers no way to open an
  asset's animations alone, so the parse cost stays; what `clips(...)` avoids is the expensive half,
  since nothing is laid out or uploaded to a GPU without a vertex descriptor and an allocator.

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
