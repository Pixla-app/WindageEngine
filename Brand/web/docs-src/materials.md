---
title: Materials and textures
description: Read a file's metallic-roughness materials with Material and TextureSlot, load their maps once with TextureStore, and keep color and data textures apart.
---
Every `LoadedMesh` carries a `Material` per submesh, read from the file that named it. `TextureStore` turns those materials into GPU textures, loading each file once. Between them, a bought asset arrives with its surfaces intact instead of as untextured geometry.

What a material *says* needs no GPU and is a plain, testable value; turning it into GPU memory is a separate, small class.

## Material

```swift
public nonisolated struct Material: Sendable, Equatable {
    public var name: String
    public var baseColor: SIMD4<Float>     // linear, alpha is opacity
    public var metallic: Float             // 0 dielectric, 1 bare metal
    public var roughness: Float            // 0 a mirror, 1 chalk
    public var emissive: SIMD3<Float>      // linear
    public var textures: [TextureSlot: TextureSource]
    public var specularExponent: Float?
}
```

This is the **metallic-roughness parameter set**, because it is the one everything speaks: glTF, USD's `UsdPreviewSurface` and every common exporter agree on it. The defaults — white, dielectric, roughness 0.65 — are chosen so a material nobody filled in still draws as a plausible painted surface.

Each scalar is **multiplied** with its map when there is one, so a textured material normally carries a white base color and a scalar of 1.

> **This is a material, not a material system.** No shader graph, no permutations, no passes, no authoring model. Your shaders decide what the parameters mean; the engine only reads them faithfully.

### What `MeshLoader` does for you

`Material(_:name:)` reads a Model I/O material, and it handles three things Model I/O gets wrong quietly:

1. **Two properties can share a semantic.** A textured `UsdPreviewSurface` diffuse arrives as both a float3 and a texture. Every property is read, and the first — the one the file authored — wins.
2. **Model I/O invents a 0.18 gray base color** for files that never mentioned one. A slot with a map takes a white tint instead, so a texture is not dimmed to 18%.
3. **A map's scalar is set to the identity.** A file that connects `metallic` to a texture supplies no scalar, and the default of 0 would multiply the map away. `metallic`, `roughness` and `emissive` become 1 when mapped.

For OBJ, Model I/O always reports the same roughness whatever the file says. So when a material has a specular exponent (`Ns`), `specularExponent` is set and `roughness` is converted from it with the standard Blinn-Phong to GGX approximation, `sqrt(sqrt(2 / (Ns + 2)))`.

## TextureSlot and TextureSource

```swift
public nonisolated enum TextureSlot: String, Sendable, Hashable, CaseIterable {
    case baseColor, normal, metallic, roughness, ambientOcclusion, emissive
}

public nonisolated enum TextureSource: Sendable, Hashable {
    case url(URL)        // usually resolved by Model I/O beside the asset
    case named(String)   // a bundle resource, extension included
}
```

### Color against numbers

`TextureSlot.isColor` is true for `baseColor` and `emissive` only. A color map is authored in sRGB and has to be decoded to linear on the way in. **A roughness or normal map is not a color**: its bytes are already numbers, and decoding it as sRGB bends every value — mid-gray roughness 0.5 arrives as 0.21, and a normal map's flat regions stop being flat. Both mistakes look like a lighting problem, so the slot decides, never the call site.

### Occlusion, roughness and metalness in one texture

`TextureSlot.packedChannel` says which channel a packed slot reads: **R occlusion, G roughness, B metalness** — glTF's packing, and what exporters write. Model I/O does not pass on which channel a USD input reads, so the convention is assumed here. It also works for an unpacked grayscale map, whose green channel is its value. The sample binds one ORM texture per submesh, taken from the roughness slot, since all three slots name the same file and `TextureStore` loads it once.

## TextureStore

```swift
public final class TextureStore {
    public init(device: MTLDevice) throws   // TextureStoreError.fallbackUnavailable
    public let white: MTLTexture        // 1×1 opaque white
    public let flatNormal: MTLTexture   // 1×1 (0.5, 0.5, 1)
    public func fallback(for slot: TextureSlot) -> MTLTexture
    public func texture(_ source: TextureSource, isColor: Bool,
                        origin: TextureOrigin = .bottomLeft,
                        bundle: Bundle = .main) throws -> MTLTexture
    public func textures(for material: Material, origin: TextureOrigin = .bottomLeft,
                         bundle: Bundle = .main,
                         reportingTo report: ((String) -> Void)? = nil) -> [TextureSlot: MTLTexture]
    public var allocations: [any MTLAllocation]
}
```

- **It caches** by file, by color-or-data and by origin. Every crate naming the same map shares one texture.
- **Every texture gets mipmaps**, because anything seen at an angle aliases without them.
- **Fallbacks let a shader always sample.** `white` multiplies to nothing; `flatNormal` means "no perturbation". They differ on purpose: a white pixel decoded as a normal tilts every surface diagonally.
- `textures(for:)` **never throws**. A missing map draws the object in its plain color and is reported once, rather than stopping a level from loading.
- After loading, add `allocations` to the renderer's residency set and commit. A texture the GPU cannot reach is garbage that looks like a shader bug.

### The v axis

Metal puts texture coordinate (0, 0) at an image's top-left; USD and OBJ put it at the bottom-left. `TextureStore` flips on load with `.bottomLeft`, the default and the convention of every format Model I/O reads. Use `.topLeft` for glTF-derived UVs or coordinates your game generates itself.

### Errors

`TextureStoreError` has three cases: `notFound(String)` for a missing bundle resource, `loadFailed(String, underlying:)` when the file would not decode, and `fallbackUnavailable`, which `init(device:)` throws when the device will not make the 1×1 fallbacks.

## In the sample

The sample resolves every map from the file's own material, per submesh:

```swift
let material = mesh.material(forSubmesh: index)
guard let source = material.textures[slot] else { return textures.fallback(for: slot) }
do {
    return try textures.texture(source, isColor: slot.isColor, bundle: .module)
} catch {
    print("WindageSample: \(name) \(slot.rawValue) — \(error)")
    return textures.fallback(for: slot)
}
```

## Normal mapping

A normal map stores directions in **tangent space**, relative to the surface, so it needs the surface's tangent to get back to world space. Ask `MeshLoader` for `MDLVertexAttributeTangent` and it generates one — see [meshes](meshes.html). In the shader:

- **Reconstruct the bitangent** as the cross of normal and tangent times the handedness `w`, rather than storing it.
- **Re-orthogonalize the tangent** against the interpolated normal first.
- **Transform the tangent by the model matrix**, not the normal matrix: it lies along the surface.
- **Keep the geometric normal for the shadow lookup**, or contact shadows detach from their casters.

Model I/O's OBJ reader recognizes only the `bump` keyword for a normal map; `map_Bump`, `norm`, `map_Kn` and `map_normal` are silently dropped. Use USD for normal-mapped assets.

## What things are made of, for sound

A material says how a surface looks, not what it sounds like underfoot. That is the level's word: `Level.Placement.surface` (`"stone"`, `"wood"`) and `Level.surface(standingOn:)`. See [levels](levels.html) and [audio](audio.html).
