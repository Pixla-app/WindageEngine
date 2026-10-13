//
//  ShadowCubes.swift
//  WindageEngine
//

import Metal
import MetalKit
import simd

/// Shadow maps for lights that radiate in every direction: a cube per light, six faces each.
///
/// ### Why this is not a tile of ``ShadowAtlas``, which is what the atlas said it would be
///
/// The atlas's own note called the missing feature "cube tiles in the atlas, six passes per light,
/// and a shader that picks a face before it picks a tile". Two thirds of that survived contact with
/// the work; **the tiles did not**, for two reasons that only appear once the shader is written.
///
/// **The face maths has to agree with six matrices exactly.** Picking a face by hand means
/// reproducing the cube-map convention — which axis becomes *u*, which becomes *v*, and which of the
/// six sign flips applies — in a shader, and matching it against six view matrices built on the CPU.
/// Every one of those is a place for a face to come out rotated or mirrored, and the picture it
/// produces is a *plausible* shadow in the wrong direction.
///
/// **And a filter kernel cannot cross a tile edge.** A shadow taken from a 2D tile is filtered by
/// stepping in *uv*; at the edge of a face the next texel is not in the next tile, it is on a
/// different face at a right angle. Taps that walk off the edge either clamp — a bright seam down
/// all twelve edges of the cube — or, worse, wander into a neighbouring light's tile.
///
/// A `typeCubeArray` texture hands both problems to the hardware. The sampler takes a **direction**
/// and picks the face itself, filters across the seams itself, and does its own comparison — so the
/// convention is the hardware's and there is nothing to match. What is left on this side is the six
/// view matrices, and those are checked against the same convention in `ShadowCubeTests`.
///
/// ### The cost, which is the reason a level should be choosing
///
/// **Six render passes per light**, against one for a spot, because six faces are six slices and a
/// slice is set on the pass descriptor rather than on the encoder — a viewport cannot move between
/// them the way it does inside the atlas.
///
/// Two culls take most of that back and both are here: a caster outside the light's **range** is
/// skipped for all six faces, and one outside a face's ``Frustum`` is skipped for that face. A batch
/// that supplies no bounds is drawn in full, which is the conservative direction — a false positive
/// costs a draw and a false negative deletes a shadow.
public final class ShadowCubes {

    /// Always six. Named rather than written as a literal because `slice = light * 6 + face` appears
    /// in three places and a `6` in the wrong one addresses another light's cube.
    public nonisolated static let faceCount = 6

    public let texture: MTLTexture
    /// Edge length of one face, in texels.
    public let size: Int
    /// How many lights may cast at once.
    public let lightCount: Int
    /// Where each face's projection starts. **Small on purpose**: the depth stored is `near / distance`,
    /// so the near plane is the whole of the precision budget and a lamp is usually inside the
    /// geometry it lights.
    public let nearPlane: Float

    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable
    private let matrixBuffer: MTLBuffer
    private static let matrixStride = 256

    /// - Parameters:
    ///   - size: one face's edge, in texels. A cube is six of these, so the memory is `6 × size² ×
    ///     lightCount × 4` bytes — 12.6 MB at the defaults.
    ///   - lightCount: how many lamps may cast at once. **Two by default**, which is deliberately
    ///     mean: six passes each is the real cost, and a level that wants more should be saying so
    ///     rather than discovering it.
    public init?(device: MTLDevice, size: Int = 512, lightCount: Int = 2, nearPlane: Float = 0.05) {
        self.size = max(16, size)
        self.lightCount = max(1, lightCount)
        self.nearPlane = max(nearPlane, 1e-4)

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .typeCubeArray
        descriptor.pixelFormat = ShadowMap.depthPixelFormat
        descriptor.width = self.size
        descriptor.height = self.size
        // **Cubes, not faces.** `arrayLength` counts whole cubes; the six faces are implied by the
        // texture type, and the slice a render pass writes is `light * 6 + face`.
        descriptor.arrayLength = self.lightCount
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Shadow Cubes"
        self.texture = texture

        // Reversed-Z, like every other pass here.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 5      // matching ShadowMap.BufferIndex, instances included
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let matrices = device.makeBuffer(
                length: ShadowCubes.matrixStride * ShadowCubes.faceCount * self.lightCount
                      * FrameRenderer.maxFramesInFlight,
                options: .storageModeShared) else { return nil }
        matrices.label = "Shadow Cube Matrices"
        self.argumentTable = table
        self.matrixBuffer = matrices
    }

    public var allocations: [MTLResource] { [texture, matrixBuffer] }

    // MARK: - The cube convention

