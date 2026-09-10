# Changelog

Every release of Windage Engine, newest first. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) under the pre-1.0 rules set out in
`README.md` § "Versioning".

**Written for somebody upgrading**, which means the entries that matter most are under *Changed* and
*Removed*. A new type costs a reader nothing; a changed one costs them a build.

## [Unreleased]

Nothing yet.

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
