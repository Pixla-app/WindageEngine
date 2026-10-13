---
title: Clustered lights
description: Point and spot lights with PunctualLight, checking a level's light budget with LightSet, and per-fragment selection with ClusterGrid and ClusteredLights.
---
The sun and an environment map light an outdoor scene well, but they do nothing useful indoors: the sun doesn't reach inside, and sky-colored ambient lights a cellar as if the sky were overhead. A `PunctualLight` is a lamp. `ClusteredLights` lets each fragment find the few lamps that reach it, and `LightSet` checks that a level hasn't crowded too many into one place.

## PunctualLight {#punctual}

```swift
public init(position: SIMD3<Float>,
            color: SIMD3<Float>,
            range: Float,
            cone: Cone? = nil)
```

- **`color` is color times brightness, unbounded.** It is radiant intensity, not a paint color. A lamp is far brighter than white paper, and the [HDR target and tone map](tone-mapping.html) handle that.
- **`range` is finite on purpose.** Inverse-square falloff never reaches zero, so without a cutoff, every lamp in a building would count as relevant to every fragment. `attenuation(at:)` is inverse-square with a smooth window to zero at the range. The denominator has a floor, because a fragment exactly at the lamp would otherwise be `NaN` and draw black.
- **`cone` is `nil` for a point light.** `PunctualLight.Cone(direction:innerAngle:outerAngle:)` takes half-angles in radians: full brightness inside the inner angle, nothing beyond the outer, and a smooth fall between. A single cutoff angle would read as a stencil rather than a lamp.

A point light is just a spot with no cone, and the shader doesn't branch on it. Spot shading is `saturate(cosAngle * angleScale + angleOffset)`, squared. A light without a cone uses a scale of 0 and an offset of 1, so the same expression comes out as 1 everywhere.

The sample's lantern light and an uncollected crate's glow:

```swift
lights.append(PunctualLight(position: SIMD3(at.x, at.y, at.z),
                            color: SIMD3(1.0, 0.72, 0.42) * 26, range: 6.5))
lights.append(PunctualLight(position: position + SIMD3(0, 0.6, 0),
                            color: SIMD3(0.6, 6.0, 2.6), range: 4.5))
```

Three helpers are useful when ranking lamps. `influence(at:)` is attenuation weighted by luminance. `PunctualLight.luminance(_:)` is Rec. 709 luminance. `reaches(_:)` tests a `BoundingBox` against a light's range and cone, and only ever errs on the side of saying yes.

## Clustering {#clusters}

Choosing a few lights per draw works only while draws are small. The sample's ground is a single 800-meter quad. With per-draw selection, that one draw got four lights for the whole level, and a spot five meters up lost to lamps standing closer to the plane. Clustering picks lights per fragment instead.

`ClusterGrid` divides the view frustum into tiles across the screen and slices into the distance:

```swift
private static let clusterGrid = ClusterGrid(tilesX: 16, tilesY: 8, slices: 24,
                                             nearPlane: 0.1, lightRange: 120)
```

- **Slices are exponential.** An even cut would make the near slices microscopic and the far ones hundreds of meters deep. `sliceScale` and `sliceBias` let a shader find its slice with one logarithm: `slice = log(z) * sliceScale + sliceBias`.
- **`lightRange` is not a view distance.** The engine's projection has an infinite far plane, but clustering needs a finite end. Geometry beyond `lightRange` still draws, it just gets no local lights. Choose the distance past which none of your lamps reaches.

Rebuild `ClusteredLights` every frame. The grid is in view space, so it changes whenever the camera moves, even if the lights don't:

```swift
let clustered = ClusteredLights(lights: Array(lightSet.lights.prefix(SampleGame.maxSceneLights)),
                                grid: SampleGame.clusterGrid,
                                viewMatrix: camera.viewMatrix,
                                fovY: projectionFovY,
                                aspectRatio: aspectRatio,
                                maximumIndices: SampleGame.maxClusterIndices)
```

It produces two arrays for your shader. `ranges` holds, for each cluster, an offset and a count into `indices`, which is a list of light indices grouped by cluster. Upload both, plus your own packed light array. The packed light layout belongs to your game, as does the shader that loops over a cluster's lights. `maxLightsPerCluster` is worth logging, because it sets the cost of the worst fragment. `droppedIndexCount` says how many entries did not fit in `maximumIndices` — zero in a frame that fits; anything else is a cell lit short. With 64 lights in a test scene, the busiest cluster held 9 and the average was 2.2. The sample's ruins have ten lights, and the busiest cluster holds 6.

## LightSet, and a budget that can't promise much {#budget}

`LightSet(lights:budget:negligibleInfluence:)` holds a level's lights. It defaults to a budget of 4 and a `negligibleInfluence` threshold of 0.02. `affecting(_:)` ranks the lights that reach a point or a box by influence, strongest first, and returns at most the budget.

Ranking by influence instead of distance fixes the common problem: a light leaves the set at the point where it had nearly stopped mattering. It can't fix the general case. **A fixed light budget can't promise a smooth hand-over in an arbitrary level.** If five lights all contribute at one point, one of them gets dropped, and a bigger budget only changes where that happens.

So the promise is conditional, and `isOverSubscribed(at:)` checks the condition: wherever no more than `budget` lights are above `negligibleInfluence`, nothing the player can see is ever dropped. `overSubscribedPoints(among:)` runs that check over a list of points. The sample runs it at load, on spawn points and objectives:

```swift
let crowded = lightSet.overSubscribedPoints(among: points)
```

A level that fails has a lighting fault built into its geometry, and it's better to find that before release than from a report of a flickering corridor.

## Lights that belong to a placement {#placements}

`Level.Placement.light` is a lamp that a placement carries, in the placement's own space: `position` is an offset from its origin, and the cone points in its frame. `Level.resolvedLights(on:)` returns every light in world space, the free-standing `lights` first and then each placement's. Moving, turning or copying a brazier in the [editor](levels.html) takes its flame with it. The offset scales with the placement, but range and brightness don't.

```swift
var lights = level.resolvedLights(on: SampleGame.ground)
```

## Shadows for the lamps {#shadows}

Spot lights cast shadows through `ShadowAtlas` and point lights through `ShadowCubes`. Both have a fixed number of slots, and the sample gives them to the lights with the highest luminance × range. See [shadows](shadows.html).
