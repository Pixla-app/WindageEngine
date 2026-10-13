---
title: Sky and environment
description: A ProceduralSky as radiance by direction, prefiltered into an EnvironmentMap for image-based lighting, and how the sample draws and lights with both.
---
`ProceduralSky` describes a sky as radiance arriving from each direction: a zenith, a horizon, a ground and a sun disc. `EnvironmentMap` prefilters that sky into two cube maps, so a shader can look up reflections and ambient light. Both come from the same source, so the sun you see, the sun that lights the scene and the sun that metal reflects stay the same sun.

## ProceduralSky {#procedural-sky}

```swift
public init(zenith: SIMD3<Float> = SIMD3(0.28, 0.45, 0.85),
            horizon: SIMD3<Float> = SIMD3(0.62, 0.72, 0.88),
            ground: SIMD3<Float> = SIMD3(0.22, 0.21, 0.18),
            sunPitchDegrees: Float,
            sunYawDegrees: Float,
            sunRadiance: SIMD3<Float> = SIMD3(330, 310, 270),
            sunAngularRadius: Float = 0.05)
```

A second initializer takes `sunDirection:` in place of the two angles. All values are **linear radiance, not colors**. The sun is thousands of times brighter than the sky around it, and the [tone map](tone-mapping.html) brings that range down to something a display can show.

- **`ground` shouldn't be black.** Surfaces facing down are lit by the ground. A black lower hemisphere is the most common reason an object lit by its environment looks like it's floating in a void.
- **`sunAngularRadius`** is in radians. The real sun is about 0.00465. A wider disc gives a softer reflection.
- **`sunPitchDegrees` and `sunYawDegrees`** read and write `sunDirection` as angles, which are easier to picture and adjust than a vector. `ProceduralSky.direction(pitchDegrees:yawDegrees:)` does the same conversion for any code that needs it.
- **`sunDirection`** is normalized however it is set; a zero vector points straight up.
- **`radiance(inDirection:)`** returns the radiance arriving from any direction, which doesn't need to be normalized.
- **`matterLight`** is the light a white speck of dust scatters under this sky — see [particles](particles.html).

### Radiance is not irradiance {#irradiance}

`sunRadiance` is how bright the disc looks when you look straight at it. A surface facing the sun receives that radiance multiplied by the small solid angle the disc covers. **Use `sunIrradiance` as your directional light's intensity**, never `sunRadiance`. With the default 0.05-radian disc, the two differ by about 130×. Because the irradiance is derived from the disc, a wider sun comes out both softer and stronger.

## A level's sky {#level}

`Level.sky` is an optional `ProceduralSky`, saved as its own block in the [level file](levels.html). Every key is optional, so a block that names only `sunPitch` is valid. This is the sample's dusk ruins:

```json
"sky" : {
  "zenith" : [0.15, 0.17, 0.21],
  "horizon" : [0.3, 0.28, 0.26],
  "ground" : [0.1, 0.09, 0.07],
  "sunPitch" : 11,
  "sunYaw" : 240,
  "sunRadiance" : [38, 24, 13],
  "sunAngularRadius" : 0.1
}
```

Read it through `Level.resolvedSky`. That property also handles older files that set the sun with `sunPitch` and `sunYaw` in `settings` and have no `sky` block. With neither, it returns the default `ProceduralSky()`.

An overcast level is darker and flatter overall, not just lit by a dimmer sun. The ruins' first sky kept bright blue-sky values and only dimmed the sun, and the stone washed out to near-white.

## EnvironmentMap {#environment-map}

```swift
public init(device: MTLDevice,
            sky: ProceduralSky,
            size: Int = 128,
            irradianceSize: Int = 16) throws
```

It throws an `EnvironmentMapError` naming the cube the device would not create: `.specularTexture` or `.irradianceTexture`.

| Texture | What it holds |
| --- | --- |
| `specular` | The sky convolved with the GGX lobe, **one roughness per mip**. Mip 0 is the sky itself, and the last mip is nearly uniform. Sample it at `roughness * Float(specularMipCount - 1)`. |
| `irradiance` | The sky convolved with a cosine lobe: what a diffuse surface facing each direction receives. Sixteen texels a side is enough, because the result has almost no detail. |

Add `allocations` to your residency set. Building a map is a load-time cost, not a per-frame one: 92 ms in a release build and 2.6 s in a debug build. `EnvironmentMap` is `nonisolated` and `Sendable`, so a game that would rather not spend that on the main actor builds it in a `Task.detached` and hands the map back.

### Built on the CPU {#cpu}

The prefilter runs on the CPU deliberately. The parts that can be wrong are the cube face directions, the importance sampling and two convolutions, and as CPU code they have tests that need no GPU. Those tests caught three bugs: fireflies at high roughness, fixed by quadrupling the sample count per mip; an irradiance integral off by a factor of π; and a black lower hemisphere. One limitation is stated plainly: this prefilters a **function**, not a photograph. It can't load a captured HDR panorama.

## How the sample uses them {#sample}

The sample rebuilds its environment whenever a level loads, from that level's sky:

```swift
let built: EnvironmentMap
do {
    built = try EnvironmentMap(device: engine.device, sky: level.resolvedSky)
} catch {
    print("WindageSample: no environment — metal will have nothing to reflect (\(error))")
    return
}
if let previous = environment {
    engine.residencySet.removeAllocations(previous.allocations)
}
environment = built
engine.residencySet.addAllocations(built.allocations)
engine.commitResidency()
```

It takes its sun from the same sky: `level.resolvedSky.sunDirection` for direction and cascades, and `level.resolvedSky.sunIrradiance` for intensity. If the environment were lit from one direction and the scene from another, it would look like a shading bug.

**The background is drawn from the same cube that surfaces reflect.** The sample's sky pass is a full-screen triangle that turns each pixel into a ray and samples mip 0 of `specular`. A flat clear color behind a metal object that reflects a sky with a sun in it would show two different skies in one picture.

**Divide irradiance by π.** The irradiance cube holds light integrated over the hemisphere, and Lambert's BRDF is `albedo / π`. Skip the division and every surface lit by ambient light is π times too bright.

The sky's `matterLight` lights dust. See [particles](particles.html).
