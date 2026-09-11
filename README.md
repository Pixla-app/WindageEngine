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

## How this engine gets built, and how everyone else builds one

**Nearly every engine worth using was extracted from a game, and kept a game attached.** This is not
a compromise or a stage to grow out of — it is the industry's normal shape, and the exceptions are
the cautionary tales.

| engine | the game that drove it |
|---|---|
| id Tech | a specific id title per generation — Doom, Quake, Doom 3, Rage. The engine was licensable *because* a game had shipped on it. |
| Unreal | written for *Unreal*; UE3 for *Gears of War*; UE4 and 5 developed alongside *Fortnite*, where features land before general release. |
| Source | Quake → Half-Life → Source, never without a game. |
| CryEngine · Frostbite · Decima · RE Engine | Far Cry · Battlefield · Killzone · Resident Evil 7. |
| Godot | extracted from commissioned games over roughly seven years before it was opened up. |
| Unity | **the outlier**: engine-first, from an abandoned game. Its long-standing reputation for being wide and shallow is the usual cost of having no single game holding it to account. |

**So "a game drives the engine" is the standard, and it is not the thing to avoid. Coupling is.**
Those are different, and the difference is the whole discipline here:

| | |
|---|---|
| **Driving** — correct, and how this works | A game is where you *discover* what the engine needs. The problem is found in real code, under real load, with a player looking at it. |
| **Coupling** — the failure | The engine references that game, needs it to build, ships its constants, or documents its product name. Then the engine is a component of one product and nobody else can own it. |

### What that means in practice here

1. **This repository never mentions a game.** It builds, runs and tests alone. A capability arrives
   stripped of where it came from — see the shadow cascades, whose splits were one game's sightline
   and are now a constructor argument.
2. **`WindageSample` is this engine's own game**, and it is the thing that proves an extraction. If a
   capability cannot be used by the sample through the public API, the API is wrong. It has caught a
   missing Metal compile, a buffered `print`, an ASCII-only font atlas and a depth bias that was
   secretly tied to one scene's scale.
3. **Probes cover shapes the sample is the wrong instrument for** — a scene that changes while it
   runs, geometry that mostly cannot be seen, light that is not one sun, ground that moves. A few
   hundred lines and their tests, never a game.
4. **A second sample arrives only when a capability needs a shape the first cannot express.** Skinned
   animation was expected to be the first real case — a courtyard of boxes cannot show a skeleton —
   and **it turned out not to be.** What the sample needed was a character *in* it, not a second
   sample around it; a generated rig standing in the courtyard exercised the whole animation API and
   kept one scene to maintain. **The bar is higher than it looked**, and "more demos" still does not
   meet it.

### The game does **not** have to contain everything the engine can do

**This is the inference to avoid, because it is the expensive one.** "A game drives the engine" does
not mean the game must exercise every capability before the engine may have it. Fortnite does not
touch most of Unreal. Half-Life 2 did not use everything in Source. A driving game is a *source of
real problems*, not a specification.

Capabilities arrive from three places, and only the first needs a game:

| where it comes from | example | the test it must pass |
|---|---|---|
| **A game hit the problem** | shadow cascades, the level format, the one hit test | working, tested code proves the seam — then it is extracted and stripped of that game |
| **Every game of this kind needs it, and its shape is settled** | skinned animation, audio, input, mesh loading | the shape is an industry standard, not a guess; the sample proves it is usable |
| **Nobody has needed it yet** | scene graph, ECS, material system, editor application | *do not build it* |

The second row is the one that answers "how do I build the engine when no game is pushing on it".
Most of what an engine owes a game is in it. It is not speculative work: nobody has to discover what
a skeleton or a joint palette is, and a game cannot teach you a better answer than the one the whole
industry already uses. What a game *would* teach you is a material system's shape, which is exactly
why that one is in the third row.

### When engine-first is legitimate — three buckets, not one rule

**An earlier version of this document said "nothing is built until a game needs it", and that rule is
wrong on its own.** It is circular while an engine is small: nobody needs what nobody can use, so
"wait for demand" is a rule that keeps an engine at 3,000 lines for ever. The rule it was reaching
for is narrower, and there are three cases rather than one:

| bucket | what it means | what to do |
|---|---|---|
| **Settled shape** | Everybody's version looks the same because the problem has one good answer. A skeleton, a joint palette, a particle emitter, a shadow pass, a tone-map curve, a rebindable input map. | **Build it on a roadmap.** No game has to ask first — a game could not teach you a better answer than the one the whole industry already uses. The sample proves it works. |
| **Contested architecture** | Reasonable engines disagree, and one game's needs would decide it wrongly for everybody. Whether objects live in a node tree or an ECS; how scripting attaches; how a scene is serialised. | **Defer.** Not for ever — until either a real need forces it, or you deliberately pick a side and write down why. |
| **Enormous cost** | Correct, wanted, and measured in person-years. A standalone editor application, a second platform backend, a physics solver, networking. | **A business decision, not an engineering one.** Decide it explicitly, with the cost stated. |

Only the middle bucket waits on a game. The first is most of what an engine owes anybody, and it is
where a roadmap belongs.

## Where this engine actually stands

**About 3,800 lines.** Godot is roughly a million; Unreal several. That comparison is only useful for
one thing: **this cannot become a general-purpose engine, and any plan that assumes it will is a plan
to never ship anything.**

Measured against something narrower and reachable — *what a native macOS first- or third-person game
needs to ship* — the picture is a real product with real gaps.

### Present

Frame pacing and frames in flight · fixed timestep · reversed-Z depth · camera · keyboard, mouse and
gamepad input with stick shaping · mesh loading through Model I/O · **skinned animation — skeletons,
clips, cross-fading and a joint palette, loaded from USD, with clips in files of their own and an
asset-orientation correction for Z-up centimetre exports** · **materials and textures — the
metallic-roughness set read from a file, and a caching texture store that knows colour from
numbers** · maths · bounding boxes, volumes
and one segment hit test · frustum culling · **a transform hierarchy, so a thing can hang off a joint
or off another thing** · **a character controller — feet, steps, gravity, jump, crouch and slide** · **particles** ·
**rebindable keys and controller buttons, and saved player settings** · **footsteps and landings** ·
**cascaded shadows, arithmetic and pass** · **an HDR
scene target with exposure and tone mapping** · **a prefiltered environment for image-based
lighting** · **punctual, spot and point lights, binned into a cluster grid, with a shadow atlas and
shadow cubes** ·
a versioned level format
with an editor · a HUD renderer with a font atlas · positional audio · save persistence · a shader
library that survives having no Xcode · and a complete sample game exercising all of it.

### Missing, and the order it is worth building in

**Settled shape — build these; no game has to ask.**

| | why it is next, or not |
|---|---|
| ~~**Skinned animation**~~ | **Done 2026-09-09.** `Skeleton`, `AnimationClip`, `SkeletonPose` and `RigLoader`; the sample's figures are posed, cross-faded and shadowed. See below. |
| ~~**A transform hierarchy**~~ | **Done 2026-09-10.** `TransformHierarchy` — attachments, one forward pass, parent-first checked; and `Attachment.external` for the case that reaches outside, which is a weapon on a hand. The sample's figures carry lanterns. See below. |
| **Animation state** | What plays next, and what interrupts what. The engine cross-fades two clips; deciding *which two* is a game's job today, and there is no evidence yet about where the line sits. Wait for a game to have more than two clips. |
| ~~**The shadow pass**~~ | **Done 2026-09-09.** `ShadowMap` owns the texture, the depth state, the descriptors and the encoder loop; the game keeps its pipelines. See below. |
| ~~**Materials and a texture path**~~ | **Done 2026-09-09.** `Material`, `TextureSlot`, `TextureStore`; `MeshLoader` returns a material per submesh, and the sample textures every surface from the file that names it. See below. |
| ~~**Normal maps**~~ | **Done 2026-09-10.** `MeshLoader` generates a tangent basis on request; the sample is normal mapped throughout. See below. |
| ~~**Post-processing**~~ | **Tone mapping done 2026-09-10** — an HDR scene target, exposure in stops, and a choice of curve. See below. Bloom and colour grading are a *look* and are not here. |
| ~~**Particles**~~ | **Done 2026-09-10.** `ParticleSystem`, `ParticleRecipe`, `ParticleEmitter` and `ParticleRenderer` — embers, a pickup burst and landing dust in the sample. See below. |
| ~~**A character controller**~~ | **Done 2026-09-10.** `CharacterController` — walking, standing on things, a step height, gravity, jump, crouch and slide. The sample walks on it. See below. |
| **LOD and instancing** | The next thing that binds once a scene is larger than one valley. |
| ~~**Input rebinding, settings persistence**~~ | **Done 2026-09-10.** `InputBindings`, `PlayerSettings` and `KeyCode`; the sample has a settings screen that saves as you change it. See below. |

**Contested — defer, and say so rather than pretending they are unwanted.**

| | the actual state of play |
|---|---|
| **Scene node model / ECS** | An ECS stores objects as arrays of components processed by systems, instead of objects with methods — good for thousands of entities. **Godot has none. Unreal's is optional and recent. Unity's is a separate opt-in stack.** Shipping without one is the norm, not a shortcut. Pick a side when something forces it. |
| **Scripting** | A second language for gameplay. It exists to let non-programmers and fast iteration in. A one-person engine in Swift has neither problem yet. |
| **Scene serialisation beyond a level file** | The level format covers placements and markers. A general "save any object graph" format is the same decision as the node model, and follows it. |

**Enormous cost — business decisions, with the cost stated.**

| | what it really costs |
|---|---|
| **A standalone editor application** | **Unity's editor is larger than its runtime.** This is where solo engines die. `LevelEditor` already gives the shape that matters — a game embeds it and edits in place, the way id and Valve games did. |
| **Windows / console backends** | A real port of the platform layer, not an `#ifdef`. The single change that would most widen the audience, and the one Mac-first defers on purpose. |
| **Physics** | Rigid bodies, constraints, a solver. Most engines license one rather than write it. |
| **Networking** | Replication, prediction, reconciliation. A genre decision before an engineering one. |

### So who would use it, and when

**Not "an engine for everyone" — an engine for a native macOS first- or third-person game.** That
audience is small, which the section below says plainly. The honest bar for it being *usable by
somebody else* is the first table above, down to and including materials and a character controller.
Everything below that line is polish; everything above it is somebody being unable to start.

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

## Skinned animation (2026-09-09)

**The engine's single biggest gap, and it is closed.** A game with a person or a creature in it can
use this engine now. Four types, none of which needs a GPU to test:

| | what it is |
|---|---|
| `Skeleton` | Structure only — joint paths, derived parentage, the rest pose, and the inverse bind matrices. Shared by every character wearing the rig. |
| `AnimationClip` | Keys for translation, rotation and scale, with the clip's own joint names. Plus `AnimationBinding`, which matches a clip's joints to a rig's **by path, once**. |
| `SkeletonPose` | A rig with a pose on it. Samples a clip, cross-fades two, or takes a pose outright, and produces the joint palette a vertex shader indexes. Allocates nothing per frame. |
| `RigLoader` | Reads the skeleton and every clip out of a USD file. **No GPU**, which is why the fiddly half is testable. |

The sample proves it: figures placed by the level file, standing in an idle clip, cross-fading into a
wave as the player comes near, lit and shadowed by exactly the shaders the rest of the scene uses.
Their rig is generated by `Tools/make_sample_figure.py` — 11 joints, two clips, written as `.usda`
rather than shipped as a binary nobody can read.

### Three things measured, that the API does not tell you

Each one produces a character that is wrong rather than a build that fails, which is why each is now
a test with a fixture behind it.

1. **`MDLSkeleton`'s two transform arrays are in different spaces.** `jointRestTransforms` is
   **joint-local**; `jointBindTransforms` is **skeleton-space**, already accumulated. They hold the
   same numbers in any rig rooted at the origin — which is most hand-written test rigs and no real
   character — so a test rig that does not separate them passes while wrong. `offset-rig.usda` puts
   its root at (5, 0, 0) for exactly this reason.
2. **Clips are not in the object hierarchy.** They arrive in `MDLAsset.animations`, a container of
   its own, named by their full path. Walk the objects looking for them and every character is a
   statue.
3. **`MDLAnimationBindComponent.jointPaths` comes back empty** even with the skeleton attached. The
   paths are on `MDLSkeleton.jointPaths`.

