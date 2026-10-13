//
//  ParticleRenderer.swift
//  WindageEngine
//

import Foundation
import Metal
import simd

/// Draws whatever a ``ParticleSystem`` says is alive, as camera-facing quads, into the scene.
///
/// **The GPU half, split from the simulation for the reason the shadow pass is split from its
/// arithmetic.** A pipeline either draws or it does not; a lifetime curve, a spread or a pool that
/// drops the wrong particle can be wrong while looking plausible. That half wants tests, and tests
/// should not want a GPU.
///
/// ### Unlike the shadow pass, the engine can own the pipeline here
///
/// A shadow pipeline needs the game's vertex function, because it draws the game's meshes. A
/// particle is a point and a colour — there is nothing of the game's in its geometry — so the whole
/// pipeline, shaders included, lives here, and a game hands over a system and a camera.
///
/// ### Drawn into the HDR scene, after the opaque geometry
///
/// **Into the scene, not onto the interface.** A spark has to go through exposure and the tone map
/// like the lamp it came off, or it arrives on screen a different brightness from its own source.
/// Depth is **tested and never written**: a spark behind a pillar is hidden by it, and a spark in
/// front of another must not punch a hole in it.
///
/// **Unsorted**, which is a known compromise rather than an oversight. Light adds, and addition does
/// not care about order. Matter covers, and does — but at the low opacities dust and smoke are drawn
/// at, a wrong order is not something an eye finds. A game with dense smoke sorts, back to front.
public final class ParticleRenderer {

    /// One particle as the shader reads it. **Two `float4`s**, pinned by a test on size, stride and
    /// alignment.
    struct Instance {
        var positionAndHalfSize: SIMD4<Float>
        var colorAndCoverage: SIMD4<Float>
    }

    struct Frame {
        var viewProjection: matrix_float4x4
        var right: SIMD4<Float>
        var up: SIMD4<Float>
    }

    public let capacity: Int
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let argumentTable: MTL4ArgumentTable
    private let instanceBuffer: MTLBuffer
    private let frameBuffer: MTLBuffer
    private let instanceBytes: Int
    private static let frameStride = (MemoryLayout<Frame>.size + 255) & ~255

    /// - Parameter capacity: the most particles drawn in one frame. Match the system's.
    public init?(device: MTLDevice, capacity: Int = 1024) {
        self.capacity = max(1, capacity)
        instanceBytes = MemoryLayout<Instance>.stride * self.capacity
        do {
            let library = try ShaderLibrary.make(device: device, bundle: .module,
                                                 sourceNamed: "ParticleShaders")
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "weParticleVertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "weParticleFragment"

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = "Particles"
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.rasterSampleCount = 1
            descriptor.colorAttachments[0].pixelFormat = FrameRenderer.sceneColorPixelFormat
            // **Premultiplied.** See ``ParticleRecipe/glows`` — this one blend serves both light and
            // matter, and straight alpha here would darken every particle by its own opacity twice.
            descriptor.colorAttachments[0].blendingState = .enabled
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
            descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
            descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineState = try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("\(Engine.name): unable to build the particle pipeline: \(error)")
            return nil
        }

        // Reversed-Z, like every other pass: nearer is greater.
        let depth = MTLDepthStencilDescriptor()
        depth.depthCompareFunction = .greater
        depth.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depth),
              let instances = device.makeBuffer(length: instanceBytes * FrameRenderer.maxFramesInFlight,
                                                options: .storageModeShared),
              let frames = device.makeBuffer(length: ParticleRenderer.frameStride * FrameRenderer.maxFramesInFlight,
                                             options: .storageModeShared) else { return nil }
        instances.label = "Particle Instances"
        frames.label = "Particle Frame"
        self.depthState = depthState
        instanceBuffer = instances
        frameBuffer = frames