    /// Which world directions a face's own axes point along.
    ///
    /// **Derived from the sampler's convention rather than chosen.** The hardware picks a face and a
    /// *uv* from a direction; a face rendered on this side has to land on exactly that *uv* or the
    /// shadow is filed under a coordinate nothing reads. Working backwards from the standard cube
    /// table — face `+X` has `u ∝ -z` and `v ∝ -y`, and so on — fixes all three axes, and the result
    /// is the familiar one: up is `+Y` for the four side faces, and `∓Z` for the two poles.
    ///
    /// **`right × up == forward`, which looks like the wrong handedness and is not.** A cube map is
    /// sampled from the inside, so its faces are mirrored relative to a camera looking out. The same
    /// relation holds in ``ShadowAtlas/viewProjection(for:nearPlane:)`` and in the cascades, so the
    /// winding — and therefore the front-face cull — is the same in all three.
    public nonisolated static func faceBasis(_ face: Int)
        -> (right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>) {
        switch face {
        case 0:  return (SIMD3( 0, 0, -1), SIMD3(0, 1,  0), SIMD3( 1,  0,  0))  // +X
        case 1:  return (SIMD3( 0, 0,  1), SIMD3(0, 1,  0), SIMD3(-1,  0,  0))  // −X
        case 2:  return (SIMD3( 1, 0,  0), SIMD3(0, 0, -1), SIMD3( 0,  1,  0))  // +Y
        case 3:  return (SIMD3( 1, 0,  0), SIMD3(0, 0,  1), SIMD3( 0, -1,  0))  // −Y
        case 4:  return (SIMD3( 1, 0,  0), SIMD3(0, 1,  0), SIMD3( 0,  0,  1))  // +Z
        default: return (SIMD3(-1, 0,  0), SIMD3(0, 1,  0), SIMD3( 0,  0, -1))  // −Z
        }
    }

    /// World-to-clip for one face of a light's cube.
    ///
    /// A 90° field of view and a square aspect, because six of them have to tile a sphere exactly —
    /// this is the one projection in the engine with no room to be tuned. Reversed-Z with an infinite
    /// far plane, like the rest: the light's range ends it, so a far plane would be a second place to
    /// get the same number wrong.
    public nonisolated static func viewProjection(face: Int,
                                                  position: SIMD3<Float>,
                                                  nearPlane: Float) -> matrix_float4x4 {
        let (right, up, forward) = faceBasis(face)
        let view = matrix_float4x4(columns: (
            SIMD4(right.x, up.x, -forward.x, 0),
            SIMD4(right.y, up.y, -forward.y, 0),
            SIMD4(right.z, up.z, -forward.z, 0),
            SIMD4(-simd_dot(right, position), -simd_dot(up, position), simd_dot(forward, position), 1)
        ))
        let projection = matrix_perspective_right_hand_reverse_z(
            fovyRadians: .pi / 2, aspectRatio: 1, nearZ: max(nearPlane, 1e-4))
        return simd_mul(projection, view)
    }

    /// Which face a direction lands on, and where on it — **the sampler's rule, written down.**
    ///
    /// Nothing calls this at runtime; the hardware does this itself, from the direction the shader
    /// hands it. It is here so the six matrices above can be checked against the convention they were
    /// derived from, which is the one thing about this feature that cannot be seen by looking at the
    /// screen: a face rendered mirrored still produces a shadow, in a place that is wrong in a way
    /// that reads as "the bias is off".
    ///
    /// Returns `nil` for a zero direction, which has no face.
    public nonisolated static func lookup(direction d: SIMD3<Float>) -> (face: Int, uv: SIMD2<Float>)? {
        let a = abs(d)
        let face: Int, sc: Float, tc: Float, ma: Float
        if a.x >= a.y && a.x >= a.z {
            ma = a.x
            if d.x > 0 { face = 0; sc = -d.z; tc = -d.y } else { face = 1; sc =  d.z; tc = -d.y }
        } else if a.y >= a.z {
            ma = a.y
            if d.y > 0 { face = 2; sc =  d.x; tc =  d.z } else { face = 3; sc =  d.x; tc = -d.z }
        } else {
            ma = a.z
            if d.z > 0 { face = 4; sc =  d.x; tc = -d.y } else { face = 5; sc = -d.x; tc = -d.y }
        }
        guard ma > 0 else { return nil }
        // v downwards, like every other texture here.
        return (face, SIMD2(0.5 * (sc / ma + 1), 0.5 * (tc / ma + 1)))
    }

    /// The depth a face stores for a point that far along its own axis.
    ///
    /// **`near / distance`, and the `distance` is the major axis rather than the length.** A cube face
    /// is a 90° frustum, so what its projection divides by is the offset's largest component — the
    /// corner of a face is `√3` further away than its centre and stores a *smaller* depth for it.
    /// Comparing against a euclidean distance instead darkens every face towards its corners.
    public nonisolated static func normalizedDepth(majorAxis: Float, nearPlane: Float) -> Float {
        nearPlane / max(majorAxis, 1e-6)
    }

    // MARK: - The pass

    /// One light's cube: which slice, where it is, and how far it reaches.
    public struct Caster {
        public let slice: Int
        public let position: SIMD3<Float>
        /// Used to skip casters the light cannot reach at all. **Not a far plane** — the projection
        /// has none — just a cull.
        public let range: Float