Two smaller ones, both measured rather than assumed: **keyframe times arrive in seconds**, converted
from the file's time codes, so nothing downstream needs the frame rate; and **asking for four
influences per vertex when the file authored two is safe** — Model I/O pads with joint 0 at weight 0,
which contributes nothing, so the shader needs no branch.

### What is deliberately not here

**No animation state machine.** The engine cross-fades two clips; *which* two, and what interrupts
what, is the game's decision today. That is a contested shape, not a settled one, and there is no
evidence to design it from — the sample has two clips and a distance check.

**No retargeting, no IK, no root motion.** Each is real, each is wanted eventually, and none of them
can be designed from a rig somebody generated to test the loader.

### Why this was legitimate to build engine-first

It is the second row of the table above: a settled shape. Nobody has to discover what a skeleton, a
joint palette or a cross-fade is, and no game could teach a better answer than the one every engine
already uses. What a game *would* have taught — how clips get chosen, how a controller drives them —
is exactly what was left out.

> **The rule this seemed to break, and did not.** "Nothing enters this package speculatively" is
> about architecture with no single right answer. Applied to skinning it would have kept the engine
> unusable by any game with a person in it, waiting for a game that could not be built.

## Materials and textures (2026-09-09)

**The largest routine gap after animation, and it is closed.** Three pieces, split along the same
line as the rig loader — what a material *says* needs no GPU, and turning that into memory on one
does.

| | what it is |
|---|---|
| `Material` | The metallic-roughness parameter set: base colour, metallic, roughness, emissive, and where each map lives. A value type, `Sendable`, no device. |
| `TextureSlot` | Which map a texture is — and therefore whether it holds **colour or numbers**. |
| `TextureStore` | Loads a file once, hands the same texture back after that, and carries the 1×1 fallbacks. |

`MeshLoader` returns a `Material` per submesh instead of throwing the file's materials away, which is
the difference between a bought asset arriving intact and arriving as untextured geometry.

### This is a material, not a material *system*

The parameter set is settled — glTF, `UsdPreviewSurface`, Unreal, Unity and every exporter agree on
it, and inventing another vocabulary would make every bought asset a conversion problem. **A material
system is a different thing and is not here**: no shader graph, no permutations, no pass model, no
authoring. That is the contested part, where engines genuinely disagree, and where one game's needs
would decide it wrongly for everybody.

### The v axis, and a bug that hid in plain sight

**Metal puts texture coordinate (0, 0) at an image's top-left. USD and OBJ put `st` (0, 0) at its
bottom-left.** Something has to reconcile those exactly once, and `TextureStore` does it — every
texture is loaded with a bottom-left origin, matching every format Model I/O reads.

**It was wrong from the day textures were added and nothing could tell.** The sample's crate, stone
and ground maps are planks, brickwork and noise, and every one of them reads the same upside down. It
took a bought character whose texture is a **palette** — a 32×32 grid of swatches with a magenta row
along the bottom — for a vertical flip to stop softening an edge and start handing a limb a
completely different colour.

> **The lesson is about the test asset, not the code.** Four generated textures, none of which could
> fail visibly. The regression test now uses a fixture that is red on top and blue on the bottom,
> because a test image that looks the same either way up is testing nothing about which way up it is.

`.topLeft` remains available for glTF-derived UVs, which are the other way round.

### sRGB is a property of the slot, not a decision per call site

A colour map is authored in sRGB, because that is what a monitor expects and what spends more range
on darks where eyes are more sensitive. Shading arithmetic is only correct in linear space, so a
colour texture has to be decoded on the way in — free, if the texture is created with an `_srgb`
format, and not at all if it is not.

**A roughness or normal map is not a colour.** Its bytes are already numbers, and decoding one as
sRGB bends every value: mid-grey roughness 0.5 arrives as 0.21, so the whole scene looks wetter than
it was authored. Both mistakes look like a lighting problem rather than a loading one, so
`TextureSlot.isColor` decides and nothing else gets asked.

### Three things measured about Model I/O's materials

1. **Two properties can carry the same semantic, and `property(with:)` hides it.** A USD
   `UsdPreviewSurface` with a textured diffuse arrives as a float3 `baseColor` *and* a texture
   `diffuseColor`, both `.baseColor`. `property(with:)` returns whichever it reaches first, so a
   loader using it gets a colour on one asset and a texture on the next. Read the whole list —
   `properties(with:)` — and take the first, which is the one the file authored rather than the one
   the importer invented.
2. **The importer's invented base colour is 0.18 grey.** That float3 above is 0.18 in a file that
   never mentioned a base colour: a principled-shader default. Multiply a texture by it and the asset
   arrives at 18% brightness, which reads as a lighting bug in a renderer that is working. **A slot
   with a map takes a white tint**, and the number is used only where there is no map to tint.
3. **A texture property's *type* depends on a call somewhere else.** The same property is `.string`
   before `MDLAsset.loadTextures()` and `.texture` after it. Matching on `.texture` works or fails
   depending on whether an unrelated line ran. Having a URL is what actually means "this is a map".

### What the sample turned up

- **`half` is a type in Metal Shading Language.** A Blinn-Phong half-vector named `half` fails to
  compile with an error about a declaration specifier, which does not obviously mean "rename this".
- **A `float4` vertex attribute wants a 16-byte-aligned offset.** In the skinned layout that puts the
  weights *before* the joint indices in memory, though the shader declares them the other way round —
  attribute index and byte offset are independent, which is the thing that makes it fixable.
- **Identity tints stop being a good idea the moment surfaces are textured.** The sample coloured
  objects by their level tag — earth for ground, ochre for a landmark. Multiplied against a map, a
  ground tint of 0.32 took an already-dark texture to a sixth of its brightness, and the courtyard
  went black. Identity is the material's job now; the game's tint says only what a file cannot
  know — an objective already reached, and whatever is selected in the editor.

## What a real character brings that a made-up one does not (2026-09-09)

The rig loader was built and proved against a figure written by a script — eleven joints, two clips,
one file. **Then an 87-joint character from an actual toolchain was loaded**, and it arrived in three
shapes the engine had no answer for. None of them was a bug in what existed; all three were things a
generated asset had no way to show.

### One file per clip, and each one carries a whole copy of the rig

Every toolchain that exports one animation at a time gives a file per clip, and each of those files
contains the mesh and the skeleton as well. `RigLoader.load` read one file and returned skeleton
*and* clips, so five animations meant five copies of a 34,650-vertex mesh.

`clips(named:)` reads only the animations, and `load(named:clipFiles:)` puts a rig from one file
together with animations from others. **The mesh in those files is still parsed** — Model I/O has no
way to open an asset's animations alone — but nothing is laid out or uploaded, because there is no
vertex descriptor and no buffer allocator.

A file holding one clip has it **renamed to the file's own name**. The internal name is
`root_A_MOD_BL_Walk_F_Femn_Animation_Base_Layer`; a game asks for `walk`.

### A clip file's rest pose is not the rig's rest pose

**The trap, and the reason clip files' skeletons are ignored rather than merged.** A per-clip export
carries a full rig whose rest transforms are wherever the exporter left it — usually the clip's first
frame. Measured on the same joint of the same skeleton:

| file | rest translation |
|---|---|
| base | (10.42, 4.08, 7.84) |
| walk | (3.16, 1.17, 7.84) |

Merge them and every joint a clip does *not* animate falls back to whichever file was read last. The
character stands wrong, and the fault changes as animations are added — which makes it look like an
animation bug rather than a loading one.

### The scale is on a node, and the loaders were ignoring it

**Corrected 2026-09-09, after a first diagnosis that was wrong.** The character measured 176 units
tall, which was read as "the asset is in centimetres and the file does not say so". It does say so.
The mesh data is in centimetres and the **conversion sits on a parent node** — the empty an FBX
import creates, scaled by 0.01 — so the character is 176 units in its own space and 1.77 m in the
world, and every part of the file agrees.

**What was actually wrong was the engine.** `MeshLoader` and `RigLoader` read a mesh's bounds and a
skeleton's joints and never walked the node chain above them, so any asset with a parent transform
came in a hundred times too big. Harmless for a hand-written OBJ at the origin, which is every asset
this repository had until a real one arrived.

`LoadedMesh.nodeTransform` and `Rig.nodeTransform` report it now, and it is applied the same way as
everything else in this family — **in front of the model matrix**, where one matrix corrects the
mesh, the rig and the animation at once.

> **The lesson, and it is about the probe rather than the asset.** The measurement that produced the
> wrong answer read `MDLMesh.boundingBox` and stopped. It never asked what the mesh hung off, so it
> could not see the half of the answer that was sitting one level up. A probe that reports a number
> without reporting the space it is in is a probe that will eventually be believed.

### Up axis: real, and now handled at both ends

Separately from the scale, the file *was* Z-up, because Blender's USD exporter writes Blender's own
convention unless told otherwise. That is genuine and `AssetOrientation` handles it.

**The studio's exporter now states `upAxis = "Y"`**, which is USD's own default and what Model I/O,
Quick Look and Preview assume — a Z-up character opens in Preview lying on its side. So our own
characters need no correction, and a bought one still might. **Honouring the file's declared up axis
is what a correct loader does**, and it costs a matrix multiply at load whether or not it turns out
to be the identity.

### The sample ships the untidy version

Its figure is written **in centimetres under a node scaled by 0.01, with its second clip in a file of
its own** whose copy of the skeleton has the wrong rest pose — the faults, not tidied versions of
them. It renders identically to the tidy single-file version it replaced, which is the whole point: a
loader that only ever sees identity node transforms is a loader whose node handling is untested, and
that is exactly the bug this arrangement caught.

### And then it was actually run — 2026-09-09

**Everything above was found by *probing* the character with a script. Probing is also what produced
the one wrong answer this repository has had to correct**, so the sample gained a way to load a real
one and it was pointed at a 93-joint, 39,360-vertex character with six clips. It renders: skinned,
textured, shadowed, animating, at the right scale, standing on the ground.

**Three things that only running it could show.**

- **The engine could not load anything outside its own bundle.** `MeshLoader` and `RigLoader` took a
  resource name and a `Bundle`, so a character sitting in a pipeline's output folder was unreachable —
  and so is a mesh a level editor opens, and so is a mod. There are `url:` entry points now, and the
  bundle calls are the convenience on top. **A gap of that shape cannot be found by a fixture**,
  because a fixture is a bundle resource by construction.
- **Facing is per asset, exactly as predicted.** The character's front is not where the sample's
  markers assumed, and nothing in the file says which way it faces. It is a yaw applied where the
  thing is placed.
- **The material names no texture**, also as predicted: the tool builds the colour map in memory, so
  there is no file for the exporter to reference. It ships beside the model and is bound by name.

**Everything else simply worked** — 93 joints against a 128-joint palette, four influences per vertex
genuinely in use, the node scale, the clip-per-file loading, the clip files' wrong rest poses, the
declared up axis. That is what the fixtures were for, and it is the argument for having built them:
the faults a real asset exposes are cheap to fix *once you know they exist*, and finding them is what
the real asset is for.

> **One rough edge left alone.** The base file's own clip keeps the exporter's name —
> `root_A_MOD_BL_Idle_Standing_Femn_Animation_Base_Layer` — because only clip *files* are renamed to
> their stems, and "RobotPlayer" would be no clearer for an idle. The sample blends the first two
> clips positionally and prints which two, since that is otherwise a guess.

**Pointing the sample at one:** `WINDAGE_SAMPLE_CHARACTER=/path/to/Name` — a path with no extension.
It loads `<path>.usdc` for the rig and mesh, every `<path>_*.usdc` beside it as a clip, and
`<path>_ColorMap.png` as the base colour. Not shipped, because a real character is tens of megabytes
and belongs to whoever made it, and this repository builds with nothing checked out beside it.

## Normal mapping (2026-09-10)

A normal map stores directions in **tangent space** — relative to the surface, so one map serves a
wall and a barrel. Getting back to world space needs the surface's own axes: its normal, and a
**tangent** aligned with the texture's u direction. The tangent depends on how the texture was laid
across the triangle, which only the mesh knows; a shader can approximate it from screen-space
derivatives, and the approximation fails exactly where mapping is tightest.

`MeshLoader` generates one when the pipeline's semantics ask for `MDLVertexAttributeTangent` and the
file did not bring it, which is most files — Model I/O's importers rarely carry tangents even where
the source format had them.

### Four things measured, each of which fails quietly

- **Model I/O's OBJ reader recognises only `bump`.** All five spellings were tried: `map_Bump` —
  which is what Blender and Maya write — `norm`, `map_Kn` and `map_normal` are read and **silently
  dropped**, leaving no property on the material and nothing in the log. Only `bump` produces a
  `tangentSpaceNormal`.
