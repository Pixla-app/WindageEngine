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
clips, cross-fading and a joint palette, loaded from USD** · **materials and textures — the
metallic-roughness set read from a file, and a caching texture store that knows colour from
numbers** · maths · bounding boxes, volumes
and one segment hit test · frustum culling · shadow cascade arithmetic · a versioned level format
with an editor · a HUD renderer with a font atlas · positional audio · save persistence · a shader
library that survives having no Xcode · and a complete sample game exercising all of it.

### Missing, and the order it is worth building in

**Settled shape — build these; no game has to ask.**

| | why it is next, or not |
|---|---|
| ~~**Skinned animation**~~ | **Done 2026-09-09.** `Skeleton`, `AnimationClip`, `SkeletonPose` and `RigLoader`; the sample's figures are posed, cross-faded and shadowed. See below. |
| **A transform hierarchy** | Not a scene graph — just parenting, so a thing can be attached to a joint or to another thing. **Half arrived with animation**: a rig *is* a hierarchy, and `SkeletonPose.modelTransform(ofJoint:)` is where a weapon hangs off a hand. What is still missing is parenting between *objects*. |
| **Animation state** | What plays next, and what interrupts what. The engine cross-fades two clips; deciding *which two* is a game's job today, and there is no evidence yet about where the line sits. Wait for a game to have more than two clips. |
| **The shadow pass** | The maths is here; the pass is written twice outside. Extract when a third consumer says what the seam is. |
| ~~**Materials and a texture path**~~ | **Done 2026-09-09.** `Material`, `TextureSlot`, `TextureStore`; `MeshLoader` returns a material per submesh, and the sample textures every surface from the file that names it. See below. |
| **Normal maps in a consumer** | The slot, the sRGB rule and the flat-normal fallback are all here; nothing has bound one yet, because that needs tangents in the vertex layout and a mesh worth mapping. The next real asset forces it. |
| **Post-processing** | Tone mapping is per-game today, and it must not be: shading past 1.0 and writing it straight makes every lit surface clip identically. An engine that renders HDR owes a curve. |
| **Particles** | Written outside already. A settled shape — pool, emitter, camera-facing quads, deterministic spread. |
| **A character controller** | Walking, ground-following, step height, crouch, slide. Written outside already, and every first-person game rewrites it. |
| **LOD and instancing** | The next thing that binds once a scene is larger than one valley. |
| **Input rebinding, settings persistence** | Small, unglamorous, and the difference between a demo and something shippable. |

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
