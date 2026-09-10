//
//  RigLoader.swift
//  WindageEngine
//

import Foundation
import ModelIO
import simd

public enum RigLoaderError: Error, CustomStringConvertible, Sendable {
    case assetNotFound(String)
    case noSkeleton(String)
    case conflictingGeometryBindTransforms(String)

    public var description: String {
        switch self {
        case .assetNotFound(let name): "No asset named \(name) in the bundle"
        case .noSkeleton(let name): "\(name) loaded but contains no skeleton — it is a statue"
        case .conflictingGeometryBindTransforms(let name):
            "\(name) binds several meshes to one skeleton with different geometry bind transforms"
        }
    }
}

/// A rig and everything it can do: one skeleton, and the clips authored against it.
public nonisolated struct Rig: Sendable {
    public let skeleton: Skeleton
    public let clips: [AnimationClip]

    public init(skeleton: Skeleton, clips: [AnimationClip]) {
        self.skeleton = skeleton
        self.clips = clips
    }

    public func clip(named name: String) -> AnimationClip? {
        clips.first { $0.name == name }
    }
}

/// Reads a skeleton and its clips out of a USD file.
///
/// ### Why this is separate from ``MeshLoader``, and not merely tidier
///
/// **Reading a rig needs no GPU.** Geometry does — `MTKMesh` wants a device to put buffers on — but
/// a skeleton and a clip are numbers, and Model I/O will parse them with no allocator at all. Split
/// that way, the half with all the fiddly convention in it is testable by `swift test` against a
/// real file, with nothing to open and no device to create. The half that needs a device is a
/// dozen lines and has nothing to get wrong.
///
/// ### Model I/O does read UsdSkel — measured, not assumed
///
/// The load-bearing question before any of this was written: does Model I/O import skinning, or
/// silently drop it? A hand-authored rig — two joints, eight vertices, a rotating clip — comes back
/// complete: joint indices and weights as vertex attributes, the skeleton with its joint paths and
/// both transform arrays, and the clip with its keys converted to seconds. So no third-party
/// importer is needed, and FBX gets in by way of a Blender import and a USD export.
///
/// ### Three things the API does not tell you, each found by measuring
///
/// 1. **`MDLSkeleton`'s two transform arrays are in different spaces** — rest is joint-local, bind
///    is skeleton-space. See ``Skeleton``, which is where that is written down properly.
/// 2. **Clips do not live in the object hierarchy.** They arrive in `MDLAsset.animations`, a
///    separate container, named by their full path. Walk the objects looking for them and every
///    character is a statue.
/// 3. **`MDLAnimationBindComponent.jointPaths` comes back empty** even when the component has the
///    skeleton attached. The joint paths are on `MDLSkeleton.jointPaths`; a loader that reads only
///    the bind component finds no joints and concludes the same thing.
public nonisolated enum RigLoader {

    public static func load(named name: String,
                            withExtension fileExtension: String = "usdc",
                            bundle: Bundle = .main) throws -> Rig {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw RigLoaderError.assetNotFound("\(name).\(fileExtension)")
        }
        return try rig(from: MDLAsset(url: url), named: "\(name).\(fileExtension)")
    }

    /// Pulls the rig out of an already-open asset.
    ///
    /// Exposed so a caller loading meshes from the same file does not open it twice — the mesh path
    /// needs a vertex descriptor and a buffer allocator this one has no use for.
    public static func rig(from asset: MDLAsset, named name: String = "asset") throws -> Rig {
        guard let mdlSkeleton = firstSkeleton(in: asset) else {
            throw RigLoaderError.noSkeleton(name)
        }

        // The geometry bind transform takes a vertex from the space it was modelled in into the
        // space the skeleton's bind transforms are measured in. Every export met so far has had it
        // identity; folding it into the inverse bind matrices costs one multiply at load and means
        // the shader never has to know it exists.
        var geometryBind: matrix_float4x4?
        for mesh in meshes(in: asset) {
            guard let component = mesh.componentConforming(to: MDLComponent.self) as? MDLAnimationBindComponent,
                  component.skeleton === mdlSkeleton else { continue }
            let transform = float4x4(component.geometryBindTransform)
            if let existing = geometryBind, !simd_almost_equal_elements(existing, transform, 1e-5) {
                throw RigLoaderError.conflictingGeometryBindTransforms(name)
            }
            geometryBind = transform
        }

        let skeleton = try Skeleton(mdlSkeleton, geometryBindTransform: geometryBind ?? matrix_identity_float4x4)
        return Rig(skeleton: skeleton, clips: clips(in: asset))
    }

    /// The skeleton bound to a mesh if there is one, otherwise the first in the hierarchy.
    ///
    /// The bind component is asked first because a file may carry several skeletons — a character
    /// and the rig of something it is holding — and the one the geometry points at is the one that
    /// matters. A file with a skeleton and no bound mesh is still readable, which is how an
    /// animation-only file loads.
    private static func firstSkeleton(in asset: MDLAsset) -> MDLSkeleton? {
        for mesh in meshes(in: asset) {
            if let component = mesh.componentConforming(to: MDLComponent.self) as? MDLAnimationBindComponent,
               let skeleton = component.skeleton {
                return skeleton
            }
        }
        var found: MDLSkeleton?
        walk(asset) { object in
            if found == nil, let skeleton = object as? MDLSkeleton { found = skeleton }
        }
        return found
    }

    private static func meshes(in asset: MDLAsset) -> [MDLMesh] {
        var result: [MDLMesh] = []
        walk(asset) { if let mesh = $0 as? MDLMesh { result.append(mesh) } }
        return result
    }

    private static func walk(_ asset: MDLAsset, _ visit: (MDLObject) -> Void) {
        func descend(_ object: MDLObject) {
            visit(object)
            for child in object.children.objects { descend(child) }
        }
        for index in 0..<asset.count { descend(asset.object(at: index)) }
    }

    /// Every clip in the file.
    ///
    /// **From `asset.animations`, which is not part of the object hierarchy.** Named by the last
    /// component of the animation's path, because `/Root/Walk` is where the clip lives and `Walk` is
    /// what a game asks for.
    private static func clips(in asset: MDLAsset) -> [AnimationClip] {
        guard let container = asset.animations as? MDLObjectContainer else { return [] }
        return container.objects.compactMap { object in
            guard let packed = object as? MDLPackedJointAnimation else { return nil }
            return AnimationClip(packed)
        }
    }
}