- **The basis must be built before the vertex descriptor is applied.** Handing a descriptor to
  `MDLAsset(url:vertexDescriptor:bufferAllocator:)` converts the file to that layout at load, and a
  tangent the file lacks is filled with **zeroes** — degenerate rather than absent, which normalises
  to NaN and deletes the triangle rather than shading it wrongly. So: load with no descriptor,
  generate, then apply.
- **`w` is handedness, ±1, and it is not padding.** A UV island mirrored across the model — most of
  any character, whose two halves share one texture — has its bitangent reversed. Drop the sign and
  every mirrored surface is lit as though the light were on the other side.
- **A tangent transforms by the model matrix, not the normal matrix.** It lies *along* the surface.
  The inverse transpose exists for things perpendicular to a surface, and using it here shears the
  tangent off the surface the moment anything is scaled unevenly.

### Two decisions in the shader

**The bitangent is reconstructed, not carried** — it is the cross product of the other two times the
handedness, so storing it would cost twelve bytes a vertex to save one cross product, and the two
could then disagree. The tangent is re-orthogonalised against the normal first, because interpolating
across a triangle leaves them no longer perpendicular and a skewed basis skews every direction it
maps.

**The shadow lookup keeps the geometric normal.** Biasing a shadow sample along a mapped normal moves
it off the surface it belongs to, and the contact shadow detaches from its caster — a bug that looks
like a shadow problem and is a normal-mapping one.

### The sample's normal maps come from its colours

`Tools/make_sample_textures.py` defines a height field per surface — a plank gap is lower, mortar is
recessed — and derives both the colour and the normal map from it. Drawn independently the two would
drift, and a normal map that disagrees with the colour under it reads as bad lighting rather than as
a mistake. Central differences wrap at the edges, because these textures tile: clamping puts a seam
of flat normals around every tile, which catches the light as a grid.

## The probe that said this was possible — 2026-09-06

Before any of the above was treated as a plan, the load-bearing
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

### What it was estimated to cost

Vertex format (joints + weights), a skeleton and clip value type, sampling to a joint-matrix palette,
and skinning in the vertex shader. **That estimate held**, and the one thing it missed was the
authoring problem — a courtyard of boxes cannot show a skeleton, so the sample needed a rig before it
could show anything. Generating one was a smaller job than buying one and a far better test: a rig
whose every joint, weight and key is written by a script in this repository is one whose failures can
be attributed.

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

> **"The trigger is an asset, not a decision" — half right, and worth recording as such.** The note
> here said a clip and blending API built with nothing to skin would be guesswork, and that a rigged
> character had to be bought first. The first half was right and the second was not: what the API
> needed was *a* rig, not a *bought* one. `Tools/make_sample_figure.py` writes an eleven-joint figure
> with two clips, and it exercised the interface hard enough to find every fault listed above.
>
> **What a bought character will still test that a generated one cannot**: a hundred joints rather
> than eleven, four influences per vertex actually in use, a non-identity geometry bind transform,
> and whatever an exporter does that a script does not.
>
> **The format filter stands: OBJ carries no skeleton.** An OBJ character is a statue by format, not
> by engine limitation.

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

**True in the literal sense since 2026-09-10.** This section described the intent for months while
there was no curve for the HUD to be after — the scene was written straight to the drawable. There
is one now, and the ordering it was designed around is real: the scene is drawn into an HDR target,
a second pass fits it to the display, and `GameLoop.encodeHUD` runs in **that** pass, after the
curve.

The engine enforces the ordering rather than documenting it because the failure is silent: a HUD
drawn inside the scene's shading goes through exposure and a filmic curve like everything else, and
a brand colour arrives desaturated and shifted with nothing to say why.

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

## A microfacet specular, in the sample (2026-09-10)

The sample shades with Cook-Torrance and a GGX distribution now — Smith height-correlated visibility,
Schlick Fresnel, and Karis's analytic fit of the split-sum environment BRDF standing in for a lookup
table. It replaced Lambert plus a Blinn-Phong lobe, which was written to prove that a material's
roughness arrived and did something, and had become the weakest part of the picture once there was an
HDR target to put a real highlight in.

### It is in the sample, and that is the split working

The engine owns when things happen, the depth convention and the tone map. **What a surface *is* — its
BRDF, its lighting model, how many lights it takes — is a game's**, and no two games will agree.

**If a second consumer writes this same function, that is the moment to extract it.** Which is the
shadow-pass lesson applied before the fact rather than after: the rule is not "wait for a third", it
is "one copy is a game's business and two copies are a defect".

### What an OBJ cannot say, measured

**Model I/O's OBJ reader returns roughness 0.9 and metallic 0.0 whatever the file contains.** Five
materials were tried: `Ns 12`, `Ns 200`, `Pr 0.25`, `Pm 1.0`, and both PBR extensions together. The
roughness semantic never moved and the extensions were read and discarded.

What does arrive is `Ns`, as `specularExponent`. So that is where an OBJ's roughness comes from, via
`α = sqrt(2 / (Ns + 2))` and perceptual roughness `sqrt(α)` — an approximation between two lobes that
are not the same shape, and one every renderer that reads OBJ makes some version of.

**`specularExponent` is a reliable tell for a Blinn-Phong material**, because a USD
`UsdPreviewSurface` carries real roughness and metallic and no exponent at all. Its presence means
"the roughness beside this is invented".

### Five things worth knowing about the lobe

- **Metal with no environment is black.** A metal surface has no diffuse; its entire appearance is
  what it reflects. With only a sun in the scene it is black but for one highlight — so the sample
  reflects a two-colour sky gradient, which costs a `mix` and is the difference between metal reading
  as metal and reading as a bug. **The figure is metal deliberately**: a dielectric surface looks much
  the same under either lobe, and would have left `metallic` untested.
- **`alpha` is roughness squared.** Roughness is authored perceptually so a slider steps evenly; the
  distribution wants the physical quantity, and using the perceptual value bunches the useful range
  into the first third.
- **Fold `1 / (4 NdotL NdotV)` into the visibility term.** Separately, both it and the geometry term
  vanish at grazing angles, and the division is a ratio of two vanishing numbers — a rim of fireflies
  along every silhouette. Combined, the zeros cancel algebraically and never reach the hardware.
- **Clamp roughness away from zero.** A perfectly smooth surface is a delta function: infinitely
  small, infinitely bright, and on screen one crawling pixel.
- **`kD = 1 − F`.** What is not reflected is available to scatter. Skipping it makes a shiny surface
  brighter than the light falling on it — the usual way a first PBR shader breaks energy conservation.

### The analytic sky it started with is gone

It was replaced the same day by a real prefiltered environment — see below. The two-colour `mix` is
kept in the history because it is the right first step: it costs one instruction, it is the difference
between metal reading as metal and reading as a bug, and it is enough to get the BRDF correct before
adding a cube map to the list of things that might be wrong.

## Lights that are not the sun (2026-09-10)

A directional sun and an environment map light an outdoor scene correctly and have **no answer at all
for an interior**: the sun does not reach inside, and a sky-coloured ambient lights a cellar as though
the sky were overhead.

`PunctualLight` and `LightSet` were **extracted from a probe built to ask exactly this question**, and
stripped of the game that asked it. That is what the probes are for.

### What the probe had right, and it is the important part

**A hard budget cannot promise a smooth hand-over in an arbitrary level.** A fragment shader cannot
loop over every lamp in a building, so a game needs a budget and a rule for choosing which lights fill
it. The obvious rule — the nearest few — has an obvious bug: *nearest* changes as the player walks, so
a light drops out and a surface goes dark in one frame.

Choosing by **influence** rather than distance fixes the common case, because a light then leaves the
set where it had nearly stopped mattering. It does not fix the general one: if five lights all
contribute at a point, one is dropped, and how visible that is depends entirely on how the level was
built. A bigger budget only moves the number.

So the promise is conditional, and `isOverSubscribed(at:)` checks the condition: **where no more than
the budget are above `negligible`, nothing the player can see is ever dropped.** A level that violates
it has a lighting fault built into its geometry — findable before it ships rather than after somebody
reports a flicker in one corridor.

### What the probe had wrong

It ranked lights by **falloff alone** and ignored how bright they are, so a candle at one metre
outranked a floodlight at ten — and the floodlight was the one dropped. Influence is weighted by
luminance now: a dot product, and the ordering means what it claims.

> This is what a probe is supposed to produce — not code to paste in, but a shape and a finding, both
> of which survived, and one mistake that was cheaper to find there than here.

### Spot lights, and a cone that cannot be tested at one point (2026-09-10)

A cone is a direction and **two** angles — full brightness within the inner, nothing beyond the outer,
smooth between. One cutoff gives a hard-edged circle that reads as a stencil rather than as a lamp.

**A point light is a spot with no cone, and the shader does not branch on it.** Its `angleScale` is 0
and its `angleOffset` is 1, so the angular term evaluates to exactly 1 everywhere from the same two
multiplies — one code path, and nothing that behaves differently depending on which kind of lamp a
level happens to hold.

**Selection is where a cone bites.** The nearest point of a box gives the best *distance*, which
settles a point light. For a spot it does not: the nearest corner of a wall can be outside the cone
while the far end of the same wall is brightly lit, and testing that one point drops the light and
darkens the lit end. So the cone is tested against the box's bounding **sphere** — conservative, able
to say yes when the answer was no and never the reverse — and ranking uses distance alone. Same
asymmetry as `Frustum`: a false positive costs one iteration of a loop, a false negative deletes light
the player can see.

## Shadows for the lamps (2026-09-10)

A spot light casts now. Until this, a lamp reached through a wall — a real limitation, and the reason
the sample's ranges were kept short: a light that passes through geometry is only obvious when it
reaches far enough for it to be.

### An atlas rather than a texture each

A shadow map per light means a texture per light: an allocation and a residency entry appearing and
disappearing as a level loads, a render pass each, and a shader indexing an array of textures. One
texture cut into tiles is a fixed allocation, **one render pass for every light** — the viewport moves
between them — and a single binding the shader samples with an offset.

**Scissored as well as viewported, which is not redundant.** A viewport limits where geometry lands;
it does not stop a clear or a wide triangle touching a neighbour's tile, and one lamp bleeding into
another's map is a shadow that appears in the wrong room.

### Spot lights only, and the cost of the rest is written down

A spot's shadow map is one perspective render — the same shape as a cascade, sharing the same
pipeline, which is why this was affordable at all. **A point light needs six**, one face per
direction, so shadowing every lamp in a room costs six times what shadowing the aimed ones does.

`ShadowAtlas.viewProjection(for:)` returns **nil** for a light with no cone rather than silently
shadowing one direction of six. The remaining work was described here as "cube tiles in the atlas, six
passes per light, and a shader that picks a face before it picks a tile"; **two thirds of that was
right**, and the section below is what happened to the other third.

### Four smaller ones

- **The field of view is the cone's outer angle doubled**, and a little more. Less cuts the shadow off
  inside the lit circle; more spends resolution on nothing.
- **A lamp pointing straight down is the common case and exactly where a fixed up vector is
  degenerate** — the cross product is zero, the basis becomes `NaN`, and nothing draws at all.
- **The shader's constant bias is positive where the rasteriser's is negative.** They are different
  quantities in different spaces — normalised light depth against a rasteriser offset — and reversed-Z
  inverts the sign of only one of them. Two biases with the same name and opposite signs is worth a
  comment at each.
- **Tiles go to the brightest, longest-reaching lamps.** A light nobody can see casting a shadow
  nobody can see is the tile to give away first.

### Verified by difference, not by looking

A spot's shadow on open ground is subtle enough that "looks about right" is not verification. The same
frame was rendered with the per-light shadow flag on and off, and **1.2% of the frame changed**,
confined to the lit ground.

> **That measurement came before the search for a good camera angle**, and it is the right order. It
> answered "is this working" in one step, so the time afterwards went into making it *visible* rather
> than into wondering whether there was anything to see.

## Point lights cast too (2026-09-10)

Every lamp in the sample stops at a wall now, aimed or not. `ShadowCubes` is a cube-array depth
texture, the six face matrices, and the pass that records them.

### A cube array rather than tiles of the atlas

The section above predicted cube-shaped tiles inside `ShadowAtlas`. That was the wrong shape, and both
reasons only appear once the shader is written.

