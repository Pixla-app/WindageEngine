//
//  RigLoaderTests.swift
//  WindageEngineTests
//

import Testing
import Foundation
import ModelIO
import simd
@testable import WindageEngine

/// Loading a rig from a real USD file, with no GPU and no window.
///
/// **That this is possible at all is the reason ``RigLoader`` is separate from ``MeshLoader``.**
/// Geometry needs a device; a skeleton and a clip are numbers. Split there, everything with a
/// convention in it — which space a transform is in, where a clip lives, whether a joint path
/// survives — is checked by `swift test` against a file somebody can read.
@MainActor
struct RigLoaderTests {

    private func loadRig() throws -> Rig {
        try RigLoader.load(named: "offset-rig", withExtension: "usda", bundle: .module)
    }

    @Test("Model I/O imports UsdSkel — joints, both transform arrays and the hierarchy")
    func skeletonComesThrough() throws {
        let rig = try loadRig()
        #expect(rig.skeleton.jointPaths == ["root", "root/mid"])
        #expect(rig.skeleton.parentIndices == [nil, 0])
    }

    /// **The finding this fixture exists for.** Rest transforms are joint-local, bind transforms are
    /// skeleton-space, and nothing in the API says so. Read them alike and a character collapses
    /// toward the origin or flies apart, depending which way round the mistake went.
    @Test("Rest and bind transforms arrive in different spaces")
    func restAndBindAreDifferentSpaces() throws {
        let skeleton = try loadRig().skeleton
        #expect(simd_distance(skeleton.restTransforms[1].columns.3, SIMD4(0, 1, 0, 1)) < 1e-5)
        let bind = simd_inverse(skeleton.inverseBindTransforms[1])
        #expect(simd_distance(bind.columns.3, SIMD4(5, 1, 0, 1)) < 1e-5)
    }

    /// Clips are not in the object hierarchy — they come from `MDLAsset.animations`, a container of
    /// its own. Walk the objects looking for one and every character is a statue.
    @Test("Clips are found, named by their last path component")
    func clipsAreFound() throws {
        let rig = try loadRig()
        #expect(rig.clips.count == 1)
        #expect(rig.clip(named: "Swing") != nil)
    }

    /// Times come back in seconds, converted from the file's time codes. The fixture runs 24 frames
    /// at 24 fps, so nothing downstream has to know the file's frame rate.
    @Test("Keyframe times are seconds, not frames")
    func timesAreSeconds() throws {
        let clip = try #require(loadRig().clip(named: "Swing"))
        #expect(abs(clip.duration - 1) < 1e-5)
        #expect(clip.rotation.times.count == 3)
        #expect(abs(clip.rotation.times[1] - 0.5) < 1e-5)
    }

    /// The end-to-end check: a file on disk poses a rig, and the joint lands where the file says.
    @Test("A loaded clip poses a loaded skeleton")
    func loadedClipPosesLoadedRig() throws {
        let rig = try loadRig()
        let clip = try #require(rig.clip(named: "Swing"))
        var pose = SkeletonPose(skeleton: rig.skeleton)

        var playhead = AnimationPlayhead(clip: clip, skeleton: rig.skeleton)
        #expect(playhead.binding.unboundJoints.isEmpty)

        playhead.advance(by: 0.5)                       // the quarter-turn key
        pose.set(to: playhead)

        // The child joint is at (5, 1, 0); a vertex a metre above it swings round to (4, 1, 0).
        let skinned = pose.skinningMatrices[1] * SIMD4<Float>(5, 2, 0, 1)
        #expect(simd_distance(SIMD3(skinned.x, skinned.y, skinned.z), SIMD3(4, 1, 0)) < 1e-4)
    }

    @Test("At rest, a loaded rig skins to where it was modelled")
    func loadedRestPoseIsIdentity() throws {
        let pose = SkeletonPose(skeleton: try loadRig().skeleton)
        for matrix in pose.skinningMatrices {
            #expect(simd_almost_equal_elements(matrix, matrix_identity_float4x4, 1e-5))
        }
    }

    @Test("A file with no skeleton says so rather than loading a statue")
    func noSkeletonThrows() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("windage-no-skeleton-\(UUID().uuidString).usda")
        try """
        #usda 1.0
        def Mesh "Box"
        {
            point3f[] points = [(0,0,0), (1,0,0), (1,1,0)]
            int[] faceVertexCounts = [3]
            int[] faceVertexIndices = [0,1,2]
        }
        """.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(throws: RigLoaderError.self) {
            try RigLoader.rig(from: MDLAsset(url: url), named: url.lastPathComponent)
        }
    }

    @Test("A missing file is named in the error")
    func missingFileThrows() {
        #expect(throws: RigLoaderError.self) {
            try RigLoader.load(named: "no-such-rig", withExtension: "usda", bundle: .module)
        }
    }
}
