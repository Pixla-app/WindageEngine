---
title: Shadows
description: Cascaded sun shadows with ShadowMap and ShadowCascades, spot-light shadows in a ShadowAtlas, and point-light shadows in ShadowCubes.
---
Windage Engine draws three kinds of shadow: the sun's, in cascades; spot lights', in one atlas texture; and point lights', in a cube array. The engine owns the textures, the depth state, the bias and the encoder loops. Your game keeps the two things only it can know: its pipelines and its uniform layout.

## The split {#split}

| The engine's | Your game's |
| --- | --- |
| the depth texture array and its per-cascade slices | the **pipelines**, compiled against your shaders and vertex descriptor |
| the reversed-Z depth state, front-face cull, slope-scaled bias | the **uniform layout**, meaning the struct a `model` matrix sits in |
| the per-cascade pass descriptors and the encoder loop | the joint palette, where there is one |
| the light matrices, per frame in flight | the cascade **numbers** |

## Cascades for the sun {#cascades}

`ShadowCascades` is a value you configure: where each cascade ends, the resolution, and how far the light box reaches. A courtyard and a long-range outdoor game need different splits, so the numbers belong to your game:

```swift
private static let cascades = ShadowCascades(splits: [8, 22, 55, 120],
                                             resolution: 1024,
                                             lightDepthRange: 200)
```

That is the sample's set, for a courtyard seventy meters across (the defaults are a resolution of 2048 and a light depth range of 1500). Three behaviors are built in:

- **The light matrix snaps to whole texels**, so shadow edges don't crawl as the camera moves.
- **Bias scales per cascade** (`biasScales`). If a cascade covers 8× the world per texel, it needs about 8× the bias.
- **Each cascade fades into the next** over the last `blendFraction` of its own span. Without that, you'd see a seam at a fixed distance from the player.

`normalizedDepthBias(forCascade:)` derives the shader's bias from a texel's world size, so `biasTexels` doesn't depend on scene scale. Shaders get four-wide vectors: `splitVector`, `blendStartVector`, `depthBiasVector` and `biasScales`. `constantDepthBias` and `slopeScaledDepthBias` are **negative**, because under reversed-Z, pushing an occluder away from the light means a smaller depth value.

## The pass {#pass}

`ShadowMap(device:cascades:)` allocates the cascade array (`texture`, in `ShadowMap.depthPixelFormat`). Add its `allocations` to your residency set.

Build each shadow pipeline from `ShadowMap.pipelineDescriptor(vertexFunction:vertexDescriptor:label:)`. It sets everything that has to be right: no fragment function, no color attachment and a raster sample count of one. You supply the vertex function and the vertex descriptor.

Your shadow vertex function reads its inputs at the indices in `ShadowMap.BufferIndex`: `vertices` (0), `uniforms` (1), `lightViewProjection` (2), `jointPalette` (3) and `instances` (4). A mismatch raises no error; it records the scene from the wrong matrix.

Each frame, call `updateMatrices` once and use what it returns for both passes:

```swift
let matrices = shadowMap.updateMatrices(frameSlot: frameSlot, camera: view,
                                        sunDirection: sunDirection)
```

For a view that isn't a `Camera`, such as an orbiting editor camera, use `updateMatrices(frameSlot:cameraPosition:cameraForward:sunDirection:)`. Then call `encode(into:frameSlot:batches:)`.

### Batches {#batches}

A `ShadowMap.Batch` is one kind of geometry: a pipeline, plus closures that reach each object. A skinned mesh has a different vertex layout, so it needs its own batch. This is the sample's static batch:

```swift
var batches = [ShadowMap.Batch(
    pipeline: shadowPipeline,
    count: visibleDrawableCount,
    mesh: { self.drawables[$0].mesh.mesh },
    uniformAddress: { self.uniformBuffer.gpuAddress
        + UInt64(self.uniformOffset(frameSlot: frameSlot, drawable: $0)) },
    bounds: { self.volumes[$0].worldBounds })]
```

A skinned batch also passes `jointPaletteAddress`. `bounds` is optional; `nil` means "draw everything", and `ShadowCubes` uses it to cull.

The second initializer, `Batch(pipeline:encode:)`, is for geometry that isn't one `MTKMesh` per object: instanced copies, or a mesh your game builds into its own buffers. The engine binds the pipeline and the light matrix, then calls your closure once per pass with the encoder, the argument table and a `ShadowMap.Pass`: `index` is the cascade, atlas tile or cube face, and `viewProjection` is its light matrix, from which a `Frustum` can cull. The sample draws its debris this way, binding copies at `ShadowMap.BufferIndex.instances`.

## Write uniforms before any pass {#order}

A shadow pass reads the same `model` matrix and joint palette as the main pass. Write them in `encodePrePasses`, before any shadow is recorded. If you write them in `encode`, every shadow is recorded from the previous frame's positions and lags behind its caster. The sample's `encodePrePasses` writes uniforms, debris transforms and light matrices first, then encodes the three shadow passes. See [game loop](game-loop.html).

> **Every shadow was a frame stale, and it looked right.** Metal 4 tracks no hazards between passes. Until 0.20.0 the scene pass sampled shadow maps a pass in the same command buffer was still writing, so every shadow was a frame stale, and the very first frame differed on every run: once black, once blotched in cluster-sized squares. `FrameRenderer` now places barriers so the scene waits for the shadow passes. The [frame check](frames.html) caught it.

## Spot lights: ShadowAtlas {#atlas}

`ShadowAtlas(device:size:tilesPerSide:)` cuts one texture into tiles (2048 texels and 4 per side by default, so `tileCount` is 16). All casters share **one render pass**. `ShadowAtlas.viewProjection(for:nearPlane:)` builds a spot's matrix from its cone, and returns `nil` for a light with no cone. Pass `ShadowAtlas.Caster(tile:viewProjection:)` values to `encode(into:frameSlot:casters:batches:depthBias:slopeScale:)`, reusing the batches from the cascades. In the shader, `tile(_:).uvTransform(atlasSize:)` gives the offset and scale for a tile.

## Point lights: ShadowCubes {#cubes}

`ShadowCubes(device:size:lightCount:nearPlane:)` is a cube-array depth texture. The hardware sampler picks the face and filters across seams. It costs **six render passes per light**, so `lightCount` defaults to two and a level should choose which lamps get one. Pass `ShadowCubes.Caster(slice:position:range:)` values to `encode(into:frameSlot:casters:batches:depthBias:slopeScale:)`. It returns how many objects it recorded. Casters outside the light's range are skipped for all six faces, and those outside a face's frustum for that face: in the sample's ruins, 35 objects recorded against 384 unculled.

The sample uses `ShadowCubes(device: device, size: 384, lightCount: 6)` and reassigns cubes every frame: a cube recorded from where a carried lantern *was* casts a shadow that lags the hand.

Related: [lights](lights.html), [culling](culling.html), [instancing](instancing.html).