**The face maths has to agree with six matrices exactly.** Picking a face by hand means reproducing
the cube convention in a shader — which axis becomes *u*, which becomes *v*, which of the six sign
flips applies — and matching it against six view matrices built on the CPU. Every one of those is a
place for a face to come out rotated or mirrored, and a mirrored face still casts a shadow. It lands
somewhere else, and on screen that reads as a bias problem rather than a convention problem.

**And a filter kernel cannot cross a tile edge.** A tap that steps off the edge of a face does not
land on the next texel of that face; it lands on a different face at a right angle. Clamping draws a
bright seam down all twelve edges of the cube; not clamping reads a neighbouring lamp's tile.

A `typeCubeArray` texture hands both problems to the hardware. The sampler takes a **direction**,
picks the face itself, filters across the seams itself, and does its own comparison — so the
convention is the hardware's and there is nothing left to match. What stays on this side is the six
view matrices.

### The bias is in metres, not in depth

A cube face stores `near / distance`. **A constant added to that depth is a third of a millimetre at
one metre and most of a metre at ten**, so a bias tuned to clear acne beside the lamp deletes contact
shadows across the room. Taking it off the *distance* instead, scaled by the face's own texel size,
makes it one number at every range — the same reasoning as `ShadowCascades.biasTexels`, arrived at
from the opposite direction.

### Six passes, and what culling gives back

Six passes per light is the honest cost, and it is why `ShadowCubes` defaults to **two** casting
lights rather than a comfortable number: a level should be choosing which lamps deserve one.

Two culls take most of it back, and both are in the pass. **A caster outside the light's range is
skipped for all six faces; one outside a face's `Frustum` is skipped for that face.** In the sample's
ruins — two casting point lights across thirty-two drawables — that is **35 objects recorded against
384 unculled**, so all twelve passes together cost barely more than one unculled pass.

`ShadowMap.Batch` grew an optional `bounds` for this. Nil means draw everything, which is the
conservative direction: a false positive costs a draw and a false negative deletes a shadow.

> **`Frustum` had no consumer inside this repository until now.** It arrived in 0.4 from two games
> that wanted it, and the first thing here to need it was a shadow pass rather than a camera.

### `right × up == forward`, which looks like the wrong handedness

A cube map is sampled from the *inside*, so its faces are mirrored relative to a camera looking out.
The relation already held for a spot's view matrix and for the cascades, so the winding and the
front-face cull are the same in all three — but it is the kind of thing that gets "fixed" by somebody
checking a determinant, so it is asserted in the tests.

### Verified twice, because half of it is invisible

**The half a screenshot cannot show** is whether the six matrices agree with the sampler's own rule.
That is checked on the CPU: for a spread of directions, the face the rule picks and the *uv* it gives
have to be exactly where that face's matrix lands the point. `ShadowCubes.lookup(direction:)` exists
only for this — nothing calls it at runtime, because the hardware does that job.

**The half it can** was a difference, as with the spots: the same frame with the per-light cube flag
on and off changed **1.77% of it**, all of it around the two braziers.

## Lights that belong to a placement (2026-09-11)

`Level.Placement.light` is a lamp the placement carries, in its own space — an offset from its origin,
a cone aimed in its frame. `Level.resolvedLights(on:)` puts every lamp in the world: the free-standing
ones, then the carried ones through a `TransformHierarchy`, each attached externally to its placement's
transform.

**It exists because a brazier and its flame were two entries in one file**, kept together by a test,
and the first person to move a brazier in the in-game editor would have left its pool of light on the
floor where it had been. Now moving, turning or copying the placement moves the lamp; the offset scales
with the placement and the lamp's reach does not.

## What things are made of (0.9.1)

`Level.Placement.surface` is what a placement is made of — `"stone"`, `"wood"`, `"metal"` — and
`Level.groundSurface` what the ground is. `Level.surface(standingOn:)` answers the one question a
footstep asks: the surface of the placement stood on, or the ground's for `nil`. **The game's word, like
tags** — the engine does not know what sounds a game has, only that a footstep needs to ask.

**It exists because a game knew which solid it stood on and nothing about it.** The controller reports
`groundSolid`; the sample filled the gap with "every solid is stone, the ground is dirt", true of both
its levels only because nobody had laid a board. A placement that names no surface answers `nil`, not
the ground's, so the gap can be noticed — the sample logs it once and a test on the shipped levels makes
sure there are none.

**Walked in the sample**: the ruins' stairs are three stone treads up to a landing of three timber ones,
the same shape, different wood. The scripted walk reports footsteps on stone up the stairs, on wood
across the landing, and a landing on dirt off the far end — footstep sounds for wood and metal made by
`Tools/make_sample_sounds.py`, whose existing sounds regenerated byte-for-byte.

## A placement's transform, and a rotation that ran backwards (2026-09-11)

**`Level.transform(of:on:)` is the one definition of where a placement is**: scaled, turned by `yaw`
about +Y, moved to its anchored position. There was none. The sample built the matrix by hand; a game
built it twice; and **the engine's own bedding turned the other way from all of them** — for a
positive yaw every renderer turns +X towards −Z, and bedding turned it towards +Z, so it sampled the
ground under the corners of the placement's mirror image.

Nothing showed on flat ground, for square footprints, or at right angles. A long building turned on a
slope was bedded on corners it does not have. It came out of a game the engine was extracted from, and
that game's own collision uses the same backwards turn; the engine is fixed, and the game's parity test
against it will now say so.

> **What found it was needing the transform, not looking for a bug.** A light carried by a placement
> has to be moved by the placement's transform, and asking where that lived turned up four copies.

## Controller buttons a player can move (2026-09-10)

`PadBindings` does for the controller what `InputBindings` does for the keyboard, for the four actions
that are buttons on a pad: jump, crouch, sprint and brace.

**Stored by position** — `south`, `east`, the shoulders, the stick clicks — because the bottom face
button is A on one pad and Cross on another, and the thumb learned where it is, not what it says. What
a settings screen shows comes from the connected pad itself.

**Only the buttons that are actions move.** The sticks, the triggers, the d-pad and the menu button are
the convention; a shooter that let aim wander onto a face button would be offering a way to make itself
unplayable. R3 is refused because it is the engine's scroll notch. Square, Triangle and R1 are only
unbound *by default* — kept free so a title can grow a reload — and a title that has grown one reserves
it.

**A menu that has the pad turns the pad's actions off** (`acceptsPadActions`), because a pad is polled
rather than dispatched: without it, Circle pressed to leave the settings screen also crouches the
player behind it. The menu reads `padButtonsPressed` instead, and **reads raw presses rather than the
bindings** — it is where the bindings change, and a menu that followed them would move its own
"change" button.

### A controller nobody is holding

`GCController.withExtendedGamepad()` builds a real `GCExtendedGamepad` whose buttons are set from code,
and `InputState.useGamepad(_:)` reads it in place of the system's. That is what the tests press, and
what the sample's scripted walk presses — so the rebinding was driven end to end in the running game,
menu and all, with no controller on the desk. **Its d-pad only moves through `setValueForXAxis(_:yAxis:)`**;
set as a button, a direction is accepted and ignored.

## An override that hid a bug (2026-09-10)

**The ruins had untextured pillars and steps for as long as the sample had two levels** — whenever a
player walked into them from the courtyard, which is the only way a player gets there. The first
level's meshes were loaded, and their textures resolved, in one place; the next level's were loaded in
another that resolved nothing.

**Nothing showed it because every screenshot opened the ruins directly** with `WINDAGE_SAMPLE_LEVEL=1`,
and that path loaded the ruins' meshes the first way. The override existed to make a picture
repeatable, and repeatable turned out to mean *always the same route in* — never the player's. It was
found by building the braziers, which exist only in the second level and so would only ever load the
second way.

> **A debugging entry point is a second way into the program, and a second way in is a second place
> for state to be set up.** One loading path now, for both.

## Footsteps and landings (2026-09-10)

`CharacterController` reports what its body did each step — a foot coming down, a landing and how
hard, a jump — and which solid it is standing on. The sample plays dirt and stone footsteps from that,
and heavier landings.

### Footfalls from distance covered, not distance asked for

Pushing into a wall asks for six metres a second and covers none. Counting what was asked for is the
classic bug where a player standing against a wall marches on the spot, so strides are counted from
where the feet actually got to.

**The strides are longer than a person's, because the speeds are.** A walk here is six metres a
second — a jog — and a footstep every real 0.7 m would be eight a second, which reads as a drum roll.
At 2.6 m walking, 5 m sprinting and 1.6 m crouched the cadence is about 2.3, 3.6 and 1.7 a second,
which the ear takes for feet. The first step comes 40% of a stride after setting off, or the start of
every walk would be silent. A slide makes none; a step down a stair is not a landing.

### A foot on every tread — and where the rule had to live

A stride is longer than a stair tread, so four treads sounded like two footsteps and floating. The
fix was obvious and was put in the obvious place, the step-up in `move` — and **a test counting
footsteps per tread still found two**. The footprint's leading edge reaches each tread before any move
is refused, so it is the ground-following in the vertical step that lifts the body, and the step-up
was never running on stairs at all. The rule is in both places now.

### And a landing you can feel (2026-09-11)

The controller turns a landing's impact into a critically damped spring: the eye drops as the legs
take the weight — `landingDrop`, part of `eye` — and the view nods with it — `landingCameraDip`, for
the view only, by the slide's rule. Scaled between 3 and 12 m/s, so a jump dips a third and a 3.6 m fall
dips the whole 16 cm and 3.4°.

**Stepped by the spring's exact solution.** The first version integrated it with semi-implicit Euler
and a test found it reaching 20% short of where it was kicked; a critically damped spring has a closed
form, and using it makes the curve the same at any step size.

### An ambience volume (0.11.2)

`AudioEngine.ambienceVolume` scales the loops and nothing else — the output of their own spatialiser,
which every loop and no one-shot passes through — and `PlayerSettings.ambienceVolume` is the player's
dial for it, under the master volume. **A player who finds a fire too loud should not lose their own
footsteps turning it down**, which one volume made them do.

**Measured offline**: half ambience took a loop down 6.0206 dB — 20·log₁₀ ½ — and a one-shot by 0.0.
With the sample's own sounds, the crackle at 2 m went from −33.10 to −39.12 dBFS and a walking footstep
stayed at −29.18. The sample's settings screen has an **Ambience** row under Volume.

### Something that turns underfoot (0.11.1)

`Surroundings.turns` says how far each solid turned since the last step, and about which centre. A body
standing on one is carried round it — through collision, like any carry, and with no footsteps — and
`turned` reports the angle, **for the game to add to the view**: the controller walks by the yaw it is
given and does not own the camera, and a player carried round with a fixed view faces one way while the
floor spins. Positive is the way a placement's yaw and a camera's yaw both turn (`Level.turned`), so the
one number serves both. A solid that moves and turns is moved first, then turned about where its
centre is now.

**Ridden in the sample**: a 4 m stone turntable in the courtyard (`Tools/make_sample_turntable.py` —
round, so its box does not swell as it turns), at 30° a second. Standing 1.2 m from its centre for three
seconds, the table turned 90.0°, the feet 90.0° round its centre at the same 1.21 m, and the view 89.9°.

**Two things found**: a test measured against the *reported* turn passed with the turning switched off,
because both were zero — it is measured against the table's own turn now; and the sample's lifts and
turntables stood still in photo mode, because they advanced inside the walking branch — two frames 1.5 s
apart came out identical.

### A foot on the way down, as on the way up (0.11.0)

The climb has had a footfall on every tread since 0.6.9: at these speeds a stride is longer than a
tread, so distance alone would float up the middle ones. **The descent never had it** — the rule counted
only a rise, and four treads coming down sounded one footstep where going up sounded four. A step
*down* a tread counts now too, from the same ground-following that reports the rise.

**"One per tread" is not literal, and the test says what is**: a natural footstep just before a tread
edge merges with that tread's (the guard that stops a tread ringing twice), going up as well as down.
The invariant tested is **symmetry** — from mirrored starts, the same number coming down as going up
(0 against 4 before; 4 and 4 after). On the ruins' stairs the walk down from the landing went from 3
footsteps to 5 — wood, then stone, then dirt.

### Sounds that belong to a place (0.10.2)

`AudioEngine.startLoop(_:at:volume:)`, `moveLoop`, `stopLoop` play a sound for as long as a thing is
there; `Level.Placement.sound` is one a placement carries, at an offset in its own space like its lamp,
and `Level.carriedSounds(on:)` puts it in the world. A brazier moved, copied or deleted in the editor
takes its crackle with it.

