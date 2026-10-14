---
title: Loading meshes
description: Load USD, glTF and other formats with MeshLoader, laid out to match your pipeline, with bounds, materials, node transforms and generated tangents.
---
`MeshLoader` turns a file into Metal meshes laid out exactly the way your render pipeline expects, along with each mesh's bounding box, its materials and its place in the file's node hierarchy. It reads whatever Model I/O reads, and glTF.

## Formats

Model I/O reads **USD, USDZ, OBJ, PLY, STL and Alembic** natively, and the engine reads **glTF 2.0 — `.gltf` and `.glb`** — itself. **FBX is not read**: the only complete reader is Autodesk's SDK, which a public source repository cannot carry. Prefer USD or glTF for anything with materials or hierarchy; OBJ is fine for placeholder geometry. Emission, for one, reaches the engine from USD and glTF and not from OBJ.

## glTF and GLB {#gltf}

Pass a `.gltf` or `.glb` to either load function, exactly as you would a USD file. The engine reads it into an `ImportedModel` and hands that to Model I/O, so tangents, your vertex layout, bounds and materials come out the same way as for any other format.

What is read:

- **Meshes** from the default scene, each placed by its node's transform, which arrives as `nodeTransform`. Triangle strips and fans become triangle lists; points and lines are left out and reported.
- **Compressed files**: quantized attributes (`KHR_mesh_quantization`), meshopt (`EXT_meshopt_compression`, `KHR_meshopt_compression`) and Draco (`KHR_draco_mesh_compression`).
- **Materials**: the full metallic-roughness set with its textures, emission and `KHR_materials_emissive_strength`. Textures may be inside a `.glb`, in data URIs or in files beside a `.gltf`, as PNG, JPEG, WebP (`EXT_texture_webp`) or KTX2 (`KHR_texture_basisu`). `KHR_texture_transform` is baked into the texture coordinates.
- **Buffers** embedded, in data URIs, or in a `.bin` beside the `.gltf`.

A glTF texture lands the same way up as the same model's from USD: its coordinates are turned to Model I/O's v-up convention, so leave `TextureOrigin` at its default. Images that are not plain files — inside a `.glb`, in a data URI, KTX2 or WebP — are written once to the app's temporary folder, named by their contents, because a `Material` names its textures by URL. glTF's factors stay with their textures: a base color factor tints its texture, and a metallic factor of 0 keeps a metallic-roughness map from making a surface metal.

What is not read: **skins and animation**. A skinned mesh arrives in its bind pose, placed where its joints stand at rest; load the rig from USD (see [skeletons](skeletons.html)). Cameras, lights and morph targets are ignored. A file that *requires* an extension the engine does not read is refused, naming the extension.

`Material` cannot carry alpha mode and cutoff, double-sidedness, normal scale, occlusion strength, wrapping or filtering. To see them, or to write a model out again, read it yourself:

```swift
let model = try MeshLoader.model(url: url)   // or ImportedModel.read(gltf: url); throws GLTFError
for material in model.materials {
    print(material.name, material.alphaMode, material.doubleSided)
}
```

`ImportedModel` is plain values — meshes, materials and images — in meters, Y up, with linear colors. A reader of your own, for a format the engine does not read, can make one and draw it with `MeshLoader.load(model:named:device:vertexDescriptor:semantics:reportingTo:)`. `GLTFError` says why a file was refused: `unreadable`, `unsupportedVersion`, `unsupportedExtension` or `missingResource`. Through `MeshLoader`, it arrives as the `underlying` error of `conversionFailed`.

> **A sandboxed app** can open a `.bin` beside a `.gltf` only when the two share a name — `hero.gltf` and `hero.bin` — and the app declares the `.bin`'s type with `NSIsRelatedItemType` in its Info.plist. Otherwise the read fails with `missingResource`.

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