        let table = MTL4ArgumentTableDescriptor()
        table.maxBufferBindCount = 2
        guard let argumentTable = try? device.makeArgumentTable(descriptor: table) else { return nil }
        self.argumentTable = argumentTable
    }

    public var allocations: [any MTLAllocation] { [instanceBuffer, frameBuffer] }

    /// The radiance a white speck scatters toward the eye under a sky, for lighting dust and smoke.
    ///
    /// ### Why matter needs this and light does not
    ///
    /// **A particle's colour is one of two different quantities, and treating them as one is the
    /// bug this exists for.** For a spark the colour *is* its radiance: it makes light. For dust it is
    /// an **albedo** — how much of the light arriving it sends on — and drawn as if it were radiance,
    /// a grey dust puff is a grey *lamp*. The first landing in the sample threw exactly that: a
    /// 0.5-grey cloud on ground in shadow, reading as a white glow several times brighter than the
    /// floor it came off.
    ///
    /// ### Isotropic, and unshadowed
    ///
    /// A speck that scatters equally in every direction sends the eye the *average* of what arrives
    /// from all of them: the sky's mean radiance over the sphere, plus the sun's irradiance spread
    /// over 4π. That is this. **It does not know about shadow** — dust in the shade of a wall is lit
    /// as if it were in the open — which is the price of computing it once for the whole level; the
    /// sky term alone would be right in shade and far too dark in sun.
    public nonisolated static func matterLight(under sky: ProceduralSky) -> SIMD3<Float> {
        // A Fibonacci sphere: even coverage with no clustering at the poles.
        let samples = 256
        let golden = Float.pi * (3 - Float(5).squareRoot())
        // The sun is added analytically below. **A sample that landed on its disc would add its
        // radiance once more** — tens of thousands of times the sky's — so the disc is stepped round.
        let sunCone = cos(max(sky.sunAngularRadius * 3, radians_from_degrees(2)))
        var sum = SIMD3<Float>.zero
        var counted = 0
        for i in 0..<samples {
            let y = 1 - 2 * (Float(i) + 0.5) / Float(samples)
            let ring = (1 - y * y).squareRoot()
            let direction = SIMD3(cos(golden * Float(i)) * ring, y, sin(golden * Float(i)) * ring)
            guard simd_dot(direction, sky.sunDirection) < sunCone else { continue }
            sum += sky.radiance(inDirection: direction)
            counted += 1
        }
        return sum / Float(max(counted, 1)) + sky.sunIrradiance / (4 * .pi)
    }

    /// Draws every live particle, in one instanced draw.
    ///
    /// Leaves the encoder with this renderer's pipeline, depth state and argument table bound. A game
    /// that draws more afterwards binds its own again, as it would after any other pass borrowing
    /// the encoder.
    ///
    /// - Parameters:
    ///   - matterLight: the radiance a perfectly white speck of dust would scatter here — see
    ///     ``matterLight(under:)``. Multiplies every particle that does not glow; light ignores it.
    /// - Returns: how many were drawn.
    @discardableResult
    public func draw(_ system: ParticleSystem,
                     into encoder: MTL4RenderCommandEncoder,
                     frameSlot: Int,
                     viewProjection: matrix_float4x4,
                     camera: Camera,
                     matterLight: SIMD3<Float> = SIMD3(repeating: 1)) -> Int {
        let base = instanceBytes * frameSlot
        let instances = instanceBuffer.contents().advanced(by: base)
            .bindMemory(to: Instance.self, capacity: capacity)
        var count = 0
        for particle in system.particles where particle.isAlive {
            guard count < capacity else { break }
            let look = system.appearance(of: particle)
            let lit = system.recipes[particle.recipe].glows ? look.color : look.color * matterLight
            instances[count] = Instance(positionAndHalfSize: SIMD4(particle.position, look.size * 0.5),
                                        colorAndCoverage: SIMD4(lit, look.coverage))
            count += 1
        }
        guard count > 0 else { return 0 }

        var frame = Frame(viewProjection: viewProjection,
                          right: SIMD4(camera.right, 0),
                          up: SIMD4(camera.up, 0))
        let frameOffset = ParticleRenderer.frameStride * frameSlot
        frameBuffer.contents().advanced(by: frameOffset)
            .copyMemory(from: &frame, byteCount: MemoryLayout<Frame>.size)

        encoder.pushDebugGroup("Particles")
        encoder.setRenderPipelineState(pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)
        encoder.setArgumentTable(argumentTable, stages: .vertex)
        argumentTable.setAddress(instanceBuffer.gpuAddress + UInt64(base), index: 0)
        argumentTable.setAddress(frameBuffer.gpuAddress + UInt64(frameOffset), index: 1)
        encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4,
                               instanceCount: count)
        encoder.popDebugGroup()
        return count
    }
}