**Loops have their own spatialiser**, because one distance curve cannot serve a shot and a fire.
Through the one-shots' curve — reference 8 m, then 90% of the inverse law — a sound at 20 m measured
over half its level at 2 m: a brazier through it would fill the level. Loops use the physical inverse
law from 2 m and measured **1 : 0.250 : 0.100** at 2, 8 and 20 m. Each loop starts at a different point
in its sound, so two braziers are not one crackle in two places.

**Measured, not heard — `AudioEngine(offlineSampleRate:)` and `renderOffline(seconds:)`** pull the mix
with no device, which is how every level here was checked. `WINDAGE_SAMPLE_MEASURE_AUDIO=1 swift run
WindageSample` does it for the sample's own crackle: −33.1 dBFS at 2 m, halving with each doubling to
−53.1 at 20 m — about 6 dB under a walking footstep, at the level file's 0.8, standing at the fire.

**Measuring found the engine's own note about spatialisation was wrong.** It set `.sphericalHead` on the
environment node — where the algorithm does nothing, since it belongs to each source — with a comment
that spherical head "keeps the directional cue a game reads". Set where it does take effect, a source
5 m to the right came out **1.01× louder in the right ear; HRTF gives 4.6×, `.auto` 5.6×.** Voices stay
`.auto`, as every `play()` had quietly made them; the note says what was measured, and a test keeps the
cue from going missing. **And a quirk of HRTF, measured**: inside a spatialiser's reference distance a
source is quieter, not flat — about 72% at the listener, rising to full at the reference — so a loop at
1 m reads a little under one at 2 m. Beyond the reference the inverse law holds exactly.

The sample reconciles its loops on every rebuild rather than restarting them, **matching by what and
where first**: placements have no identity but their index, and a copy inserted before a brazier
renumbers it — keyed by index, an edit to one brazier restarted the other's fire.

### And something that moves underfoot (0.10.1)

`Surroundings.motion` says how far each solid moved since the last step, in the order of `solids`; a
body standing on one that moved **goes with it, first**, before its own walking — so walking on a
moving platform is walking relative to it, and riding one standing still makes no footsteps and no
bob. Up and down is rigid (the eye does not ease after a lift the way it eases up a stair); across goes
through the same collision as walking, so a platform does not carry anyone through a wall. `carried`
says how far it went. **Translation only** — a turning deck is the next thing.

Measured against switching it off: without the carry a rising lift leaves the eye 8 cm behind (the
stair-smoothing), a sliding platform goes 4 m out from under a body that stays put, and walking on one
is not relative to it.

**Ridden in the sample**: a timber lift beside the ruins' landing, rising 0.9 m — from a step up off
the ground to the landing's level — with eased ends and pauses (the sample's code; the level only tags
it `"lift"`). The scripted ride logged the feet against the lift's top: 0.30/0.30 at the bottom,
0.75/0.75 halfway, 1.20/1.20 at the top, back to 0.30 still riding through the turn, up again, and a
walk off onto the landing at 1.20 — no footsteps the whole ride.

### And room to stand (0.10.0)

**Letting go of crouch is a request, not a promise of room.** Under a beam the controller keeps the
body down — at crouched height, a crouched walk's speed, no sprint, a crouched stride — and stands the
moment the footprint is clear; `isHeldDown` says so, for a game to put on screen. Room is the lowest
underside of anything over the footprint and above the soles, with the collision test's own tolerance.

**What it replaced was worse than the parked note said.** Standing up under a 1.5 m beam put the top of
the head 35 cm inside it — and then every move was refused, because the body already overlapped the
beam wherever it tried to go. Stuck, until crouching again, with nothing to say why.

**The sample found a second fault in the first fix**: the walk stops a body against a face to within
a hair, and a headroom check without that tolerance counted the touch as overhead — walking up to the
ruins' new lintel, *standing*, pushed the player into a crouch. Driven in the ruins after the fix:
stopped at the lintel standing (eye 1.70), crouched under it (1.05), let go — held at 1.05, "NO ROOM TO
STAND" — then walked out and stood the moment the body was clear.

### And a head that bobs, which a player can turn down or off (0.8.1)

`headBob` is a view offset in metres — across the view and up — **locked to the stride phase**, the
same distance-driven phase that sounds the footsteps. So the head dips as each foot lands, stops when
the body stops, and does nothing for a player pushing into a wall; a bob on a clock sways while standing
still, which reads as swimming.

- **Two dips for every sway**, the sway leaning toward the leg carrying the body: a figure-eight. The
  rise is the larger of the two (1.4 cm either side at a walk, against 0.9 of sway); equal amounts trace
  a loop.
- **Scaled by gait**: ×1.7 at a sprint, ×0.5 crouched, less below walking pace. **None in the air and
  none in a slide**, since neither has footfalls. Eased in and out, never switched.
- **A step up jumps the stride phase to a footfall**, and a bob read straight off the phase jumped with
  it — 2.86 cm in one frame on every tread, measured by a test that fails without the fix. The jump is
  carried and eased out at the eye's settling rate, the way the eye follows the step itself.
- **The view's, never the aim's**, like the dips. `PlayerSettings.headBob` is 0…1 with **0 as off**:
  bob is a known cause of motion sickness, so off has to exist, and most players who find it too much
  want less rather than none.

**Measured in the sample**, peak to peak through a scripted walk: 2.8 cm up and down and 1.8 cm side to
side walking, 4.7 and 3.0 sprinting, 1.4 and 0.9 crouched — the tuning, to the millimetre. Half on the
setting gives exactly half; off, set on the settings screen, gives none.

### What is underfoot

`groundSolid` is the index of the box the feet are on, or nil for terrain. It is what makes a stone
step sound like stone, and what a moving platform will need to carry you.

## Keys a player can change (2026-09-10)

`InputBindings` says which key does what; `PlayerSettings` holds that plus a sensitivity and an invert
**for the mouse and for the stick separately** (since 0.8.0), volume and brightness; `SaveStore` keeps
them. The sample has a settings screen on **O**.

### The bug it found: Shift had never worked in the sample

**macOS does not send Shift as a key press.** Shift, Control, Option and Command arrive as a change of
*modifier flags*, and a window that forwards `keyDown` and `keyUp` alone has no Shift at all. The
sample shipped like that with "shift sprint" printed on its screen. Rebinding is what found it,
because it made every key go through one path — and a modifier had no path.

So modifiers are keys: a window forwards `flagsChanged` to `InputState.flagsChanged(keyCode:
modifierFlags:)`, which reads the **device-specific bit** for the physical key — the generic Shift flag
is set while *either* Shift is down, so releasing the left one with the right still held would read as
still pressed. Sprint, or crouch, can then be bound to Control like anything else. The sample's
on-screen hint is now built from the bindings, so it cannot advertise a key that does nothing.

### The rules

- **A key already in use is swapped, not stolen.** Taking W for jump gives forward jump's old key. The
  alternative leaves a player who cannot walk and does not know why.
- **Escape, Tab and the arrows are refused.** Escape is the way out: bound to jump, the player cannot
  release the pointer or reach the screen that would undo it. Tab and the arrows are the engine's
  generic *next* and *step*.
- **A game adds its own always-on keys to the refused set** — in the sample P, R, N, M and O. A key the
  game consumes first is a key a binding never sees; jump on P would pause the game.
- **One key per action.** A secondary slot doubles every rule above.

### Tolerant, field by field

`SaveStore` returns nothing for a file it cannot decode, which for progress is the right failure and
for settings is a terrible one: **nothing means every setting reset**, so a player loses eight rebound
keys because a later build added a ninth. Both types decode field by field — a missing field takes its
default, an unknown one is ignored, a key name this build does not recognise costs only that one
binding, and a hand-edited file with two actions on one key keeps the first.

Keys are stored **by name**, so the file reads `"forward" : "W"` rather than `13`.

### A sensitivity per device, and an invert per device (0.8.0)

**A mouse and a stick are different kinds of input, so one number cannot suit both.** A mouse reports a
displacement and a stick a rate (`Camera.look(mouseDelta:)` against `Camera.turn(rate:deltaTime:)`);
a player's comfortable setting for one says nothing about the other, and a single multiplier made a
player who uses both choose which to leave wrong. Invert is split for the same reason: players who fly
often invert a stick and not a mouse. `mouseLookScale` goes in front of the mouse path and
`stickLookScale` in front of the stick's, and neither touches the other.

**A file from before 0.8.0 has one `lookSensitivity` and one `invertLook`**, and both devices inherit
them, since that is what the player had on both. They are read and never written; a device's own key
wins where a file has both.

**Proved in the sample by rates, not by reading code.** The scripted walk holds the look stick
(`pad.lookRight:0.5`) and moves the mouse (`mousex:500`), and prints how far the view turned. At the
defaults a half-second of full stick is 91.67° and 500 points of mouse is 63.03° — the constants,
exactly. With the mouse at 2.0, the stick at 0.5 and the stick inverted, set through the settings screen
from the virtual pad, they are 45.84°, 126.05°, and a stick-up that looks *down* while the mouse's
vertical stays put. An old-style file at 1.5, inverted, turns both devices 1.5× with both flipped.

### A dead zone per stick, and a stick that walks at the speed it is pushed to (0.9.0)

**A worn stick drifts**: it rests a few percent off centre, and past the dead zone that is a view
creeping round with nobody touching it. `PlayerSettings.moveDeadzone` and `lookDeadzone` let the player
cure it; `InputState` reads them. The response still starts from zero at the new edge and reaches full
at full deflection, so a bigger dead zone costs travel and never top speed.

**Building it found that movement ignored how far the stick was pushed.** `CharacterController` and
`Camera.advance` normalised the direction to stop two keys being faster than one — which also threw the
stick's deflection away: 5% walked 6 m a second, the same as 100%. They clamp to length 1 now. The game
the walking was extracted from had the same line and was fixed the same day.

**Proved in the sample with a stick held part-way** (`pad.lookRight@0.2`): at the defaults a stick
resting at 20% turns 2.26° a second and walks 0.11 m — the drift — and 50% turns 18.11° in half a
second; with the dead zones raised to 26% and 30% on the settings screen, 20% does nothing, 50% turns
9.64°, full deflection is still 91.67°, and 60% walks 1.99 m. Every figure is the curve's.

### No apply button

Every change is saved the moment it is made. A settings screen that can be closed without saving is
one a player closes without saving, and then finds their keys back the way they were.

### The scripted walk presses real keys now

`WINDAGE_SAMPLE_WALK` used to hand the controller a movement directly. That tested the body and
skipped everything in front of it — the bindings, the menu, and the Shift that did not work. It now
presses and releases keys down the same path a keyboard does, so a script can open the settings
screen, rebind a key, close it and walk with the new key. Two launches proved the round trip: rebind
forward to I and walk with it; quit; relaunch; I still walks and W does not.

## Particles (2026-09-10)

`ParticleSystem` simulates; `ParticleRenderer` draws. Embers rise off the ruins' braziers and the
figures' lanterns, a collected crate throws green sparks, and a landing from a drop kicks up dust.

### Extracted, and three things changed on the way

**The simulation came from a working game.** It steps on the fixed timestep, so a burst plays the same
way twice and the whole thing tests without a GPU; the pool is fixed; and when it is full the
**oldest** particle is recycled, never the newest, because the newest burst is the one the player is
looking at.

**Kinds became recipes.** The game had an enum of its own kinds — right inside one game, wrong in an
engine, because the next game's kinds are embers and spray. What was shared was the *shape* of a kind:
`ParticleRecipe` — count, speed, spread, life, size, growth, gravity (signed, per recipe: dust falls,
an ember rises, a flash does neither), drag, colour, fade, and whether it glows.

**"Every eighth step" became a rate.** Emitting on a step count ties an effect's density to the fixed
timestep; change the step and every continuous effect in the game changes with it. `ParticleEmitter`
keeps the fraction owed from one step to the next.

**The randomness was quantised.** The spread came from `fract(sin(x) × 43758.5453)` — the shader
one-liner — in 32-bit floats on the CPU, where the product is tens of thousands and the fraction keeps
only the bits left over. **300,000 draws produced 8,923 distinct values.** It looked plausible, which is
why nothing had said so. It is an integer hash now, and the same draws give 297,320.

### Light and matter share one pipeline

A spark makes light and covers nothing; dust covers what is behind it. **Premultiplied alpha serves
both**: the blend is `src + dst × (1 − src.a)`, matter writes its opacity as `src.a`, light writes zero,
and for light the blend becomes a plain add. Two pipelines would mean two draws and a sort between
them.

