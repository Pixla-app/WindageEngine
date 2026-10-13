---
title: Culling
description: Skip what a view cannot see with Frustum and BoundingBox — five planes under an infinite far plane — for the camera and for each shadow pass.
---
`Frustum` takes a view-projection matrix and answers one question: could any part of this box be visible? Use it to skip drawing what is behind the player or off to the side, and to skip shadow casters a light's pass cannot see.

## Why cull an open scene

A 70° field of view is under a fifth of the circle. In a scene of a few hundred objects, most of them sit behind the player's shoulders whether or not anything blocks them, so testing each against the view is cheap and saves a draw call per object. It matters more for shadows, where the same scene is recorded several times from a light's point of view.

## Frustum

```swift
public struct Frustum: Sendable, Equatable {
    public private(set) var planes: [SIMD4<Float>]
    public init(viewProjection m: simd_float4x4)
    public func mayIntersect(_ box: BoundingBox) -> Bool
}
```

Build it from the same world-to-clip matrix you draw with, and test world-space boxes against it:

```swift
// Your game
let viewProjection = simd_mul(projection, camera.viewMatrix)
let frustum = Frustum(viewProjection: viewProjection)

for object in objects where frustum.mayIntersect(object.worldBounds) {
    draw(object)
}
```

Each plane is a `(normal, distance)` pair, unit-normalized and pointing inward: a point is inside when `dot(normal, point) + distance >= 0` for every plane.

### Five planes, not six

The engine's projection, `simd_float4x4(perspectiveFovY:aspectRatio:nearZ:depthRange:)`, has an **infinite far plane** (see [camera](camera.html)). Extract the far plane from it and you get a zero normal, because there is no far plane to extract. `Frustum` drops it, so a Windage Engine frustum has **five** planes: left, right, bottom, top and near.

Code written expecting six is written for a different projection. It would either carry a plane that always passes or divide by zero normalizing it. The tests check for exactly five unit-length planes, and that a box 100 km down the view is still visible.

### Reversed-Z, the right way round

The planes are extracted from the matrix rows (Gribb–Hartmann). The textbook form assumes near maps to depth 0 and far to `w`; under reversed-Z near maps to 1 and far to 0, so the near and far rows swap. `Frustum` does this for you. Extracted the textbook way, the near plane would cull everything close to the camera — which reads as geometry failing to load, not as a culling bug.

## The asymmetry behind every detail

**A false positive costs a draw call. A false negative deletes something the player can see.** Those are not comparable, so `mayIntersect` leans toward keeping:

- It is the standard conservative box test. For each plane it takes the box corner furthest along the plane's normal and rejects only if even that corner is outside.
- A box straddling a plane is kept, even when most of it is outside. That costs a draw, never a missing object.

## BoundingBox, in world space

`mayIntersect` takes a `BoundingBox` in **world** space. A `LoadedMesh`'s `bounds` are in the mesh's own space, so transform them first. `BoundingBox.transformed(by:)` re-derives the box from all eight corners, which stays correct under rotation. A `Volume` does this for you:

```swift
let volume = Volume(local: mesh.bounds, transform: transform)
let box = volume.worldBounds
```

Remember the mesh's `nodeTransform` belongs inside the transform — see [meshes](meshes.html).

**A skinned mesh's bounds are its bind pose.** An arm raised at runtime leaves the box, and a culling test against it deletes the character's shadow at exactly the moment it moves. Widen it with `expanded(by:)`; the sample uses half a meter for its figures:

```swift
bounds: { Volume(local: mesh.bounds, transform: self.figures[$0].transform)
    .worldBounds.expanded(by: 0.5) }
```

## Culling shadow passes

A shadow is the scene drawn again from a light's point of view, so the same test applies per pass. `ShadowMap.Batch` takes an optional `bounds` closure — this drawable's world-space box — for the passes that can use it:

```swift
ShadowMap.Batch(
    pipeline: shadowPipeline,
    count: visibleDrawableCount,
    mesh: { self.drawables[$0].mesh.mesh },
    uniformAddress: { /* this drawable's uniforms */ },
    bounds: { self.volumes[$0].worldBounds })
```

`nil` means draw everything, which is the conservative direction. With bounds supplied:

| Pass | What it culls |
| --- | --- |
| `ShadowCubes` (point lights) | Casters outside the light's range skip all six faces; casters outside a face's `Frustum` skip that face. |
| `ShadowMap` (sun cascades) | Ordinary batches are drawn whole: a cascade covers what the camera covers, so there is little to remove. |

See [shadows](shadows.html) and [lights](lights.html).

### A batch that draws itself culls itself

A batch built with `ShadowMap.Batch(pipeline:encode:)` — instanced copies, or geometry your game builds into its own buffers — encodes its own draws, so the engine cannot cull it per object. Instead, since 0.24.0, the closure is told which pass it is drawing:

```swift
public struct Pass {
    public let index: Int                       // cascade, atlas tile, or cube face (slice × 6 + face)
    public let viewProjection: simd_float4x4  // world to this pass's light clip space
}
```

Build a `Frustum` from `pass.viewProjection` and draw only what it can see:

```swift
// Your game
ShadowMap.Batch(pipeline: instancedShadowPipeline) { encoder, table, pass in
    let frustum = Frustum(viewProjection: pass.viewProjection)
    // keep the copies whose world bounds frustum.mayIntersect(_:) accepts, then draw them
}
```

A sun cascade near the eye covers only a few meters. On a scattered wood of 1,000 heavy trees, drawing every copy into all four cascades was three quarters of the frame — 75 ms with shadows against 19 without — and culling each cascade to its own frustum brought it to 25 ms.

The sample's debris is small enough to draw whole into every pass, so its batch ignores the pass (`{ encoder, table, _ in … }`). See [instancing](instancing.html).

## What it does not do

- **No occlusion culling.** Something hidden behind a wall but inside the frustum is drawn.
- **No spatial structure.** `mayIntersect` is a test you call per box; a game with many thousands of objects groups them first.
- **No automatic culling of the main view.** The engine draws nothing of yours, so which objects reach a draw call is your game's loop.
