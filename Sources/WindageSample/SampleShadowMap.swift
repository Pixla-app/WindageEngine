//
//  SampleShadowMap.swift
//  WindageSample
//

import Metal
import MetalKit
import WindageEngine
import simd

/// The sun's shadow pass: the scene recorded from the light's point of view, once per cascade.
///
/// **The arithmetic is not here.** Splits, the light basis, texel snapping, per-cascade bias and the
/// blend bands are `WindageEngine.ShadowCascades`, which is pure and tested without a GPU. This file
/// is only the half that needs a device — a texture, a pipeline and an encoder, which either work or
/// draw nothing at all.
///
/// **It lives in the sample rather than in the engine, and that is the extraction rule doing its
/// job.** A shadow pass has to bind *this game's* vertex layout and *this game's* per-object uniform
/// buffer; what the general seam looks like is a question a second implementation answers and a
/// first one only guesses at. This is that second implementation.
final class SampleShadowMap {

    /// A courtyard seventy metres across, not a sniper range. **These are the sample's numbers, and
    /// the fact that they are nothing like a long-range game's is the point of `ShadowCascades`
    /// taking them as an argument.**
    /// **`lightDepthRange` is 200, not the 1500 default.** It is how far along the light axis the
    /// recorded box reaches, and the default was set by a game whose world is kilometres deep. A
    /// courtyard needs a fraction of that, and leaving it wide throws away depth precision on empty
    /// air either side of the scene.
    static let cascades = ShadowCascades(splits: [8, 22, 55, 120],
                                         resolution: 1024,
                                         lightDepthRange: 200)

    let texture: MTLTexture
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable

    /// One light matrix per cascade per frame in flight. **Per frame in flight** because the GPU may
    /// still be reading last frame's while this frame's is written.
    private let matrixBuffer: MTLBuffer
    private static let matrixStride = MemoryLayout<matrix_float4x4>.stride

    init?(device: MTLDevice, library: MTLLibrary, vertexDescriptor: MTLVertexDescriptor) {
        let count = SampleShadowMap.cascades.count

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = SampleShadowMap.cascades.resolution
        descriptor.height = SampleShadowMap.cascades.resolution
        descriptor.arrayLength = count
        descriptor.usage = [.renderTarget, .shaderRead]
        // Private, but **not memoryless**: unlike the main depth buffer this is read again in a
        // later pass, so it has to survive its own render pass.
        descriptor.storageMode = .private
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        texture.label = "Sample Shadow Cascades"
        self.texture = texture

        guard let matrices = device.makeBuffer(
            length: SampleShadowMap.matrixStride * count * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else { return nil }
        matrices.label = "Cascade Matrices"
        matrixBuffer = matrices

        do {
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "sampleShadowVertex"

            let pipelineDescriptor = MTL4RenderPipelineDescriptor()
            pipelineDescriptor.label = "SampleShadowPipeline"
            pipelineDescriptor.vertexFunctionDescriptor = vertexFunction
            // **Depth only: no fragment function and no colour attachment.** Nothing is being
            // shaded; only occlusion is being recorded.
            pipelineDescriptor.fragmentFunctionDescriptor = nil
            pipelineDescriptor.vertexDescriptor = vertexDescriptor
            pipelineDescriptor.rasterSampleCount = 1
            pipeline = try compiler.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("WindageSample: shadow pipeline failed — \(error)")
            return nil
        }

        // Reversed-Z like every other pass in this engine: nearer the light is a *greater* value.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = true
        guard let depthState = device.makeDepthStencilState(descriptor: depth) else { return nil }
        self.depthState = depthState

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 3
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else { return nil }
        argumentTable = table
    }

    /// Everything the GPU must be able to reach.
    var allocations: [MTLResource] { [texture, matrixBuffer] }

    /// This frame's light matrices, in the order the fragment shader expects them.
    ///
    /// Computed once and handed back, so the shadow pass and the main pass cannot disagree about
    /// where the light was looking — two calls to `cascadeMatrices` a frame apart would.
    func updateMatrices(frameSlot: Int, camera: Camera, sunDirection: SIMD3<Float>) -> [matrix_float4x4] {
        let matrices = SampleShadowMap.cascades.cascadeMatrices(cameraPosition: camera.position,
                                                               cameraForward: camera.forward,
                                                               sunDirection: sunDirection)
        let base = frameSlot * SampleShadowMap.cascades.count * SampleShadowMap.matrixStride
        for (index, matrix) in matrices.enumerated() {
            var value = matrix
            matrixBuffer.contents().advanced(by: base + index * SampleShadowMap.matrixStride)
                .copyMemory(from: &value, byteCount: MemoryLayout<matrix_float4x4>.size)
        }
        return matrices
    }

    /// Records every drawable from the sun's point of view, once per cascade.
    ///
    /// The per-drawable uniforms must already be written for this frame slot — the shadow pass reads
    /// the same `model` matrix the main pass will, which is what keeps a shadow attached to the
    /// thing that cast it.
    func encode(into commandBuffer: MTL4CommandBuffer,
                frameSlot: Int,
                drawableCount: Int,
                meshFor: (Int) -> MTKMesh,
                uniformBuffer: MTLBuffer,
                offsetForDrawable: (Int) -> Int) {

        let count = SampleShadowMap.cascades.count
        let matrixBase = frameSlot * count * SampleShadowMap.matrixStride

        for cascade in 0..<count {
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
            encoder.setRenderPipelineState(pipeline)
            encoder.setDepthStencilState(depthState)

            // Slope-scaled bias handles what culling does not: a surface nearly edge-on to the light
            // spans many depth values inside one texel and needs proportionally more room. Scaled
            // per cascade, because a cascade covering 8x the world per texel needs 8x the bias.
            let scale = SampleShadowMap.cascades.biasScales[cascade]
            encoder.setDepthBias(-0.0006 * scale, slopeScale: -1.8 * scale, clamp: 0)

            encoder.setArgumentTable(argumentTable, stages: .vertex)
            argumentTable.setAddress(
                matrixBuffer.gpuAddress + UInt64(matrixBase + cascade * SampleShadowMap.matrixStride),
                index: 2)

            for index in 0..<drawableCount {
                argumentTable.setAddress(uniformBuffer.gpuAddress + UInt64(offsetForDrawable(index)),
                                         index: 1)
                let mesh = meshFor(index)
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
            encoder.endEncoding()
        }
    }
}