Drawn **into the HDR scene**, after everything opaque, with depth tested and never written — a spark
goes through the tone map like the lamp it came off, a spark behind a pillar is hidden by it, and one
spark does not punch a hole in another. **Unsorted**: addition does not care about order, and at the
opacities dust is drawn at, a wrong order is not something an eye finds.

### Dust is an albedo — found by landing on it

The first landing threw a 0.5-grey cloud onto ground in shadow and it came out as a white glow, several
times brighter than the floor. **A particle's colour means radiance for a spark and albedo for dust**,
and drawn as radiance a grey dust puff is a grey lamp. `ParticleRenderer.matterLight(under:)` lights
matter by the sky's mean radiance plus the sun's irradiance spread over 4π — what an isotropic speck
sends the eye. Computed once per level, and **unshadowed**: dust in the shade of a wall is lit as if in
the open, which is the price of not asking per particle.

## A body with feet (2026-09-10)

`CharacterController` walks across the ground, stands on things, steps up a low ledge, falls off a
high one, jumps, crouches and slides. The sample walks on it; until now it pinned the camera to one
height and the only collision was sideways.

### Extracted, then finished

**The walking half came from a working game.** Movement along the ground plane rather than the look
direction — so aiming at your feet does not slow you and aiming at the sky does not lift you — a
crouch that is a posture with a cost, a slide that carries a sprint's momentum into it, and an eye
that settles over rough ground instead of jittering over every bump. Its numbers came across tuned
in play, and the reasons with them; they are `Tuning`'s defaults.

**What it lacked was anything to stand on but a height function.** Its world was one terrain with
nothing on it, so it had no gravity, no step height and no obstacles. A second consumer with crates
and steps is what showed where the seam was: the ground is a question the controller asks —
`Surroundings`, terrain plus solid boxes — not a function belonging to the game.

The game it came from still has its own copy. Replacing that is the game's work, on its schedule.

### The body is a box

A capsule is the textbook body because it slides round corners by itself. Against a world of
axis-aligned boxes — which is what `Volume.worldBounds` produces and what every solid in a level is —
a box is **exact**: two ranges per axis, no contact normals, no penetration to resolve. It catches on a
corner a capsule would glance off; moving one axis at a time is what takes most of that back, and is
also what makes a wall hit at an angle something you slide along rather than stick to.

A turned crate's world box is larger than the crate, so the player stands a hand's width off its
corners. That is the conservative way round for something you walk into.

### The feet move at once; the eye follows

Collision is resolved against the feet, exactly. Every change in the height under a grounded player —
a step up, a step down, the next bump of a noisy terrain — moves the feet in one step and is eased
into the eye over a moment. That is the whole of what makes stairs read as stairs rather than as a
stutter. **A fall is never eased**: a landing is felt.

### The numbers that are new

| | | why |
|---|---|---|
| step height | 0.45 m | a stair and a low plinth, not a crate — a crate you could walk onto is not cover |
| gravity | 20 m/s² | about twice real; at 9.8 a fall floats, because nothing in a first-person view gives the drop a scale |
| jump | ≈1 m | onto a low wall, not onto a crate |
| coyote time, jump buffer | 0.1 s each | a jump on the last frame of a ledge, or just before landing, is not eaten |

**No jump out of a slide.** A slide is committed, and a jump from sprint speed is the movement tech
the slide's own tuning forbids.

### What the sample found

**A blocked step stopped the player wherever the last whole step ended** — 4 cm short of a crate at a
walk in the first run, and the arithmetic says 15 cm at a sprint, which is a gap you can see when you
turn to look at the wall. A blocked axis now moves up to the face.

### Driven, not just tested

`WINDAGE_SAMPLE_WALK` replays keys for seconds and logs where the feet end each segment, so the claim
can be repeated rather than taken on trust:

```
WINDAGE_SAMPLE_LEVEL=1 WINDAGE_SAMPLE_WALK="d:0.75 w:1.0 w:0.4 wait:1 space:0.05 wait:1.2" swift run WindageSample
```

On the ruins: up four 30 cm steps to **1.20 m**, off the end and down to **0.00**, a jump peaking at
**0.97 m**, and stopped exactly at a crate's face at a walk and at a sprint. A scripted walk ignores
the mouse, because the first one was steered off course by whatever the mouse was doing over the
window.

## Things that hang off other things (2026-09-10)

`TransformHierarchy` is parenting: one transform expressed relative to another, resolved in the right
order, every frame. The sample's figures carry lanterns.

### It is deliberately not a scene graph

A scene graph is an *object model* — nodes that own children and components, are looked up by name,
and become the unit everything else in the engine is written against. That is a decision this engine
has not made; it is in the contested list above and it stays there.

**What a game runs into first is much smaller.** This is a list of attachments and a list of
matrices, owning no objects at all, so the same hierarchy places a drawable, a light and a collision
volume without knowing that any of them exist.

### The interesting case is the one that reaches outside itself

A rig is already a hierarchy and `SkeletonPose` already resolves it in one forward pass. What it
cannot do is reach *out* — and the canonical attachment is exactly that: **a weapon in a hand has for
its parent a joint, inside a pose, that is itself placed by an object's world transform.**

`Attachment.external(_:)` is that made first-class. A node attached externally takes its parent's
world transform from an array handed to `refresh(attachedTo:)`, so its own local transform stays what
it should be — **the grip, authored once**. The alternative is a caller rewriting the node's local
transform every frame, which means keeping the grip somewhere else and doing the multiply by hand.

How many external transforms will arrive is declared when the hierarchy is built, so an
out-of-range attachment is a load-time error. Left to the call site it would be an index read at
sixty hertz, and the cheapest thing to do with a bad one is substitute the identity — which puts the
held object at the world origin, once, in a frame nobody was looking at.

### Parent-first, checked rather than trusted

The same rule `Skeleton` enforces, for the same reason. A hierarchy that violated it would still
produce a picture, with the child one frame behind the parent — which reads as a lag in the animation
rather than as a structural fault.

### Scale is inherited, and that is wrong for a held object

**A rig authored in centimetres hands its wrist a hundredfold scale.** That factor belongs to the arm
— the forearm genuinely is fifty units long in the rig's own space — and it is exactly wrong for
something merely *hung* there: the lantern is drawn at one percent of its size, in a position that is
otherwise correct, which reads as the wrong mesh rather than as the wrong space.

`matrix_without_scale` at the call site rather than a "do not inherit scale" flag inside the
hierarchy, because it is a decision about *what is being attached* and only the caller can see that.

### A joint's frame is not a promise about where the mesh got drawn

The sample figure's bind pose puts its forearm joint 48 cm along the arm, and the arm mesh reaches
74 — so 26 cm along the joint's +X reads as "the hand", and with the arm down it is exactly that.
**Raised, it is not:** the drawn limb stops a hand's length short of where that arithmetic says the
hand went, and a lantern placed there floats above the figure's head.

The gap between a joint's frame and the vertices around it is the asset's business rather than the
engine's. The useful form of the finding is a warning: **a grip derived from bind-pose arithmetic is
a guess.** It is a number set by looking, which is what an attachment point in a tool is for — and
this sample has no tool.

### What it found in the shadow cubes

**The sample assigned cube slices once, at level load.** That is correct for lamps that do not move,
and the first lamp that did move is what exposed it: a cube recorded from where the lamp *was* is a
shadow that lags the hand. Now assigned every frame, which is a sort of five elements.

### Measured

Two frames of the same figure, waving and not: the lantern is at the end of the outstretched arm in
one and raised with it in the other. The lantern lights change **24.5% of the frame** against having
none, and their own cube shadows — the figure's body blocking the lamp in its own hand — a further
**4.7%**.

## Clustered shading (2026-09-10)

**A fragment asks which lights reach *it***, instead of inheriting a list chosen for the whole mesh it
belongs to. `ClusterGrid` cuts the frustum into tiles and depth slices; `ClusteredLights` bins the
scene's lights into the cells they reach, once per frame.

### It exists because per-draw selection had a floor it could not get under

`LightSet` picks a few lights per object — correct, cheap, and **only as good as the draws are
small**. The section below is the day that stopped being true: the sample's ground is one
eight-hundred-metre quad, so one draw got four lights for an entire level. No budget and no ordering
rule fixes that, because the object is the wrong unit to choose lights for.

A cluster is the right unit. It is a small box of the world, so the lights reaching it are few by
construction, and a fragment belongs to exactly one.

### Three decisions worth the words

- **Slices are exponential.** Cut the depth evenly and the near slices are microscopic while the far
  ones are hundreds of metres deep — a perspective frustum's cross-section grows with distance, so an
  even cut puts almost every cluster where there is almost no screen. Slicing by the logarithm makes
  each cluster roughly cubic, which is what keeps the count manageable.
- **Clustering needs a finite far distance, and this engine's projection has none.** The infinite far
  plane is deliberate — no view distance to tune, nothing to clip at range — so `ClusterGrid` carries
  its own `lightRange`. That is honest rather than awkward: a punctual light has a finite range by
  definition, so there is a distance past which none of them reaches, and that is the number.
- **An offset and a count per cluster, not a fixed list each.** A fixed list means every cluster pays
  for the worst one — three thousand cells times a budget of eight is twenty-four thousand entries,
  nearly all empty. A range into a shared list costs an empty cluster nothing and puts no ceiling on
  a full one.

**Binned on the CPU**, for the same reason `EnvironmentMap` prefilters there: the slicing, the cluster
geometry and the sphere test are exactly the arithmetic that produces a plausible picture when it is
wrong, and this repository's rule is that such halves want tests. The assignment walks *lights* rather
than clusters — a lamp touches the few slices its range spans and the tiles its sphere covers, so
lighting one corner of a room costs a handful of tests rather than a sweep of the grid.

### Measured

Sixty-four lights in a test scene: **busiest cluster 9, average 2.2**. The sample's ruins: ten lights,
**busiest 6**. That ratio is the point — the worst fragment loops nine times instead of sixty-four,
and the typical one twice.

### The bug that made it render as nothing at all

The first working version drew **no local light whatsoever**, and the CPU side was provably right: six
lights, 222 cluster entries, 173 cells occupied. Printing those numbers is what turned an open-ended
hunt into a two-line one — the fault had to be between the buffer and the shader.

**A `SIMD3<Float>` used as padding has 16-byte alignment in Swift; the shader's three trailing scalars
have four.** The struct came out 48 bytes on one side and 32 on the other, so every field after it in
the frame uniforms was read from the wrong address. It compiled, it ran, and it looked exactly like a
feature nobody had wired up.

> **A struct that agrees on its fields and disagrees on its padding is the worst kind of mismatch**,
> and it is the third layout question in this file — after the skinned vertex layout's `float4`
> alignment and the tone-map uniform's packing. There is a test pinning size, stride *and* alignment
> now, because the first two only catch half of it.

### The finding that was not about spot lights at all

The sample's first spot lit nothing, and **over-subscription was not why**: `isOverSubscribed`
reported the level clean at every point a player stands. The cause is that **the ground is one
800-metre quad**. Per-draw selection gives that single draw four lights for the whole level, so the
objective lamps standing 0.6 m above it beat a spot 5 m up, and the spot never reached the shader at
all.

**Per-draw light selection is only as good as the draws are small.** No budget and no ordering rule
fixes an oversized one; that is what clustered and tiled shading exist for. The sample aims its spot
at a pillar instead — a normal-sized draw — and the limitation is written down rather than tuned
around.

> **The check earned its place by being *negative*.** Having a tool that said "not that" is what
> stopped an afternoon of adjusting light intensities in search of a problem that was never there.

### Four smaller ones

- **Selection is per draw, against the box's nearest point rather than its centre.** A long wall whose
  middle is out of a lamp's reach still has an end inside it, and lighting a whole draw by its centre
  is how one end of a corridor goes dark while the lamp is plainly shining on it.
- **The falloff needs a floor in the denominator.** A fragment exactly at a lamp's position is a
  division by zero, and the pixel that produces is not "very bright" — it is `NaN`, which draws black.
- **Local lights cast no shadows.** There is one shadow map and the sun has it, so a lamp reaches
  through a wall. A real limitation, and the reason the sample's ranges are short: it is only obvious
  when a lamp reaches far enough for it to be.
- **A lamp in daylight does almost nothing**, which is correct and is why the sunlit level has none.

### Two things in the level and the sample

