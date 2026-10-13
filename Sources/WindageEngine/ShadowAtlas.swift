//
//  ShadowAtlas.swift
//  WindageEngine
//

import Metal
import MetalKit
import simd

/// Shadow maps for the lights that are not the sun, packed into one texture.
///
/// ### Why an atlas rather than a texture each
///
/// A shadow map per light means a texture per light: an allocation and a residency entry that appear
/// and disappear as a level loads, a render pass each, and a shader that would have to index an array
/// of textures. One texture cut into tiles is a fixed allocation, **one render pass for every light**
/// — the viewport moves between them — and a single binding the shader samples with an offset.
///
/// ### Spot lights only, and the cost of the rest is written down
///
/// A spot's shadow map is one perspective render, which is the same shape as a cascade and shares the
/// same pipeline. **A point light needs six** — a cube, one face per direction — so shadowing every
/// lamp in a room costs six times what shadowing the aimed ones does. That is a real piece of work
/// rather than a hard one: cube tiles in the atlas, six passes per light, and a shader that picks a
/// face before it picks a tile.
///
/// Until then a point light is unshadowed, which is the same limitation the sample already had and
/// is why its lamps have short ranges: a light that reaches through a wall is only obvious when it
/// reaches far enough for it to be.
public final class ShadowAtlas {

    /// One light's share of the texture.
    public nonisolated struct Tile: Sendable, Equatable {
        /// Where this tile starts, in the atlas's texels.
        public let origin: SIMD2<Int>
        /// Its edge length, in texels.
        public let size: Int

        /// The tile as the shader wants it: a UV offset and a scale, so a lookup in `0…1` for one
        /// light lands inside its own tile.
        public func uvTransform(atlasSize: Int) -> (offset: SIMD2<Float>, scale: Float) {
            let inverse = 1 / Float(atlasSize)
            return (SIMD2(Float(origin.x) * inverse, Float(origin.y) * inverse),
                    Float(size) * inverse)
        }
    }

    public let texture: MTLTexture
    public let size: Int
    public let tilesPerSide: Int

    /// How many lights may cast at once. **A hard number, and the shader does not need to know it** —
    /// a light either carries a tile or does not, which it says in its own data.
    public var tileCount: Int { tilesPerSide * tilesPerSide }

    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable
    private let matrixBuffer: MTLBuffer
    private static let matrixStride = 256   // one light matrix per tile per frame, aligned

    /// - Parameters:
    ///   - size: the whole atlas, in texels.
    ///   - tilesPerSide: cut into this many columns and rows, so `tilesPerSide²` lights may cast.
    public init?(device: MTLDevice, size: Int = 2048, tilesPerSide: Int = 4) {
        self.size = max(64, size)
        self.tilesPerSide = max(1, tilesPerSide)

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: ShadowMap.depthPixelFormat, width: self.size, height: self.size,
            mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        // Private but **not memoryless**: read again in the shading pass, like the cascades.
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Shadow Atlas"
        self.texture = texture

        // Reversed-Z, matching every other pass in this engine. A shadow map written with one
        // convention and compared with the other renders a scene either fully lit or fully dark.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 5      // matching ShadowMap.BufferIndex, instances included
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let matrices = device.makeBuffer(
                length: ShadowAtlas.matrixStride * self.tilesPerSide * self.tilesPerSide
                      * FrameRenderer.maxFramesInFlight,
                options: .storageModeShared) else { return nil }
        matrices.label = "Shadow Atlas Matrices"
        self.argumentTable = table
        self.matrixBuffer = matrices
    }

    public var allocations: [MTLResource] { [texture, matrixBuffer] }

    public func tile(_ index: Int) -> Tile {
        let clamped = min(max(index, 0), tileCount - 1)
        let edge = size / tilesPerSide
        return Tile(origin: SIMD2((clamped % tilesPerSide) * edge, (clamped / tilesPerSide) * edge),
                    size: edge)
    }

    /// Where a spot light's shadow map looks from, and how it projects.
    ///
    /// **The field of view is the cone's *outer* angle doubled**, so the map covers exactly what the
    /// light can reach — no more, which would waste resolution, and no less, which would cut the
    /// shadow off inside the lit circle.
    ///
    /// Reversed-Z with an infinite far plane, like every other projection here. The light's range
    /// already cuts it off, so a far plane would be a second place to get the same number wrong.
    ///
    /// Returns `nil` for a light with no cone: a point light needs six of these, not one.
    public static func viewProjection(for light: PunctualLight, nearPlane: Float = 0.05)
        -> simd_float4x4? {
        guard let cone = light.cone else { return nil }

        let forward = cone.direction
        var upHint = SIMD3<Float>(0, 1, 0)
        // A lamp pointing straight down is the common case and exactly where a fixed up vector is
        // degenerate — the cross product is zero and the whole basis becomes NaN.
        if abs(simd_dot(forward, upHint)) > 0.99 { upHint = SIMD3(0, 0, 1) }
        let right = simd_normalize(simd_cross(upHint, forward))
        let up = simd_cross(forward, right)

        let eye = light.position
        let view = simd_float4x4(columns: (
            SIMD4(right.x, up.x, -forward.x, 0),
            SIMD4(right.y, up.y, -forward.y, 0),
            SIMD4(right.z, up.z, -forward.z, 0),
            SIMD4(-simd_dot(right, eye), -simd_dot(up, eye), simd_dot(forward, eye), 1)
        ))

        // Widened a little past the cone, so the softened edge of the lit circle is still inside the
        // map rather than sampling whatever is beyond it.
        let fov = min(cone.outerAngle * 2.2, Float.radians(fromDegrees: 175))
        let projection = simd_float4x4(
            perspectiveFovY: fov, aspectRatio: 1, nearZ: max(nearPlane, 1e-3))
        return simd_mul(projection, view)
    }

