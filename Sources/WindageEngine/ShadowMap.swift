//
//  ShadowMap.swift
//  WindageEngine
//

import Metal
import MetalKit
import simd

/// The sun's shadow pass: the scene recorded from the light's point of view, once per cascade.
///
/// **Extracted 2026-09-09, from two implementations that had drifted into being the same thing.**
/// `ShadowCascades` — the arithmetic — has been here since it was written; the *pass* was not, and it
/// existed twice: once in this repository's sample and once in a game. Every part that varied between
/// them turned out to be one of two things, and both are supplied per ``Batch``.
///
/// > **This was previously parked as "waiting for a third consumer", and that was the wrong reason.**
/// > A third copy would have been more evidence about a question that was already answerable. What
/// > actually settled it was teaching the sample's pass to draw *skinned* meshes: a second vertex
/// > layout inside one consumer forced exactly the abstraction two consumers had been hinting at.
///
/// ### What the engine owns, and what it cannot
///
/// | here | the game's |
/// |---|---|
/// | the depth texture array, its format and its per-cascade slices | the **pipelines** — they are compiled against the game's shaders and its vertex descriptor |
/// | the reversed-Z depth state, the front-face cull, the slope-scaled bias | the **uniform layout** — what a `model` matrix sits inside is the game's struct |
/// | the per-cascade pass descriptors and the encoder loop | the joint palette, where there is one |
/// | the light matrices, per frame in flight | the cascade *numbers* — a courtyard and a sniper range want different splits |
///
/// A pipeline cannot come from here: it needs a vertex function and a vertex descriptor that only
/// the game has. **What can come from here is everything that has to be right for a pipeline to
/// work at all** — see ``pipelineDescriptor(vertexFunction:vertexDescriptor:label:)``.
public final class ShadowMap {

    /// One kind of geometry: a pipeline, and how to reach each thing drawn with it.
    ///
    /// **Batches rather than one loop, because a skinned mesh has a different vertex layout** and so
    /// needs a different pipeline. Rolling that into a per-object loop means changing pipeline per
    /// object; a list of batches changes it once per kind.
    ///
    /// Closures rather than arrays because a game's drawables are its own — an array here would mean
    /// building a copy of the scene every frame to hand over.
    public struct Batch {
        public let pipeline: MTLRenderPipelineState
        public let count: Int
        public let mesh: (Int) -> MTKMesh
        /// Where this drawable's uniforms sit for the frame slot being encoded. **Already written**:
        /// the shadow pass reads the same `model` matrix the main pass will, which is what keeps a
        /// shadow attached to the thing that cast it.
        public let uniformAddress: (Int) -> UInt64
        /// Where its joint palette sits, or nil for anything not skinned. Also already written — a
        /// shadow posed one frame behind its character is a shadow that lags a wave.
        public let jointPaletteAddress: ((Int) -> UInt64)?

        /// This drawable's bounds in **world** space, for passes that can cull.
        ///
        /// **Optional, and nil means draw everything.** A cascade covers what the camera covers, so
        /// there is little to cull and nothing to gain; ``ShadowCubes`` renders the same scene six
        /// times from one point, where a light's range and a face's frustum remove most of it. A
        /// batch that cannot cheaply say where its objects are keeps the conservative behaviour,
        /// which costs draws rather than deleting shadows.
        public let bounds: ((Int) -> BoundingBox)?
        /// **Draws for geometry that is not one `MTKMesh` per object** — instanced copies drawn with an
        /// instance count, or a mesh a game builds into its own buffers, like a heightfield it sculpts.
        /// The engine binds the cascade's light matrix and the pipeline, then hands over the encoder and
        /// the argument table; the closure binds what its vertex function reads and encodes its draws.
        /// `nil` for an ordinary batch, which the engine draws object by object.
        public let encode: ((MTL4RenderCommandEncoder, MTL4ArgumentTable, Pass) -> Void)?

        public init(pipeline: MTLRenderPipelineState,
                    count: Int,
                    mesh: @escaping (Int) -> MTKMesh,
                    uniformAddress: @escaping (Int) -> UInt64,
                    jointPaletteAddress: ((Int) -> UInt64)? = nil,
                    bounds: ((Int) -> BoundingBox)? = nil) {
            self.pipeline = pipeline
            self.count = count
            self.mesh = mesh
            self.uniformAddress = uniformAddress
            self.jointPaletteAddress = jointPaletteAddress
            self.bounds = bounds
            self.encode = nil
        }