**Lights are a named list in the level file**, not markers with values on them. A marker is a *place*
the game interprets and its `values` are scalars; a light is a position, a colour, a brightness and a
range, and five loose numbers under a marker means nothing checks they belong together.

**`Level` decodes explicitly and tolerantly now.** Every field but the version is optional, because
the synthesised decoder throws on a missing key — so adding `lights` to the type would have refused
every level already written, including any a player edited and saved into Application Support. The
same reasoning as the sky's optional fields, applied one level up.

## Emission (2026-09-10)

The last material slot with nothing reading it. Every slot `Material` carries now reaches a pixel.

### Three things about emission itself

- **It is added, not lit.** Nothing multiplies it: not the sun's angle, not the shadow map, not the
  ambient occlusion. A glowing seam that dimmed when a shadow crossed it would be a lamp that goes out
  when you stand in front of it.
- **A whole object that emits looks flat, and correctly so.** An emitting surface has no light
  direction, so there is nothing for shading to vary. Real emissive surfaces are a strip or a panel,
  confined by a **map** — which is exactly what an OBJ crate cannot have, so the sample's objectives
  glow gently enough that the planks and the sun still carry their shape.
- **A PNG cannot hold a value above 1**, so an emissive map alone is never brighter than white, and a
  seam that is exactly white does not read as lit. How much brighter is a look decision, so it is the
  game's multiplier rather than the texture's.

### The game owns the value, not the material times the game

Multiplying them was the first attempt and it **silently produced nothing**: an OBJ material's
emission is always zero, so a crate the game wanted lit came out as zero times whatever it asked for.
The material's emission is a *default* the caller may use, override or ignore, because only the caller
knows whether this surface is powered right now.

**The sample's objectives emit instead of swapping colour.** They used to change albedo, which is a
colour a surface *is* — so a collected crate and an uncollected one differed the way two paints
differ. Emission is light the surface makes; it survives being in shadow, and it goes above 1 so the
tone map has somewhere to roll it.

### What OBJ carries, measured: nothing

`Ke` and `map_Ke` are both read and discarded — the emission property comes back as an **always-black
`.color`** whatever the file says. Emission joins metalness and roughness maps as USD-only here.
`map_Ka` does arrive as an emission *texture*, which is the ambient map landing on the emission
semantic; a legacy quirk rather than a path worth relying on.

### The identity-scalar rule, third instance

A file that connects `emissiveColor` to a texture supplies no scalar for it, so the field kept
`Material`'s default of zero and multiplied the map away — the same fault as metalness and as the 0.18
base colour before it. **Three slots needed this for the same reason, which is what makes it a rule
rather than three fixes**: a slot with a map takes the identity for the operation it is used in.

## Occlusion, roughness and metalness from a texture (2026-09-10)

The last material slots with nothing behind them. They are each a single number, so they are packed
into one RGB texture — **R occlusion, G roughness, B metalness**, glTF's packing — which is a third of
the memory, a third of the bindings and one sample instead of three.

### What Model I/O carries, measured

- **USD carries all four.** Metalness, roughness, occlusion and emissive arrive as textures on the
  right semantics.
- **It drops which channel each reads.** A `UsdPreviewSurface` with roughness connected to a texture's
  `.g` and metalness to its `.b` arrives as two properties naming the same file, with nothing to
  distinguish them. So the convention is assumed, and `TextureSlot.packedChannel` is where it is
  written down rather than guessed at each call site.

  **The same channel is right for an unpacked map**, which is why the convention survives contact with
  reality: a standalone roughness map is greyscale, so its green channel is its value. Reading a fixed
  channel works for both, and that is why glTF fixed one.
- **OBJ carries none of it.** `map_Pr` and `map_Pm` are read and discarded, exactly like the `Pr`/`Pm`
  scalars before them. What *does* arrive is `map_Ns` as a **`specularExponent` texture**, and
  `map_Ka` as emission — so an OBJ can vary shininess across a surface, in exponents rather than in
  roughness. **Not wired up**: it is a differently shaped quantity needing its own per-texel
  conversion, and nothing needs it. Recorded because the next person will look for it.

### The 0.18 trap, in a second place, nearly shipped

**A file that connects `metallic` to a texture supplies no scalar for it at all.** So the field kept
whatever `Material` initialises it to — and `metallic` initialises to 0. Multiplied by the map, that
is zero everywhere: a metal character renders as a dielectric one, and nothing says why.

It was caught by looking at the figure and asking why it seemed less metallic than before, then
measuring what the material actually reported. **A slot with a map takes the identity for the
operation it is used in** — white for a tint, 1 for a multiplied factor — which is the same rule the
base-colour case already needed and which is now applied in both places.

### Two decisions in the shader

**White is exactly the right fallback**, because the three are multiplied: a surface with no map keeps
its material's own values untouched. And **occlusion applies to the ambient terms only** — it stands
for light a crevice does not receive from its surroundings, and applying it to the sun as well would
darken a surface the sun is plainly shining into, which is a shadow the shadow map already has an
opinion about.

## Image-based lighting (2026-09-10)

A surface takes light from its **whole** environment, and how it takes it depends on how rough it is:
a mirror reflects one direction, chalk gathers the entire hemisphere. Doing that integral per pixel
per frame is not affordable, so `EnvironmentMap` precomputes it twice.

| | what it holds |
|---|---|
| `specular` | The environment convolved with the GGX lobe, **one roughness per mip**. Mip 0 is the environment itself; the last is nearly uniform. A shader samples it at `roughness × (mips − 1)`. |
| `irradiance` | The environment convolved with a cosine lobe — what a diffuse surface facing a direction receives. 16×16, because a cosine convolution is a very heavy blur and the result genuinely has nothing finer in it. |

### Built on the CPU, and that is the argument

**Every part of this that can be *wrong* is arithmetic**: cube face projection, importance sampling,
two convolutions. This repository's rule is that such halves want tests and tests should not want a
GPU — a compute prefilter would be faster and would put all of it somewhere only a screenshot could
check. Here they are ordinary functions with ordinary tests, and three of those tests failed the first
time they ran.

**92 ms in a release build; 2.6 s in a debug one.** The debug figure is what somebody running
`swift run WindageSample` actually sees, and it is the honest price. The trade is also stated: this
prefilters a **function**, not a photograph. An engine that wants to prefilter a captured HDR panorama
will want the compute version, and this maths is what that would be written against.

### Three things the tests found

- **Fireflies at high roughness.** At a fixed 96 samples the chain stops getting blurrier around
  roughness 0.6 and starts getting *brighter* again — 0.72 rising to 1.67 at roughness 1.0, where a
  converged reference falls to 0.60. A wide lobe over a small, very bright sun means the estimate is
  decided by whether any sample happened to land on the sun, and the rough mips come out blotched.

  **The fix is free.** Quadrupling the sample count per mip exactly cancels the mip chain: each level
  has a quarter of the texels, so the cost per level is flat, and the roughest mips — which need the
  samples most — are the smallest and cheapest place to spend them.
- **The irradiance integral was out by a factor of π.** It is a Riemann sum over `dφ dθ`, so each term
  is worth `step²` of solid-angle measure; dividing by the sample count gives an *average* rather than
  an integral. Caught by asserting the one value that is known in closed form: a uniform sky of
  radiance L integrates to exactly πL.
- **The lower hemisphere must not be black.** A surface facing down is lit by the ground, and a black
  ground is the single commonest reason an image-based lit object looks like it is floating in a void.

### Two things in the sample

**The sky is drawn from the same cube that surfaces reflect.** A flat clear colour behind a metal
object reflecting a sky with a sun in it is two skies in one picture, and that is among the first
things an eye finds wrong with a render.

**Irradiance is not radiance.** The cube holds light integrated over the hemisphere; Lambert's BRDF is
`albedo / π`, and skipping the division makes every ambient-lit surface π times too bright.

## A level says what sky it is under (2026-09-10)

A level said where the sun was — `sunPitch` and `sunYaw` in `settings` — and everything else about
the light was hard-coded in the game. So two levels could differ in the sun's angle and in nothing
else: not the colour of the sky, not how much light came from it, not whether it was overcast.

`Level.sky` is a `ProceduralSky` now, written as its own block.

### A named thing, not more scalars

`settings` is `[String: Double]` on purpose and should stay that way. A sky is three colours, two
angles and a sun size; flattened into scalars that is fifteen keys with no structure, no way to say a
colour is a colour, and nothing to stop `skyZenithB` being set while `skyZenithG` is forgotten.

**Angles rather than a vector, because a person writes this.** `sunPitch 34, sunYaw 295` is something
you can picture and adjust; `(-0.75, 0.56, 0.35)` is three numbers that have to stay normalised and
that nobody can read. The conversion moved into the engine at the same time — it lived in a game's
source while one game read a sun out of a level, and the moment the sky itself is *in* the file, the
thing that reads it and the thing that lights with it have to agree.

**Every key optional.** A level file is edited by hand as often as by a tool, so a sky naming only
`sunPitch` is legal and useful. Requiring all seven fields makes the simplest edit the longest one.

### Radiance is not irradiance, and the two differ by about 130×

**The one that would have been a silent disaster.** `sunRadiance` is how bright the sun's disc *is*,
looked at — a large number, because a sun reflected in polished metal has to read as a sun. What a
surface *receives* is that radiance times the solid angle the disc subtends, and a 0.05 radian disc
subtends 0.0079 steradians. Use one as the other and the scene is a hundred and thirty times too
bright.

`sunIrradiance` derives it. That is what stops the sun you see and the sun that lights the scene from
being two numbers that can drift apart, and it makes a physically true thing fall out for nothing:
**a wider sun is both softer and stronger**, because it is more sky.

> The default `sunRadiance` moved from 28 to 330 as a consequence. The old figure was picked to look
> right in a reflection, at a time when nothing derived a light from it.

### The migration is in the engine, not in each game

Levels already exist on disk saying `sunPitch` and `sunYaw` in `settings` — including any a player
edited and saved, which live in Application Support and cannot be rewritten from here. Those two keys
still mean exactly what they meant, so `resolvedSky` reads them when there is no `sky` block. Doing
that in `Level` is the difference between one migration and one per consumer.

### Two things found doing it

- **Overcast is dimmer, not just a dimmer sun.** The first attempt at the ruins' sky kept the bright
  blue-sky values and only dimmed the sun; it lit everything flatly and washed the stone out to
  near-white. An overcast scene is darker *and* flatter, and the sky is most of both.
- **Adding a stored property to `Level` segfaulted a test in a different target.** Not a fault in the
  new code: `WindageSampleCore` was still linked against the old struct layout, so a decoded `Level`
  read a garbage array and `isEmpty` crashed. `swift test` reported `signal code 11` with no summary,
  and the crash log pointed at an assertion that had nothing to do with the change. **Delete the
  build directory when a type shared across targets gains a field** — the same family as the note
  about moving a package invalidating its cache.

## Tone mapping (2026-09-10)

**Shading does not stop at 1.** A sunlit surface with a specular highlight on it is genuinely
brighter than white paper, and once ambient, direct and specular are summed the result routinely
passes 1.0 — the sample's own lit faces reach about 1.13 before anything shiny is involved. Written
straight to an 8-bit display buffer, every one of those clips to the same white, so the brightest and
most informative part of the image becomes the part carrying no information.

That is not a missing polish pass. **A renderer that produces HDR and writes it to an LDR target is
incomplete**, and the symptom — blown highlights, a plasticky look, colour sliding to white as it
brightens — reads as bad art rather than as a missing stage.

### The shape of it

The frame is two passes now. The scene draws into `sceneColorPixelFormat` — `rgba16Float`, half
float because it holds far more range than a frame needs at half the bandwidth of full float. Then a
full-screen triangle reads it, applies exposure and a curve, and writes the drawable, with the
interface drawn into that same second pass so it never sees the curve.

**A triangle rather than a quad, and no vertex buffer at all.** Two triangles meeting across the
screen have a diagonal seam where the rasteriser shades the same pixels twice; one oversized triangle
covers the screen with no seam and is generated from `vertex_id`, so there is nothing to allocate,
bind or keep resident.

**The scene target cannot be memoryless**, unlike the depth buffer beside it: the tone map pass reads
it after the scene pass has ended, so it has to survive into main memory.