/// Narrows Model I/O's doubles to the floats everything downstream uses. USD stores matrices as
/// doubles; a GPU has no use for them.
private nonisolated func float4x4(_ m: matrix_double4x4) -> matrix_float4x4 {
    matrix_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                              SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
}

nonisolated extension Skeleton {
    /// Builds a skeleton from Model I/O's, folding in the transform that takes the mesh into the
    /// skeleton's space.
    ///
    /// - Parameter geometryBindTransform: applied to a vertex *before* skinning, so it multiplies in
    ///   on the right of each inverse bind matrix. Identity in every export measured so far, which
    ///   is exactly why it is folded in here rather than left for a game to remember.
    public init(_ skeleton: MDLSkeleton,
                geometryBindTransform: matrix_float4x4 = matrix_identity_float4x4) throws {
        let rest = skeleton.jointRestTransforms.float4x4Array
        let bind = skeleton.jointBindTransforms.float4x4Array
        try self.init(jointPaths: skeleton.jointPaths,
                      restTransforms: rest,
                      bindTransforms: bind,
                      geometryBindTransform: geometryBindTransform)
    }
}

nonisolated extension AnimationClip {
    /// Bakes Model I/O's keyframes into the engine's own storage.
    ///
    /// **Copied out rather than held.** `MDLPackedJointAnimation` samples perfectly well, but it is
    /// a reference type that keeps the whole asset alive, it is not `Sendable`, and it cannot be
    /// constructed in a test without a file on disk. A clip is a few kilobytes of numbers; owning
    /// them is cheaper than any of that.
    ///
    /// **Times arrive in seconds.** Model I/O converts them from the file's time codes using its
    /// `timeCodesPerSecond`, so a clip authored over 24 frames at 24 fps reports a duration of 1 —
    /// nothing here has to know the file's frame rate.
    public init(_ packed: MDLPackedJointAnimation) {
        let joints = packed.jointPaths
        let name = packed.name.split(separator: "/").last.map(String.init) ?? packed.name

        let translationTimes = packed.translations.times.map(Float.init)
        let rotationTimes = packed.rotations.times.map(Float.init)
        let scaleTimes = packed.scales.times.map(Float.init)

        self.init(
            name: name,
            jointPaths: joints,
            translation: JointTrack(times: translationTimes,
                                    values: translationTimes.flatMap {
                                        packed.translations.float3Array(atTime: Double($0))
                                    },
                                    jointCount: joints.count),
            rotation: JointTrack(times: rotationTimes,
                                 values: rotationTimes.flatMap {
                                     packed.rotations.floatQuaternionArray(atTime: Double($0))
                                 },
                                 jointCount: joints.count),
            scale: JointTrack(times: scaleTimes,
                              values: scaleTimes.flatMap {
                                  packed.scales.float3Array(atTime: Double($0))
                              },
                              jointCount: joints.count))
    }
}