        /// A batch that encodes its own draws — see ``encode``. Called once per cascade.
        public init(pipeline: MTLRenderPipelineState,
                    encode: @escaping (MTL4RenderCommandEncoder, MTL4ArgumentTable, Pass) -> Void) {
            self.pipeline = pipeline
            self.count = 1
            self.mesh = { _ in fatalError("a batch that encodes its own draws has no mesh") }
            self.uniformAddress = { _ in 0 }
            self.jointPaletteAddress = nil
            self.bounds = nil
            self.encode = encode
        }
    }

    /// Which pass a self-drawing batch is being asked to encode for: **so it can draw only what that pass
    /// can see.** A sun cascade near the eye covers a few metres; drawing a whole wood into it was three
    /// quarters of a measured frame.
    public struct Pass {
        /// The cascade, atlas tile or cube face (`slice × 6 + face`) being recorded.
        public let index: Int
        /// World to this pass's light clip space — build a `Frustum` from it to cull.
        public let viewProjection: matrix_float4x4

        public init(index: Int, viewProjection: matrix_float4x4) {
            self.index = index
            self.viewProjection = viewProjection
        }
    }

    /// Where the argument table puts each thing, and therefore what a game's shadow vertex function
    /// must declare. **Stated as constants rather than left in a comment**, because a mismatch here
    /// does not fail — it reads a matrix out of the wrong buffer and records the scene from nowhere.
    public enum BufferIndex {
        /// The mesh's vertex buffer. Set from the mesh, so a game never binds it.
        public static let vertices = 0
        /// The game's per-object uniforms, whatever they are.
        public static let uniforms = 1
        /// This cascade's light view-projection, a single `float4x4`, supplied by the engine.
        public static let lightViewProjection = 2
        /// The joint palette, for a skinned batch.
        public static let jointPalette = 3
        /// The copies' transforms, for an instanced batch that encodes its own draws — the
        /// ``InstanceBuffer`` contract: one `float4x4` per copy, indexed by `[[instance_id]]`.
        public static let instances = 4
    }

    /// Depth only, and this is not the engine's main depth format by accident: a cascade array is
    /// read again in a later pass, where a packed or stencil format would only cost bandwidth.
    public static let depthPixelFormat: MTLPixelFormat = .depth32Float

    public let cascades: ShadowCascades
    public let texture: MTLTexture

    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable
    private let matrixBuffer: MTLBuffer
    private static let matrixStride = MemoryLayout<matrix_float4x4>.stride