> **Upgrading past 0.3.0: a pipeline with the wrong format renders static, not an error.** Metal 4
> builds pipelines apart from passes, so a scene pipeline still declaring `colorPixelFormat` is
> accepted and writes eight-bit pixels into a sixteen-bit-float target — magenta and blue noise,
> nothing logged. Measured on a real consumer, 2026-09-11. Any pipeline drawn in `encode` wants
> `sceneColorPixelFormat`; any drawn in `encodeHUD` wants `colorPixelFormat`; anything drawn into a
> target of the game's own wants that target's format. **And a game that tone maps in its own shader
> sets `toneMapping = .off`**, which is a pass-through — otherwise its picture meets a second curve.

### Curves

| | |
|---|---|
| `clamp` | Not a curve — what a renderer does with no tone mapping. Kept so the difference can be looked at rather than argued about. |
| `reinhard` | Gentlest and most washed out. Scales all three channels equally, so hue is preserved exactly, which is either the virtue or the problem. |
| `aces` | **The default.** Narkowicz's six-constant fit of the ACES curve. Rolls the shoulder off gradually and lets very bright colours desaturate towards white, which is what film does and what the eye reads as bright rather than clipped. |

**Exposure is in stops**, photographic, because that is how brightness is actually reasoned about and
because the useful range is small and symmetric — roughly −4 to +4, where a multiplier's is 0.06 to
16 and reads as arbitrary.

### Two things worth knowing

- **ACES lifts midtones by about a third.** Middle grey 0.18 maps to 0.267. A scene whose values were
  chosen before there was a curve comes out *brighter* when one is switched on, not darker, and looks
  washed until its exposure is set. The sample sits at −0.5 stops for exactly that reason; a game
  authored against the curve from the start would sit at zero.
- **The fit is not asymptotic.** It passes 1 at an input of about 6.6, so the clamp after it is doing
  real work rather than guarding an edge case. Both copies of the curve clamp.

### What is deliberately not here

**No auto-exposure.** Metering the frame, deciding what "correctly exposed" means for a game, and
smoothing adaptation over time are genuinely contested — every engine does it differently and the
game's needs decide it. **No bloom, no colour grading, no vignette**: those are a look. This is the
part without which there is no picture.

> **Two copies of one formula, and it is written down as a risk.** `ToneMapping.apply(_:)` is the
> definition and `ToneMapShaders.metal` transcribes it. The alternative is no Swift version, which
> means the curve cannot be tested at all without a GPU and a way to read pixels back — so the tests
> pin specific input-output pairs instead, and a change to one copy and not the other shows up in the
> numbers rather than only on screen.

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

## Conventions

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

## Versioning (2026-09-09)

**`0.1.0` is the first version with a number**, and everything before it had nothing for a version to
mean: the engine was a folder inside a studio repository, consumed by one game developed alongside
it, where "the current commit" was always the answer. It stopped being that the day it got its own
repository, and a dependency by URL is unusable without tags.

### The number lives in one place

`Engine.semanticVersion`. The window title formats it; `CHANGELOG.md` records it; a **test fails if
they disagree**. A version that also lives in a build setting and a document is a version that will
eventually contradict itself, and it will do so on somebody else's machine.

### What a bump promises before 1.0

Semantic Versioning gives `0.x` no compatibility guarantee at all, which is honest and useless to
depend on. This repository narrows it to what everybody actually does before 1.0:

| | means |
|---|---|
| **minor** — 0.1 → 0.2 | Something changed that can break a build: a signature, a type, a removed declaration, or a default that alters behaviour. |
| **patch** — 0.1.0 → 0.1.1 | Additions and fixes only. What compiled still compiles and still does the same thing. |

So a consumer pins `.upToNextMinor(from: "0.1.0")` and gets fixes without surprises. After 1.0 this
becomes ordinary Semantic Versioning, with the major carrying the breakage.

> **The conventions count as API, even though they are not signatures.** Reversed-Z, the depth clear
> value, and the vertex-descriptor contract with `MeshLoader` are all things a consumer builds
> against; change one and their game compiles and then draws nothing, which is worse than a compile
> error. Those move the **minor**.

### The changelog is not optional, and a test is what makes that true

Nothing in a build cares whether `CHANGELOG.md` was updated, so a changelog left to discipline falls
behind — and one that has fallen behind is worse than none, because a reader believes it.
`ChangelogTests` checks that its newest entry is the version the engine reports, that entries are in
order, and that an `Unreleased` section exists to write into. Releasing without writing the entry
fails the suite.

**Entries are written for somebody upgrading**, which is why *Changed* and *Removed* carry the weight.
A new type costs a reader nothing; a changed one costs them a build.

### Releasing

1. Move `Unreleased` into a dated version heading in `CHANGELOG.md`.
2. Bump `Engine.semanticVersion` to match — the test will tell you if you forget.
3. `swift test`, then tag: **`git tag 0.2.0`**, no `v` prefix, which is what SwiftPM resolves and
   what `SemanticVersion.init(_:)` deliberately refuses to parse leniently.

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
- **No art dependency.** Its static meshes are hand-written OBJ files of a box, a taller box and a
  ground quad; its one rigged character is written by `Tools/make_sample_figure.py`; and its four
  textures are drawn by `Tools/make_sample_textures.py`, which writes PNGs with nothing but the
  standard library. A sample that needs an asset pack cannot be run by whoever just cloned this.
- **Surfaces that come from the files, not from code.** `box.obj` names `crate.png` through its
  `.mtl` and the figure names `figure.png` through a `UsdPreviewSurface` — two different formats
  through one code path, which is the only way that path gets tested. UVs are in metres throughout,
  so a crate and a tower are textured at the same scale.
- **Animated characters, from the level file.** Figures stand where a `figure` marker puts them,
  idling, and cross-fade into a wave as the player comes near — which is what proves `SkeletonPose`
  blends rather than switches. They cast skinned shadows through the same cascades as everything
  else, because a character lit by the scene that casts nothing reads as floating.
- **No Xcode project.** `swift run WindageSample`. Anything requiring a project is a thing the reader
  must own before they can start.
- **No cleverness.** One directional light, no textures. A sample with impressive rendering teaches
  the reader about the rendering. It does draw **cascaded shadows**, because a sample with no
  shadows cannot show that the shadow maths in this package works — see below. Its specular is
  Blinn-Phong rather than a PBR lobe, for the same reason: it is there to show that a material's
  roughness arrives and does something.

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

### The selection's lamp (0.8.2)

`setLight(_:)` gives the selection a lamp, replaces it or takes it away; `raiseLight(by:)` and
`brightenLight(by:)` set the two things a person adjusts by eye; `add(mesh:at:tags:light:)` drops in
something already lit. In the sample: **l** lamp on and off, **[ ]** lower and raise it, **, .** dimmer
and brighter.

- **The lamp is the placement's** (``Level/Placement/light``), so moving, turning, copying and deleting
  already carried it; what the editor lacked was a way to give one.
- **Raised in metres of the world**, whatever the placement's scale — the offset scales with the
  placement, so on a crate at scale 2 the offset moves half as far. A key that moved lamps different
  amounts on different things would be one nobody could judge.
- **Brightened in thirds of a stop**, three presses to double: brightness is judged in ratios, and a
  fixed +5 is a leap on a candle and nothing on a floodlight. Clamped above zero, for the reason scale
  is — a lamp dimmed to nothing is still there, with no way to see it.
- **An edit that changes nothing records nothing** — brightening a crate with no lamp is not an undo
  step and an unsaved change.

**Driven in the running sample**: pick a plain crate at scale 2, **l**, **]** twice, **.** three times.
The log, read through the level's own resolution, reported the lamp at 3.20 m, then 3.30 and 3.40,
brightening 45 → 56.7 → 71.4 → 90.0 — each the prediction. A frame difference against the same view
without it shows the new pool of light on the ground under the crate, with the green crates' shadows
cut out of it.

### Adding more of what a level already has (0.9.2)

`Level.kinds` is one of each kind of thing in a level — two placements are the same kind when all but
*where* they are matches: mesh, scale, anchor, tags, lamp, surface. `LevelEditor.add(_:at:)` drops
another of a kind at a point on the ground, bringing everything but the place: a brazier arrives lit,
solid and made of metal, where `add(mesh:at:)` — which knows a name and nothing else — would bring a
cold, walk-through one. **The height comes with the kind**, because under an anchor `y` is part of what
a thing is; `x`, `z` and the yaw are only where the first one happened to be put.

**Not prefabs**: a prefab is authored once and instanced; this is a question asked of a level that
already exists, and needs no format of its own. A lamp is part of a kind, so the ruins' two braziers —
one orange at 60, one yellow at 55 — are two kinds, which is correct and which the palette has to say
("brazier with a lamp at 60").

In the sample, **t** steps through the kinds and **i** drops one **where the crosshair meets the
ground** — not on whatever the crosshair touches first, which would put a crate inside a pillar. The
floor and objective crates are left out: an objective is a crate *and* a marker the run counts.
**Driven**: a brazier and a crate landed at the crosshair's ground point to the centimetre, the
brazier's lamp 1.8 m over it, lighting the ground with embers rising.

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

**The pass is `ShadowMap` now** — see the section below on why it stopped waiting.

> **The sun moved, and it is level data, not code.** Both sample levels had the sun behind the
> camera, which is invisible without shadows and useless with them: every shadow falls away from the
> viewer and hides behind its own caster. A side sun lights the faces the player is looking at *and*
> throws its shadows across them. That is a `sunYaw` in `courtyard.json`, which is the point of
> levels being files.

## Extracting the shadow pass, and the bad reason it waited (2026-09-09)

`ShadowMap` owns the pass: the depth texture array, the reversed-Z depth state, the front-face cull,
the slope-scaled bias, the per-cascade pass descriptors and the encoder loop. The game keeps its
**pipelines**, because those are compiled against its own shaders and its own vertex descriptor and
cannot come from anywhere else.

### It was parked for a bad reason, and it is worth writing down which

The note here used to say the seam was *"a question a third implementation answers better than a
second one guessing"*. **That was wrong twice over.**

It was wrong about the problem: this was never speculative work. The code was already written,
working and tested — **twice**, in two repositories, where a fix to one does not reach the other.
That is a defect, not a shape waiting to be discovered, and "wait for a third" is a rule that lets a
defect age.

And it was wrong about the evidence. A third copy would have been *more of the same* evidence about a
question that had a cheaper answer available. What actually settled it was **teaching the sample's
own pass to draw skinned meshes**: a second vertex layout inside one consumer forced exactly the
abstraction that two consumers had only been hinting at. Two things vary and no more — the **vertex
layout** and the **per-object bindings** — and both fit in a `Batch`.

> **The general lesson, since this is the second time the "wait for a consumer" rule has been too
> blunt.** It protects against *designing* something with no evidence. It says nothing about code
> that already exists in two places, and reaching for it there is how duplication gets a
> justification.

### What the split actually is

| the engine's | the game's |
|---|---|
| the depth texture array and its per-cascade slices | the **pipelines**: a vertex function and a vertex descriptor only the game has |
| the reversed-Z depth state, front-face cull, slope-scaled bias | the **uniform layout** — what a `model` matrix sits inside is the game's struct |
| the per-cascade pass descriptors and the encoder loop | the joint palette, where there is one |
| the light matrices, per frame in flight | the cascade **numbers** — a courtyard and a sniper range disagree |

**A `Batch` is a pipeline plus closures**, not arrays: a game's drawables are its own, and an array
here would mean building a copy of the scene every frame to hand over. Batches rather than one loop
because a skinned mesh has a different vertex layout, so state changes once per kind rather than once
per object.

### Two things that were comments and are now API

- **`ShadowMap.pipelineDescriptor(vertexFunction:vertexDescriptor:label:)`.** Three things have to be
  right for a shadow pipeline and none is obvious: no fragment function and no colour attachment,
  one raster sample, and a depth format matching the texture. The game supplies the two things the
  engine cannot know and gets the rest correct by construction — the same argument as reversed-Z.
- **`ShadowMap.BufferIndex`.** Where the argument table puts the uniforms, the light matrix and the
  joint palette. A mismatch here does not fail; it reads a matrix out of the wrong buffer and records
  the scene from nowhere.

**`constantDepthBias` and `slopeScaledDepthBias` moved onto `ShadowCascades`**, beside `biasScales`,
because the three numbers are one tuning. Both are **negative**: under reversed-Z, pushing a recorded
occluder away from the light is a *smaller* value, so the sign is the opposite of every textbook, and
getting it wrong doubles the acne rather than removing it — which reads as the bias doing nothing.

### What did not move

`SampleShadowMap.swift` is gone; what is left in the sample is two pipelines and four cascade numbers.
**A game with its own copy is not obliged to change**, and replacing it is that game's work on that
game's schedule — this repository does not wait on it.

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
