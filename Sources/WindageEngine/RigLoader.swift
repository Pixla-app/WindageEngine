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

    /// Where the rig sits in the file's own node hierarchy, composed from the root.
    ///
    /// **The same matrix the mesh under it carries**, and for the same reason: an exported character
    /// has its geometry *and* its skeleton in centimeters under a parent scaled by 0.01. Apply it in
    /// front of the model matrix and the mesh, the rig and the clips are all corrected at once.
    public let nodeTransform: matrix_float4x4

    public init(skeleton: Skeleton,
                clips: [AnimationClip],
                nodeTransform: matrix_float4x4 = matrix_identity_float4x4) {
        self.skeleton = skeleton
        self.clips = clips
        self.nodeTransform = nodeTransform
    }

    public func clip(named name: String) -> AnimationClip? {
        clips.first { $0.name == name }
    }

    /// The same rig with more clips on it.
    ///
    /// **This is how a real character arrives.** Every toolchain that exports one animation at a time
    /// gives you a file per clip — and each of those files carries a whole copy of the mesh and the
    /// skeleton with it. The skeleton comes from the base file, once; the clips come from the others.
    /// See ``RigLoader/clips(named:withExtension:bundle:)`` for why the skeletons in those files must
    /// be ignored rather than merged.
    public func adding(_ moreClips: [AnimationClip]) -> Rig {
        Rig(skeleton: skeleton, clips: clips + moreClips, nodeTransform: nodeTransform)
    }

    /// The rig's joints that a clip says nothing about.
    ///
    /// **Empty is what you want; everything is what a clip for a different rig looks like.** Worth
    /// checking once at load — a clip that binds to nothing is indistinguishable at runtime from a
    /// character standing still.
    public func jointsNotDrivenBy(_ clip: AnimationClip) -> [String] {
        AnimationBinding(clip: clip, skeleton: skeleton).unboundJoints
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
        return try load(url: url)
    }

    /// The same, from a file anywhere on disk — see ``MeshLoader/load(url:device:vertexDescriptor:semantics:)``
    /// for why a bundle is not enough.
    public static func load(url: URL) throws -> Rig {
        try rig(from: MDLAsset(url: url), named: url.lastPathComponent)
    }

    /// A rig from one file and its animations from others, all by URL.
    ///
    /// **A clip file's single animation is renamed to the file's own stem**, so
    /// `…/RobotPlayer_Walk.usdc` becomes `RobotPlayer_Walk` — not
    /// `root_A_MOD_BL_Walk_F_Femn_Animation_Base_Layer`, which is what the exporter called it.
    public static func load(url: URL,
                            clipURLs: [URL],
                            reportingTo report: ((String) -> Void)? = nil) throws -> Rig {
        var rig = try load(url: url)
        for clipURL in clipURLs {
            let stem = clipURL.deletingPathExtension().lastPathComponent
            let loaded = clips(url: clipURL)
            // **An unreadable file comes back empty rather than throwing.** `MDLAsset(url:)` logs and
            // returns an empty asset, so a missing clip is a file that contributed nothing — worth
            // saying out loud, since silence here is a character that simply never plays that move.
            guard !loaded.isEmpty else {
                report?("\(stem): no animation in \(clipURL.lastPathComponent)")
                continue
            }
            let named = loaded.count == 1 ? [loaded[0].renamed(to: stem)] : loaded
            let usable = named.filter { clip in
                let unbound = rig.jointsNotDrivenBy(clip)
                guard unbound.count == rig.skeleton.jointCount else { return true }
                report?("\(stem): clip '\(clip.name)' drives none of this rig's joints — dropped")
                return false
            }
            rig = rig.adding(usable)
        }
        return rig
    }

    /// Loads a rig from one file and its animations from others.
    ///
    /// - Parameter clipFiles: resource names, same extension. **A file holding exactly one clip has
    ///   that clip renamed to the file's own name**, because an exporter's internal name for an
    ///   animation is something like `root_A_MOD_BL_Walk_F_Femn_Animation_Base_Layer` and a game
    ///   wants to ask for `walk`. A file holding several leaves their names alone, since there is
    ///   then no single name the file could mean.
    ///
    /// Clips that drive none of the rig's joints are **dropped and reported** rather than kept: a
    /// clip bound to nothing is indistinguishable at runtime from a character standing still, and
    /// finding that out at load is the difference between a one-line fix and an afternoon.
    public static func load(named name: String,
                            withExtension fileExtension: String = "usdc",
                            clipFiles: [String],
                            bundle: Bundle = .main,
                            reportingTo report: ((String) -> Void)? = nil) throws -> Rig {
        var rig = try load(named: name, withExtension: fileExtension, bundle: bundle)
        for file in clipFiles {
            do {
                let loaded = try clips(named: file, withExtension: fileExtension, bundle: bundle)
                let named = loaded.count == 1 ? [loaded[0].renamed(to: file)] : loaded
                let usable = named.filter { clip in
                    let unbound = rig.jointsNotDrivenBy(clip)
                    guard unbound.count == rig.skeleton.jointCount else { return true }
                    report?("\(file): clip '\(clip.name)' drives none of this rig's joints — dropped")
                    return false
                }
                rig = rig.adding(usable)
            } catch {
                report?("\(file): \(error)")
            }
        }
        return rig
    }

    /// Reads **only** the animations out of a file, ignoring everything else in it.
    ///
    /// ### Ignoring the skeleton in a clip file is the whole point
    ///
    /// A per-clip export carries a full copy of the rig, and **its rest pose is not the rig's rest
    /// pose** — it is wherever the exporter happened to leave the skeleton, which is usually the
    /// clip's first frame. Measured on a real character: one joint's rest transform is
    /// (10.42, 4.08, 7.84) in the base file and (3.16, 1.17, 7.84) in the walk file, for the same
    /// joint of the same skeleton.
    ///
    /// So a loader that merges skeletons from clip files gets a different rest pose depending on
    /// which file it read last, and every joint a clip does *not* animate falls back to it. The
    /// character stands wrong, in a way that changes when you add an animation.
    ///
    /// **The rig comes from the base file. Clip files contribute clips and nothing else.**
    ///
    /// > **The mesh in those files is still parsed**, because Model I/O offers no way to open an
    /// > asset's animations alone. What this avoids is the expensive half — no vertex descriptor and
    /// > no buffer allocator, so nothing is laid out, converted or uploaded to a GPU.
    public static func clips(named name: String,
                             withExtension fileExtension: String = "usdc",
                             bundle: Bundle = .main) throws -> [AnimationClip] {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            throw RigLoaderError.assetNotFound("\(name).\(fileExtension)")
        }
        return clips(url: url)
    }

    /// The same, from a file anywhere on disk.
    public static func clips(url: URL) -> [AnimationClip] {
        clips(in: MDLAsset(url: url))
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
        return Rig(skeleton: skeleton,
                   clips: clips(in: asset),
                   nodeTransform: nodeTransform(of: mdlSkeleton, in: asset))
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

    /// The skeleton's own place in the file's node hierarchy.
    ///
    /// **Not decoration — see ``LoadedMesh/nodeTransform``.** An exported character's rig is in
    /// centimeters under a parent scaled by 0.01, and a loader that reads the joints and ignores the
    /// node chain produces a skeleton a hundred times too big for the world it is placed in.
    private static func nodeTransform(of skeleton: MDLSkeleton, in asset: MDLAsset) -> matrix_float4x4 {
        var found = matrix_identity_float4x4
        var matched = false
        func descend(_ object: MDLObject, _ parent: matrix_float4x4) {
            let world = object.transform.map { parent * $0.matrix } ?? parent
            if object === skeleton { found = world; matched = true }
            for child in object.children.objects where !matched { descend(child, world) }
        }
        for index in 0..<asset.count where !matched {
            descend(asset.object(at: index), matrix_identity_float4x4)
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
    static func clips(in asset: MDLAsset) -> [AnimationClip] {
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
