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

        // Bounds come from the Model I/O mesh, which still knows them — `MTKMesh` does not carry
        // them, and recomputing from the vertex buffers afterwards means reading GPU memory back.
        return zip(metalMeshes, modelMeshes).map { metal, model in
            let box = model.boundingBox
            return LoadedMesh(
                mesh: metal,
                bounds: BoundingBox(minimum: SIMD3(box.minBounds.x, box.minBounds.y, box.minBounds.z),
                                    maximum: SIMD3(box.maxBounds.x, box.maxBounds.y, box.maxBounds.z)))
        }
    }
}

/// A mesh and the box that contains it, in the mesh's own space.
public nonisolated struct LoadedMesh {
    public let mesh: MTKMesh
    public let bounds: BoundingBox

    public init(mesh: MTKMesh, bounds: BoundingBox) {
        self.mesh = mesh
        self.bounds = bounds
    }
}

/// One thing to draw: a mesh and where it sits.
///
/// Deliberately a flat list rather than a scene graph. A hierarchy earns its place when something
/// actually needs to be parented — a scope to a rifle, a rifle to a pair of hands — and inventing
/// one before then is an engine feature with no game behind it.
public nonisolated struct SceneObject {
    public let mesh: MTKMesh
    public let transform: matrix_float4x4

    /// World-space bounds, computed once at load. Everything that asks "what is out there" — ranging
    /// a target, tracing a round — starts here.
    public let worldBounds: BoundingBox

    public init(loaded: LoadedMesh, transform: matrix_float4x4) {
        self.mesh = loaded.mesh
        self.transform = transform
        self.worldBounds = loaded.bounds.transformed(by: transform)
    }
}
