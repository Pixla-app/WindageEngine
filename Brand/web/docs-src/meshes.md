---
title: Loading meshes
description: Load geometry through Model I/O with MeshLoader, laid out to match your pipeline, with bounds, materials, node transforms and generated tangents.
---
`MeshLoader` turns a file into Metal meshes laid out exactly the way your render pipeline expects, along with each mesh's bounding box, its materials and its place in the file's node hierarchy. It reads whatever Model I/O reads, and nothing else.

## Formats

Model I/O reads **USD, USDZ, OBJ, PLY, STL and Alembic** natively. Anything outside that list — FBX above all — has no importer in the engine. Prefer USD for anything with materials or hierarchy; OBJ is fine for placeholder geometry. Emission, for one, reaches the engine from USD and not from OBJ.

## The two load functions

```swift
public static func load(
    named name: String,
    withExtension fileExtension: String,
    device: MTLDevice,
    vertexDescriptor: MTLVertexDescriptor,
    semantics: [Int: String],
    bundle: Bundle = .main,
    reportingTo report: ((String) -> Void)? = nil
) throws -> [LoadedMesh]

public static func load(
    url: URL,
    device: MTLDevice,
    vertexDescriptor: MTLVertexDescriptor,
    semantics: [Int: String],
    reportingTo report: ((String) -> Void)? = nil
) throws -> [LoadedMesh]
```

The bundle form is a convenience that finds the file and calls the URL form. Its extension has no default: the extension is the format, and USD is the one to prefer. Use the URL form for anything a person chose — a file opened in an editor, a mod, an asset in a pipeline's output folder.

Both return one `LoadedMesh` per mesh in the file. `report` receives warnings that are not failures, such as a mesh that cannot have tangents.

### Errors

```swift
public enum MeshLoaderError: Error, CustomStringConvertible, Sendable {
    case assetNotFound(String)              // no such file in the bundle, or at the URL
    case noMeshes(String)                   // it loaded, but holds no meshes
    case unusableVertexDescriptor(String)   // Model I/O could not lay a mesh out by it
    case conversionFailed(String, underlying: any Error)   // Model I/O or Metal failed making buffers
}
```

## The vertex descriptor and semantics

The descriptor you pass must be **identical** to the one your pipeline was compiled against. Model I/O will convert a file's layout to whatever it is handed, so a mismatch does not fail loudly — it draws garbage. Build it in one place and use it for both.

`semantics` maps each attribute index to a Model I/O semantic name. The indices are a contract between your shaders and your descriptor, so your game owns them; the engine does not guess. Every attribute must be named: without names, Model I/O cannot tell a position from a normal, and the conversion silently produces zeroes, which renders as an unlit black scene.

The sample's layout:

```swift
static let semantics: [Int: String] = [
    0: MDLVertexAttributePosition,
    1: MDLVertexAttributeNormal,
    2: MDLVertexAttributeTextureCoordinate,
    3: MDLVertexAttributeTangent,
]
```

with a 48-byte stride: position `float3` at 0, normal `float3` at 12, texture coordinate `float2` at 24, tangent `float4` at 32. Its skinned layout adds joint indices and weights at indices 4 and 5 — a separate layout, and therefore a separate pipeline (see [skeletons](skeletons.html)).

> A `float4` attribute wants a 16-byte-aligned offset. Attribute index and byte offset are independent, so the layout can place attributes in a different memory order from the one the shader declares.

## Tangents for normal maps

Ask for `MDLVertexAttributeTangent` in `semantics` and the loader generates a tangent basis for any mesh whose file did not bring one — which is most files, since Model I/O's importers rarely carry tangents. A file that does supply them is left alone.

- Generation needs **normals and texture coordinates**. Without either, the mesh gets no tangents, and the loader says which one was missing through `report`.
- The tangent's `w` is **handedness, ±1**. Mirrored UV islands have their bitangent reversed; drop the sign and every mirrored surface is lit from the wrong side. That is why the tangent attribute is a `float4`.
- The loader builds the basis **before** applying your descriptor. Applied at load, the descriptor would fill a missing tangent with zeroes — degenerate rather than absent.

How the shader uses it is covered in [materials](materials.html).

## LoadedMesh

```swift
public nonisolated struct LoadedMesh: @unchecked Sendable {
    public let mesh: MTKMesh
    public let bounds: BoundingBox          // in the mesh's own space
    public let materials: [Material]        // one per submesh, same order
    public let nodeTransform: simd_float4x4
    public func material(forSubmesh index: Int) -> Material
}
```

**`Sendable`, so a mesh loaded on a worker can be handed to the main actor.** Unchecked because `MTKMesh` is a class: every field is a `let`, the engine never changes the mesh after loading it, and its buffers are `MTLBuffer`s, which Metal makes safe to share. Do not change the `MTKMesh` from two threads yourself. `SceneObject` is `Sendable` for the same reason.

`materials` is always padded to the submesh count, so `material(forSubmesh:)` never runs off the end; a submesh the file left unbound gets a default `Material`.

**`nodeTransform` is where the mesh sits in the file's hierarchy, composed from the root.** Apply it in front of the model matrix: `model * nodeTransform`. It is usually the identity for a hand-written mesh and almost never for an exported one — a character out of an FBX pipeline often has geometry in centimeters under a parent scaled by 0.01. `bounds` is in the mesh's own space and needs the same treatment. `SceneObject(loaded:transform:)` composes it for you.

## BoundingBox

`BoundingBox` is an axis-aligned box with `minimum`, `maximum`, `center` and `size`. `transformed(by:)` re-derives the box from all eight corners, so it stays correct under rotation. It also offers `contains(_:)`, `closestPoint(to:)`, `expanded(by:)`, a ray test `hitDistance(ofRayFrom:direction:maxDistance:)`, and `hitDistance(ofSegmentFrom:to:)`. A box is wrong in the corners by design; it is the crudest useful shape, and it is what [culling](culling.html) tests against.

## AssetOrientation

The engine is **Y-up and works in meters**. Many assets are not: an export that passed through a game-engine toolchain and Blender can arrive Z-up and in centimeters. `AssetOrientation` is the one matrix that corrects it.

```swift
public nonisolated struct AssetOrientation: Sendable, Equatable {
    public enum UpAxis: Sendable, Equatable { case x, y, z }
    public var upAxis: UpAxis
    public var unitsPerMeter: Float          // 1 for meters, 100 for centimeters; positive
    public static let identity: AssetOrientation
    public var transform: simd_float4x4    // rotation and scale
    public var rotation: simd_float4x4     // the axis change alone
    public init(asset: MDLAsset, unitsPerMeter: Float = 1)
}
```

Apply it before the placement: `model * orientation.transform`. Because skinning happens in model space, one matrix corrects the mesh, the rig and the animation together. The sample places its figure like this:

```swift
figureOrientation = AssetOrientation(asset: MDLAsset(url: rigURL))
let transform = placement * figureOrientation.transform * node
```

`init(asset:unitsPerMeter:)` takes the up axis from the file. **The scale it cannot read**: Model I/O does not expose USD's `metersPerUnit`, so measure the asset once and pass `unitsPerMeter` yourself. Facing is deliberately not here — which way is forward varies per tool and per rig, so apply that as a yaw where you place the thing.

## After loading

Add each mesh's vertex and index buffers to the renderer's residency set and commit it, as the sample does after every load. A buffer the GPU cannot reach draws garbage, not nothing.
