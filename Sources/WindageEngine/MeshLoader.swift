//
//  MeshLoader.swift
//  WindageEngine
//

import Metal
import MetalKit
import ModelIO

public enum MeshLoaderError: Error, CustomStringConvertible, Sendable {
    case assetNotFound(String)
    case noMeshes(String)

    public var description: String {
        switch self {
        case .assetNotFound(let name): "No mesh named \(name) in the app bundle"
        case .noMeshes(let name): "\(name) loaded but contains no meshes"
        }
    }
}

/// Loads geometry from disk.
///
/// **This is the piece an engine would have given us.** With no importer, the format choice is a
/// real constraint rather than a preference: Model I/O reads USD, USDZ, OBJ, PLY, STL and Alembic
/// natively, and anything outside that list — FBX above all — becomes a parser this project owns.
/// Prefer USD for anything with materials or hierarchy; OBJ is fine for placeholder geometry.
public nonisolated enum MeshLoader {

    /// Loads every mesh in a file, laid out to match the render pipeline's vertex descriptor.
    ///
    /// The descriptor is passed in rather than rebuilt here because it must be *identical* to the
    /// one the pipeline was compiled against. Model I/O will happily convert a file's own layout to
    /// whatever it is handed, so a mismatch does not fail loudly — it draws garbage.
    /// - Parameter semantics: attribute index to Model I/O semantic name, e.g.
    ///   `[0: MDLVertexAttributePosition, 1: MDLVertexAttributeTextureCoordinate]`. The game owns
    ///   these indices, because they are a contract between its shaders and its vertex descriptor —
    ///   the engine has no business guessing them.
    public static func load(
        named name: String,
        withExtension fileExtension: String = "obj",
        device: MTLDevice,
        vertexDescriptor: MTLVertexDescriptor,
        semantics: [Int: String],
        bundle: Bundle = .main
    ) throws -> [LoadedMesh] {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw MeshLoaderError.assetNotFound("\(name).\(fileExtension)")
        }
        return try load(url: url, device: device, vertexDescriptor: vertexDescriptor,
                        semantics: semantics)
    }

    /// The same, from a file anywhere on disk.
    ///
    /// **An engine that can only load from its own bundle cannot load anything a person chose.** A
    /// level editor opening a mesh, a mod, a character sitting in a pipeline's output folder — all of
    /// them are a URL and none of them is a bundle resource. The bundle call above is the convenience;
    /// this is the one that does the work.
    public static func load(
        url: URL,
        device: MTLDevice,
        vertexDescriptor: MTLVertexDescriptor,
        semantics: [Int: String]
    ) throws -> [LoadedMesh] {
        let name = url.lastPathComponent

        let modelDescriptor = MTKModelIOVertexDescriptorFromMetal(vertexDescriptor)

        // Model I/O needs the attributes *named*, not merely positioned. Without this it cannot
        // tell which incoming attribute is a position and which is a normal, and the conversion
        // silently produces zeroes — which renders as an unlit black scene, with nothing thrown and
        // nothing logged. Naming every attribute the descriptor declares is not optional.
        guard let attributes = modelDescriptor.attributes as? [MDLVertexAttribute] else {
            throw MeshLoaderError.noMeshes(name)
        }
        for (index, semantic) in semantics {
            attributes[index].name = semantic
        }

        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: modelDescriptor, bufferAllocator: allocator)
        asset.loadTextures()

        let (modelMeshes, metalMeshes) = try MTKMesh.newMeshes(asset: asset, device: device)
        guard !metalMeshes.isEmpty else { throw MeshLoaderError.noMeshes(name) }

        let transforms = nodeTransforms(in: asset)

        // Bounds and materials come from the Model I/O mesh, which still knows them — `MTKMesh`
        // carries neither, and recomputing bounds from the vertex buffers afterwards means reading
        // GPU memory back.
        return zip(metalMeshes, modelMeshes).map { metal, model in
            let box = model.boundingBox
            return LoadedMesh(
                mesh: metal,
                bounds: BoundingBox(minimum: SIMD3(box.minBounds.x, box.minBounds.y, box.minBounds.z),
                                    maximum: SIMD3(box.maxBounds.x, box.maxBounds.y, box.maxBounds.z)),
                materials: materials(of: model, count: metal.submeshes.count),
                nodeTransform: transforms[ObjectIdentifier(model)] ?? matrix_identity_float4x4)
        }
    }

    /// Every mesh's place in the file's node hierarchy, composed from the root.
    ///
    /// ### The transform is not decoration, and ignoring it is how an asset comes in wrong
    ///
    /// **This loader ignored it until 2026-09-09, and a real character is what showed it.** A
    /// character out of a game engine, through an FBX, through Blender arrives with its mesh data in
    /// **centimetres** and a **scale of 0.01 on a parent node** — 176 units tall in its own space and
    /// 1.76 m in the world. Read the mesh's bounds alone and it is a hundred times too big, and the
    /// file looks wrong when it is not.
    ///
    /// It is the same shape of correction as ``AssetOrientation``: one matrix in front of the model
    /// matrix, which is enough because skinning happens in model space, so the mesh, the rig and the
    /// animation are all corrected together.
    ///
    /// **Keyed by object identity rather than by traversal order.** `MTKMesh.newMeshes` walks the
    /// asset the same way this does, so zipping would work today — and would break silently the day
    /// it does not, by putting one mesh's transform on another's geometry.
    static func nodeTransforms(in asset: MDLAsset) -> [ObjectIdentifier: matrix_float4x4] {
        var result: [ObjectIdentifier: matrix_float4x4] = [:]
        func descend(_ object: MDLObject, _ parent: matrix_float4x4) {
            let world = object.transform.map { parent * $0.matrix } ?? parent
            if let mesh = object as? MDLMesh { result[ObjectIdentifier(mesh)] = world }
            for child in object.children.objects { descend(child, world) }
        }
        for index in 0..<asset.count { descend(asset.object(at: index), matrix_identity_float4x4) }
        return result
    }

    /// One material per submesh, in the submeshes' own order.
    ///
    /// **Padded to the submesh count rather than trusted to match.** `MTKMesh` and `MDLMesh` agree
    /// on submesh order, but a file can leave a submesh unbound, and a materials array shorter than
    /// the submeshes it indexes is an out-of-bounds crash at draw time — in a loop that has nothing
    /// to do with loading. A default material draws.
    static func materials(of mesh: MDLMesh, count: Int) -> [Material] {
        let declared = (mesh.submeshes as? [MDLSubmesh] ?? []).map { submesh in
            submesh.material.map { Material($0) } ?? Material(name: submesh.name)
        }
        guard declared.count < count else { return Array(declared.prefix(count)) }
        return declared + Array(repeating: Material(), count: count - declared.count)
    }
}

