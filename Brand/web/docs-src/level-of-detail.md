---
title: Level of detail
description: MeshDetail makes simpler tiers of a mesh when it loads and picks the coarsest one a distant copy can use without a visible change.
---
`MeshDetail` makes simpler versions of a mesh when it loads, and gives you the rule that picks one for how far away a copy stands. You need it when a scene has thousands of copies of a heavy mesh, most of whose triangles are detail too small to see from where they stand.

## Tiers {#tiers}

A mesh gets up to ten **tiers** (`MeshDetail.Options.maximumTiers`), each aiming for about half the triangles of the one before (`reduction`). Tier 0 is the mesh as loaded. They are called tiers rather than levels because in this engine a level is a `Level` file.

Tiers stop early when a tier would keep more than `stall` (85%) of the triangles before it, and a submesh of `smallestTriangleCount` (12) triangles or fewer is left alone. Those are the defaults of `MeshDetail.Options`; pass your own as `options:` when your meshes ask for different ones.

For a mesh that came through `MeshLoader`, one call does everything:

```swift
// Your game, after MeshLoader.load(…). Safe off the main thread, and worth running there.
let tiers = MeshDetail.tiers(for: loaded, vertexDescriptor: layout, positionAttribute: 0, normalAttribute: 1)
```

`vertexDescriptor` is the one the mesh was loaded with. Attribute `positionAttribute` is where each vertex's position is read, and `normalAttribute` where the normal each tier rewrites goes; both are three floats in the same buffer, whose layout gives the stride. The mesh's own buffers are read on the CPU. A mesh with a submesh that is not triangles gets no tiers. Simplifying a 19,000-triangle mesh takes a few milliseconds.

Each `MeshDetail.Tier` has:

| Property | What it is |
| --- | --- |
| `vertices` | `[UInt8]` in the full mesh's vertex layout, three vertices per triangle |
| `submeshes` | `[[UInt32]]`, per submesh, indices into `vertices` |
| `error` | the worst of its submeshes' errors, in the mesh's units |

Tier `i` is reduction `i` of every submesh, so a copy changes all its parts at once. A submesh with fewer reductions repeats its coarsest.

### The steps, for a mesh that did not come from MeshLoader

The call above is two public steps. `reductions(indices:positions:vertexCount:stride:)` simplifies one submesh into `[MeshDetail.Reduction]`, each with `indices` into the full mesh's vertices and an `error`; `positions` points at the first vertex's three position floats. `tiers(_:full:vertices:stride:positionOffset:normalOffset:)` turns per-submesh reductions into tiers; `full` is each submesh's own indices, and `vertices` points at the first vertex itself. Both take `options:`. Every reduction is made from the full mesh, so errors do not add up from tier to tier.

## Choosing a tier: the half-pixel rule {#choose}

Each tier's error is how far its surface strays from the original, in the mesh's units. Seen from far enough away, that covers less than half a pixel and the tier cannot be told from the full mesh. So there is no table of distances to tune per asset.

```swift
// Your game, per copy, per frame. `fovy` is the vertical field of view your game passes to
// simd_float4x4(perspectiveFovY:aspectRatio:nearZ:); `viewportHeight` is in pixels,
// from viewportSizeChanged(width:height:). `box` is the copy's BoundingBox in the world.
let radius = simd_length(box.maximum - box.minimum) / 2
let distance = simd_distance(camera.position, box.center) - radius
let tier = MeshDetail.coarsestTier(errors: tiers.map(\.error),
                                   distance: distance,
                                   scale: copyScale,                 // the copy's uniform scale
                                   pixelsPerRadian: Float(viewportHeight) / fovy)
```

- `errors[i]` is tier `i + 1`'s error. A result of 0 means the full mesh; a result of `n` means `tiers[n - 1]`, because the array `tiers(for:…)` returns starts below the full mesh.
- `distance` is from the eye to the nearest the copy can come: its box's center less its radius. A distance of 0 or less returns the full mesh.
- `scale` is the copy's size. A tree scaled up strays further.
- `pixelsPerRadian` is the viewport's height in pixels over its vertical field of view in radians.
- `maximumPixelError` defaults to `0.5`.

> **Half a pixel, not one.** At one pixel, a wood of trees six pixels tall visibly lost their tiers of branches: a pixel of error all round an outline that small adds up to a different shape.

The tests check that a farther copy never gets a finer tier than a nearer one.

## Recomputed normals {#normals}

A simplified mesh keeps some vertices and drops the rest, and a kept vertex keeps its normal. On a faceted prop that normal belonged to one face of many, perhaps one facing the ground, so a far copy drew nearly black. Every tier therefore gets **its own vertices, with normals made again from its own faces**: each corner's normal is the area-weighted average of the faces meeting at its position that bend less than 60° from its own face (`MeshDetail.Options.creaseCosine`), so hard edges stay hard.

The cost is three vertices per triangle of each tier, which halves with every tier: about 1 MB for every tier of a 19,000-triangle tree together.

## Permissive simplification {#permissive}

The simplifier may collapse across hard edges. Low-poly packs split every vertex at every hard edge, so a careful simplifier finds nothing it may touch. The price is softened shading on a far copy, below half a pixel.

## Drawing a tier is the game's job {#drawing}

`MeshDetail` is the CPU half only, like `InstanceBatches`. Putting a tier's vertices in a buffer and drawing them is yours, because only your game knows its vertex layout and how it batches.

**Copies at different tiers are different batches.** Key `InstanceBatches` by mesh *and* tier:

```swift
// Your game.
struct DrawKey: Hashable, Sendable {
    var mesh: Int
    var tier: Int
}
let batches = InstanceBatches<DrawKey>(copies)   // copies: [(DrawKey, simd_float4x4)]
```

See [instancing](instancing.html) and [culling](culling.html).

## What it does not do

- **It is not in the sample.** The sample's meshes are a few hundred triangles seen from a few meters, so no tier would ever be chosen. A test proves it on a mesh loaded through `MeshLoader`.
- **No blending between tiers.** A copy switches tier from one frame to the next; the half-pixel rule keeps the switch out of sight.

## The license you ship

The simplifier is meshoptimizer's (MIT), vendored unmodified as the `MeshOptimizer` target: the engine's first code not written in Swift. **An app that ships `MeshDetail` ships meshoptimizer's license**, `Sources/MeshOptimizer/LICENSE.md`, alongside its other notices.

Added in 0.25.0 ([changelog](changelog.html)): 1,000 trees of 19,000 triangles each went from 25 ms a frame to 5.6 ms on an M2.