        public init(slice: Int, position: SIMD3<Float>, range: Float) {
            self.slice = slice
            self.position = position
            self.range = range
        }
    }

    /// Records every caster's six faces.
    ///
    /// The per-object uniforms must already be written for this frame slot, exactly as for the
    /// cascades: the pass reads the same `model` matrix the main pass will.
    ///
    /// - Returns: how many **objects** it recorded, across every face of every caster, so a game can
    ///   see what the culls saved. Objects rather than draw calls, because that is the number the
    ///   comparison against "six faces times everything" is made of.
    @discardableResult
    public func encode(into commandBuffer: MTL4CommandBuffer,
                       frameSlot: Int,
                       casters: [Caster],
                       batches: [ShadowMap.Batch],
                       depthBias: Float = 0,
                       slopeScale: Float = -2.5) -> Int {
        var draws = 0
        let base = frameSlot * ShadowCubes.matrixStride * ShadowCubes.faceCount * lightCount

        for caster in casters where caster.slice >= 0 && caster.slice < lightCount {
            // **Which casters this lamp can reach at all**, decided once for the whole cube rather
            // than six times. Tested against the nearest point of each box, because a long wall whose
            // centre is out of range still has an end inside it.
            let reachable = batches.map { batch -> [Int] in
                guard let bounds = batch.bounds else { return Array(0..<batch.count) }
                return (0..<batch.count).filter {
                    simd_distance(bounds($0).closestPoint(to: caster.position), caster.position)
                        <= caster.range
                }
            }
            if reachable.allSatisfy(\.isEmpty) { continue }

            for face in 0..<ShadowCubes.faceCount {
                let matrix = ShadowCubes.viewProjection(face: face, position: caster.position,
                                                        nearPlane: nearPlane)
                let frustum = Frustum(viewProjection: matrix)

                let descriptor = MTL4RenderPassDescriptor()
                let attachment = MTLRenderPassDepthAttachmentDescriptor()
                attachment.texture = texture
                // **The slice is the whole addressing scheme.** A cube array is flat underneath: six
                // consecutive slices per light, face-major.
                attachment.slice = caster.slice * ShadowCubes.faceCount + face
                attachment.loadAction = .clear
                attachment.clearDepth = FrameRenderer.reversedZClearDepth
                attachment.storeAction = .store
                descriptor.depthAttachment = attachment

                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
                else { continue }
                encoder.label = "Shadow Cube \(caster.slice) Face \(face)"

                // Front-face culling, as in the cascades and the atlas: recording the *back* of an
                // occluder removes most acne before any bias.
                encoder.setCullMode(.front)
                encoder.setFrontFacing(.counterClockwise)
                encoder.setDepthStencilState(depthState)
                encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: 0)
                encoder.setArgumentTable(argumentTable, stages: .vertex)

                var value = matrix
                let offset = base
                    + (caster.slice * ShadowCubes.faceCount + face) * ShadowCubes.matrixStride
                matrixBuffer.contents().advanced(by: offset)
                    .copyMemory(from: &value, byteCount: MemoryLayout<matrix_float4x4>.size)
                argumentTable.setAddress(matrixBuffer.gpuAddress + UInt64(offset),
                                         index: ShadowMap.BufferIndex.lightViewProjection)

                for (batchIndex, batch) in batches.enumerated() {
                    // A batch that draws itself cannot be culled per object here: it is drawn whole,
                    // which costs draws rather than deleting shadows — `ShadowMap.Batch.encode`.
                    if let encode = batch.encode {
                        encoder.setRenderPipelineState(batch.pipeline)
                        draws += 1
                        encode(encoder, argumentTable)
                        continue
                    }
                    var bound = false
                    for index in reachable[batchIndex] {
                        // A face sees a sixth of the sphere. **Skipping the other five sixths is what
                        // stops six passes costing six times one.**
                        if let bounds = batch.bounds, !frustum.canSee(bounds(index)) { continue }
                        if !bound { encoder.setRenderPipelineState(batch.pipeline); bound = true }
                        draws += 1

                        argumentTable.setAddress(batch.uniformAddress(index),
                                                 index: ShadowMap.BufferIndex.uniforms)
                        if let joints = batch.jointPaletteAddress {
                            argumentTable.setAddress(joints(index),
                                                     index: ShadowMap.BufferIndex.jointPalette)
                        }
                        let mesh = batch.mesh(index)
                        for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                            argumentTable.setAddress(
                                vertexBuffer.buffer.gpuAddress + UInt64(vertexBuffer.offset),
                                index: bufferIndex)
                        }
                        for submesh in mesh.submeshes {
                            encoder.drawIndexedPrimitives(
                                primitiveType: submesh.primitiveType,
                                indexCount: submesh.indexCount,
                                indexType: submesh.indexType,
                                indexBuffer: submesh.indexBuffer.buffer.gpuAddress
                                    + UInt64(submesh.indexBuffer.offset),
                                indexBufferLength: submesh.indexBuffer.length)
                        }
                    }
                }
                encoder.endEncoding()
            }
        }
        return draws
    }
}