/// A mesh, the box that contains it in its own space, and what its surfaces are made of.
public nonisolated struct LoadedMesh {
    public let mesh: MTKMesh
    public let bounds: BoundingBox

    /// One per submesh, in the same order — so `materials[i]` describes `mesh.submeshes[i]`.
    ///
    /// **A file's materials, not a game's.** What they mean to a shader is the game's business;
    /// carrying them at all is the difference between a bought asset arriving intact and arriving
    /// as untextured geometry with its surfaces thrown away on import.
    public let materials: [Material]

    /// Where this mesh sits in the file's own node hierarchy, composed from the root.
    ///
    /// **Apply it in front of the model matrix: `model * nodeTransform`.** It is usually the identity
    /// for a hand-written mesh and almost never for an exported one — a character out of an FBX
    /// pipeline has its geometry in centimetres under a parent scaled by 0.01. ``bounds`` is in the
    /// mesh's own space, so it needs the same treatment before it means anything in the world.
    public let nodeTransform: matrix_float4x4

    public init(mesh: MTKMesh,
                bounds: BoundingBox,
                materials: [Material] = [],
                nodeTransform: matrix_float4x4 = matrix_identity_float4x4) {
        self.mesh = mesh
        self.bounds = bounds
        self.materials = materials
        self.nodeTransform = nodeTransform
    }

    /// The material for a submesh, or a default if the file named none.
    public func material(forSubmesh index: Int) -> Material {
        materials.indices.contains(index) ? materials[index] : Material()
    }
}

/// One thing to draw: a mesh and where it sits.
///
/// Deliberately a flat list rather than a scene graph. A hierarchy earns its place when something
/// actually needs to be parented — a scope to a rifle, a rifle to a pair of hands — and inventing
/// one before then is an engine feature with no game behind it.
public nonisolated struct SceneObject {
    public let mesh: MTKMesh

    /// Where it is and how big it is — the half of this that a round cares about.
    ///
    /// **Held as a ``Volume`` rather than as its own bounds, so that half can travel without the
    /// mesh.** Everything that asks "what is out there" — ranging a target, tracing a round — goes
    /// through volumes, and a thing with no GPU mesh is as hittable as a thing with one.
    public let volume: Volume

    public var transform: matrix_float4x4 { volume.transform }
    public var worldBounds: BoundingBox { volume.worldBounds }

    /// **The mesh's node transform is composed in**, so a placement means the same thing whether the
    /// geometry came from a hand-written OBJ at the origin or from an exported character in
    /// centimetres under a scaled parent.
    public init(loaded: LoadedMesh, transform: matrix_float4x4) {
        self.mesh = loaded.mesh
        self.volume = Volume(local: loaded.bounds, transform: transform * loaded.nodeTransform)
    }
}