    /// - Parameter cascades: **the game's numbers.** A courtyard seventy metres across and a range
    ///   where the target is at 800 m want different splits and a different light depth range;
    ///   `ShadowCascades` takes them as arguments for that reason.
    public init?(device: MTLDevice, cascades: ShadowCascades) {
        self.cascades = cascades

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = ShadowMap.depthPixelFormat
        descriptor.width = cascades.resolution
        descriptor.height = cascades.resolution
        descriptor.arrayLength = cascades.count
        descriptor.usage = [.renderTarget, .shaderRead]
        // Private, but **not memoryless**: unlike a main depth buffer this is read again in a later
        // pass, so it has to survive its own render pass.
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Shadow Cascades"
        self.texture = texture

        guard let matrices = device.makeBuffer(
            length: ShadowMap.matrixStride * cascades.count * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else { return nil }
        matrices.label = "Cascade Matrices"
        matrixBuffer = matrices

        // Reversed-Z like every other pass in this engine: nearer the light is a *greater* value.
        // **The same convention as the main pass, and it has to be** — a shadow map written with one
        // convention and compared with the other renders a scene either fully lit or fully dark.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 5   // through BufferIndex.instances
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        argumentTable = table
    }

    /// A pipeline descriptor with everything a shadow pass needs set correctly, ready for the game's
    /// vertex function.
    ///
    /// **Three things have to be right and none of them is obvious.** No fragment function and no
    /// colour attachment, because nothing is being shaded and everything but the depth write is
    /// wasted; a raster sample count of one, because a multisampled shadow map costs four times the
    /// memory to record the same occlusion; and the depth format matching the texture, which is the
    /// one that fails loudly rather than quietly.
    ///
    /// The game still supplies the vertex function and the vertex descriptor, which is exactly the
    /// part the engine cannot know.
    public static func pipelineDescriptor(vertexFunction: MTL4LibraryFunctionDescriptor,
                                          vertexDescriptor: MTLVertexDescriptor,
                                          label: String = "Shadow") -> MTL4RenderPipelineDescriptor {
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = nil
        descriptor.vertexDescriptor = vertexDescriptor
        descriptor.rasterSampleCount = 1
        return descriptor
    }

    /// Everything the GPU must be able to reach.
    public var allocations: [MTLResource] { [texture, matrixBuffer] }

    /// This frame's light matrices, in the order a fragment shader reading the cascades expects.
    ///
    /// Computed once and handed back, so the shadow pass and the main pass cannot disagree about
    /// where the light was looking — two calls to `cascadeMatrices` a frame apart would.
    @discardableResult
    public func updateMatrices(frameSlot: Int,
                               camera: Camera,
                               sunDirection: SIMD3<Float>) -> [matrix_float4x4] {
        updateMatrices(frameSlot: frameSlot, cameraPosition: camera.position, cameraForward: camera.forward,
                       sunDirection: sunDirection)
    }

    /// The same, for a view that is not a ``Camera`` — an orbiting editor camera, a cutscene's rail.
    /// The cascades need only where the eye is and which way it looks.
    @discardableResult
    public func updateMatrices(frameSlot: Int,
                               cameraPosition: SIMD3<Float>,
                               cameraForward: SIMD3<Float>,
                               sunDirection: SIMD3<Float>) -> [matrix_float4x4] {
        let matrices = cascades.cascadeMatrices(cameraPosition: cameraPosition,
                                                cameraForward: cameraForward,
                                                sunDirection: sunDirection)
        let base = frameSlot * cascades.count * ShadowMap.matrixStride
        for (index, matrix) in matrices.enumerated() {
            var value = matrix
            matrixBuffer.contents().advanced(by: base + index * ShadowMap.matrixStride)
                .copyMemory(from: &value, byteCount: MemoryLayout<matrix_float4x4>.size)
        }
        return matrices
    }

    /// Records every batch from the sun's point of view, once per cascade.
    ///
    /// ``updateMatrices(frameSlot:camera:sunDirection:)`` must have run for this frame slot, and the
    /// per-object uniforms must already be written — the pass reads the same `model` matrix the main
    /// pass will, which is what keeps a shadow attached to the thing that cast it.
    public func encode(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, batches: [Batch]) {
        let matrixBase = frameSlot * cascades.count * ShadowMap.matrixStride

        for cascade in 0..<cascades.count {
            let descriptor = MTL4RenderPassDescriptor()
            let attachment = MTLRenderPassDepthAttachmentDescriptor()
            attachment.texture = texture
            attachment.slice = cascade
            attachment.loadAction = .clear
            attachment.clearDepth = FrameRenderer.reversedZClearDepth
            attachment.storeAction = .store        // read again in the main pass
            descriptor.depthAttachment = attachment

            guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { continue }
            encoder.label = "Shadow Cascade \(cascade)"

            // **Front-face culling.** Recording the *back* of an occluder pushes the stored depth
            // away from the lit surface, which removes most shadow acne before any bias is applied.
            // Bias then only has to cover what is left, instead of being cranked up until contact
            // shadows detach from their casters.
            encoder.setCullMode(.front)
            encoder.setFrontFacing(.counterClockwise)
            encoder.setDepthStencilState(depthState)

            // Slope-scaled bias handles what culling does not: a surface nearly edge-on to the light
            // spans many depth values inside one texel and needs proportionally more room. Scaled
            // per cascade, because a cascade covering 8x the world per texel needs 8x the bias.
            let scale = cascades.biasScales[cascade]
            encoder.setDepthBias(cascades.constantDepthBias * scale,
                                 slopeScale: cascades.slopeScaledDepthBias * scale,
                                 clamp: 0)

            encoder.setArgumentTable(argumentTable, stages: .vertex)
            argumentTable.setAddress(
                matrixBuffer.gpuAddress + UInt64(matrixBase + cascade * ShadowMap.matrixStride),
                index: BufferIndex.lightViewProjection)

            for batch in batches where batch.count > 0 {
                encoder.setRenderPipelineState(batch.pipeline)
                if let encode = batch.encode {
                    let matrix = matrixBuffer.contents()
                        .advanced(by: matrixBase + cascade * ShadowMap.matrixStride)
                        .load(as: matrix_float4x4.self)
                    encode(encoder, argumentTable, Pass(index: cascade, viewProjection: matrix))
                    continue
                }
                for index in 0..<batch.count {
                    argumentTable.setAddress(batch.uniformAddress(index), index: BufferIndex.uniforms)
                    if let joints = batch.jointPaletteAddress {
                        argumentTable.setAddress(joints(index), index: BufferIndex.jointPalette)
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
            encoder.endEncoding()
        }
    }
}
