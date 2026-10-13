---
title: Many copies
description: Draw many copies of the same meshes with one draw per submesh per kind, using InstanceBatches and InstanceBuffer, with shadows through a self-drawing ShadowMap batch.
---
A wood is a few hundred trees of two or three kinds; a rubble field is a hundred stones of one. Drawn as separate objects, that is a draw call per copy per submesh, and the CPU cost grows with every copy. Drawn instanced, it is one draw per submesh per *kind*, and the copies are a buffer of transforms the GPU indexes.

Windage Engine splits this in two, the way it splits particles: `InstanceBatches` groups copies on the CPU and is tested without a GPU; `InstanceBuffer` puts the result where a shader can read it.

## InstanceBatches

```swift
public nonisolated struct InstanceBatches<Key: Hashable & Sendable>: Sendable {
    public struct Batch: Sendable, Equatable {
        public let key: Key
        public let start: Int          // index of this kind's first transform
        public let count: Int
        public var byteOffset: Int     // start * MemoryLayout<simd_float4x4>.stride
    }
    public private(set) var transforms: [simd_float4x4]
    public private(set) var batches: [Batch]
    public init()
    public init<Copies: Sequence>(_ copies: Copies) where Copies.Element == (Key, simd_float4x4)
    public var isEmpty: Bool
}
```

Hand it `(key, transform)` pairs. The **key** is whatever names a kind in your game — a mesh name, an index into your list of loaded meshes. The result is every copy's transform in one array, kind after kind, and a `Batch` per kind saying where its run starts and how long it is.

### Order is fixed, on purpose

**Kinds come in the order they were first seen, and copies in the order they were given.** A dictionary's order would change between runs, and with it which kind is drawn first — invisible in an opaque pass, and a flicker the day a transparent kind is instanced. The same input gives the same draws every run.

## InstanceBuffer

```swift
public final class InstanceBuffer {
    public init(renderer: FrameRenderer)
    public func write<Key>(_ batches: InstanceBatches<Key>, frameSlot: Int) -> MTLBuffer?
}
```

`write(_:frameSlot:)` copies a frame's transforms into a buffer and returns it, or `nil` when there are none.

- **One buffer per frame in flight.** A frame still being drawn is reading the previous one; rewriting it in place would draw a copy at the next frame's position for a frame.
- **Grown, never shrunk**, with room to spare: half as much again as needed, never below 1,024 copies. A scene that keeps adding copies does not reallocate every frame. The rule is tested.
- **Residency is handled.** A grown buffer is added to the renderer's residency set and committed, and the old one is removed.

The engine draws nothing here. Your vertex function reads the copies, because the vertices are yours.

## The shader contract

One `float4x4` per copy, starting at the batch's `byteOffset`, indexed by `[[instance_id]]`, applied on top of whatever per-object transform you already have. Bind the buffer's address plus `byteOffset`, then draw each submesh with `instanceCount: batch.count`.

The sample's instanced vertex function:

```metal
vertex VertexOut sampleInstancedVertex(VertexIn in [[stage_in]],
                                       uint instance [[instance_id]],
                                       constant Uniforms &uniforms [[buffer(1)]],
                                       const device float4x4 *copies [[buffer(7)]])
{
    const float4x4 model = copies[instance] * uniforms.model;
    // …
}
```

Buffer 7 is the sample's choice for the main pass. Only the shadow pass's index is fixed by the engine.

## The sample's debris

`SampleRubble.transforms(around:count:margin:seed:)` scatters small boxes among a level's buildings — deterministic, so the recorded frames never drift — and the sample groups them as one kind:

```swift
rubble = InstanceBatches(SampleRubble.transforms(around: buildings).map { ("box", $0) })
```

Each frame, before any pass, it writes them:

```swift
rubbleCopies = rubbleBuffer.write(rubble, frameSlot: frameSlot)
```

Writing before the shadow passes means the shadows and the scene draw the same copies. Then the main pass:

```swift
for batch in rubble.batches {
    argumentTable.setAddress(copies.gpuAddress + UInt64(batch.byteOffset), index: 7)
    for submesh in mesh.submeshes {
        encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType,
                                      indexCount: submesh.indexCount,
                                      indexType: submesh.indexType,
                                      indexBuffer: submesh.indexBuffer.buffer.gpuAddress
                                          + UInt64(submesh.indexBuffer.offset),
                                      indexBufferLength: submesh.indexBuffer.length,
                                      instanceCount: batch.count)
    }
}
```

> **Every piece is evenly sized**, so the shader can turn normals with the copy's own rotation. A copy squashed along one axis would need its inverse transpose, per copy.

## Shadows for instanced copies

`ShadowMap` normally draws object by object. Copies are not objects, so they go in a batch that **encodes its own draws**:

```swift
ShadowMap.Batch(pipeline: instancedShadowPipeline) { encoder, table, pass in … }
```

The engine binds the pipeline and the light matrix, then calls the closure once per sun cascade — and once per atlas tile and cube face for lamp shadows. Your closure binds what its vertex function reads and draws. The copies go at `ShadowMap.BufferIndex.instances` (4):

```swift
batches.append(ShadowMap.Batch(pipeline: instancedShadowPipeline) { encoder, table, _ in
    table.setAddress(uniforms, index: ShadowMap.BufferIndex.uniforms)
    for (bufferIndex, vertexBuffer) in box.mesh.vertexBuffers.enumerated() {
        table.setAddress(vertexBuffer.buffer.gpuAddress + UInt64(vertexBuffer.offset), index: bufferIndex)
    }
    for batch in batchList {
        table.setAddress(copies.gpuAddress + UInt64(batch.byteOffset),
                         index: ShadowMap.BufferIndex.instances)
        // draw each submesh with instanceCount: batch.count
    }
})
```

and the shadow vertex function reads them there:

```metal
vertex float4 sampleInstancedShadowVertex(VertexIn in [[stage_in]],
                                          uint instance [[instance_id]],
                                          constant Uniforms &uniforms [[buffer(1)]],
                                          constant float4x4 &lightViewProjection [[buffer(2)]],
                                          const device float4x4 *copies [[buffer(4)]])
{
    return lightViewProjection * (copies[instance] * uniforms.model * float4(in.position, 1.0));
}
```

The engine cannot cull a self-drawing batch per object, so it hands you a `ShadowMap.Pass` with the pass's `viewProjection`. The sample's debris is small enough to ignore it; a wood should build a `Frustum` from it and draw only the copies that pass can see — see [culling](culling.html). See [shadows](shadows.html) for the rest of the pass.

## What it does not do

- **Pick detail by distance.** That is `MeshDetail` — see [level-of-detail](level-of-detail.html). The sample's scenes are too small to need it.
- **Cull for you.** Which copies go into a frame is your game's choice.
- **Own the vertex function.** The contract is the buffer layout; the shader is yours.