    /// One light's shadow pass: which tile, and where it looks from.
    public struct Caster {
        public let tile: Int
        public let viewProjection: simd_float4x4

        public init(tile: Int, viewProjection: simd_float4x4) {
            self.tile = tile
            self.viewProjection = viewProjection
        }
    }

    /// Records every caster into its own tile, in **one render pass**.
    ///
    /// The viewport and scissor move between lights rather than the pass ending and starting again —
    /// a pass per light would clear and store the whole atlas each time, which is the cost of the
    /// atlas paid once per light instead of once per frame.
    public func encode(into commandBuffer: MTL4CommandBuffer,
                       frameSlot: Int,
                       casters: [Caster],
                       batches: [ShadowMap.Batch],
                       depthBias: Float = -0.0015,
                       slopeScale: Float = -2.5) {
        let descriptor = MTL4RenderPassDescriptor()
        let attachment = MTLRenderPassDepthAttachmentDescriptor()
        attachment.texture = texture
        attachment.loadAction = .clear
        attachment.clearDepth = FrameRenderer.reversedZClearDepth
        attachment.storeAction = .store
        descriptor.depthAttachment = attachment

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Shadow Atlas"

        // **Front-face culling**, as in the cascade pass: recording the back of an occluder pushes
        // the stored depth away from the lit surface and removes most acne before any bias.
        encoder.setCullMode(.front)
        encoder.setFrontFacing(.counterClockwise)
        encoder.setDepthStencilState(depthState)
        encoder.setDepthBias(depthBias, slopeScale: slopeScale, clamp: 0)
        encoder.setArgumentTable(argumentTable, stages: .vertex)

        let base = frameSlot * ShadowAtlas.matrixStride * tileCount
        for caster in casters where caster.tile >= 0 && caster.tile < tileCount {
            let region = tile(caster.tile)
            encoder.setViewport(MTLViewport(originX: Double(region.origin.x),
                                            originY: Double(region.origin.y),
                                            width: Double(region.size), height: Double(region.size),
                                            znear: 0, zfar: 1))
            // **Scissored as well as viewported.** A viewport limits where geometry lands; it does
            // not stop a clear or a wide triangle touching a neighbour's tile, and one light bleeding
            // into another's map is a shadow that appears in the wrong room.
            encoder.setScissorRect(MTLScissorRect(x: region.origin.x, y: region.origin.y,
                                                  width: region.size, height: region.size))

            var matrix = caster.viewProjection
            let offset = base + caster.tile * ShadowAtlas.matrixStride
            matrixBuffer.contents().advanced(by: offset)
                .copyMemory(from: &matrix, byteCount: MemoryLayout<simd_float4x4>.size)
            argumentTable.setAddress(matrixBuffer.gpuAddress + UInt64(offset),
                                     index: ShadowMap.BufferIndex.lightViewProjection)

            for batch in batches where batch.count > 0 {
                encoder.setRenderPipelineState(batch.pipeline)
                // A batch that draws itself — instanced copies, a game-built mesh — see `ShadowMap.Batch.encode`.
                if let encode = batch.encode {
                    encode(encoder, argumentTable, ShadowMap.Pass(index: caster.tile, viewProjection: caster.viewProjection))
                    continue
                }
                for index in 0..<batch.count {
                    argumentTable.setAddress(batch.uniformAddress(index),
                                             index: ShadowMap.BufferIndex.uniforms)
                    if let joints = batch.jointPaletteAddress {
                        argumentTable.setAddress(joints(index), index: ShadowMap.BufferIndex.jointPalette)
                    }
                    let mesh = batch.mesh(index)
                    for (bufferIndex, vertexBuffer) in mesh.vertexBuffers.enumerated() {
                        argumentTable.setAddress(vertexBuffer.buffer.gpuAddress + UInt64(vertexBuffer.offset),
                                                 index: bufferIndex)
                    }
                    for submesh in mesh.submeshes {
                        encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType,
                                                      indexCount: submesh.indexCount,
                                                      indexType: submesh.indexType,
                                                      indexBuffer: submesh.indexBuffer.buffer.gpuAddress
                                                          + UInt64(submesh.indexBuffer.offset),
                                                      indexBufferLength: submesh.indexBuffer.length)
                    }
                }
            }
        }
        encoder.endEncoding()
    }
}
