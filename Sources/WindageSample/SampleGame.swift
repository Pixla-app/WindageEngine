//
//  SampleGame.swift
//  WindageSample
//

import AppKit
import Metal
import MetalKit
import simd
import WindageEngine

/// **The whole game.** Walk around a level you can edit, with a line of text saying where you are.
///
/// It is deliberately dull. Its job is not to be a good game; it is to be the thing that proves the
/// engine can be built against **using only its public API**, by somebody who is not the person who
/// wrote it. Every gap it hits is an engine bug — the first one it found was that `swift build`
/// compiles no Metal at all, so the HUD could not start outside Xcode. See ``ShaderLibrary``.
final class SampleGame: GameLoop {

    /// One description of the vertex layout, shared by the pipeline and the mesh loader. **They must
    /// agree**: Model I/O will convert a file to whatever layout it is handed, so a mismatch draws
    /// garbage rather than failing.
    static let semantics: [Int: String] = [0: MDLVertexAttributePosition, 1: MDLVertexAttributeNormal]

    static func vertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float3
        descriptor.attributes[1].offset = 12
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = 24
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    private struct Uniforms {
        var viewProjection: matrix_float4x4
        var model: matrix_float4x4
        var normalMatrix: matrix_float3x3
        var albedo: SIMD3<Float>
        var sunDirection: SIMD3<Float>
    }

    private let engine: FrameRenderer
    private let pipeline: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let hud: HUDRenderer?
    private let argumentTable: MTL4ArgumentTable
    private let uniformBuffer: MTLBuffer

    private let level: Level
    private let levelPath: String
    private var meshes: [String: LoadedMesh] = [:]
    /// Resolved once at load — the level's anchors against this game's ground, which is simply y = 0.
    private var drawables: [(mesh: LoadedMesh, transform: matrix_float4x4, albedo: SIMD3<Float>)] = []

    private var camera: Camera
    private var previousCamera: Camera
    private var aspectRatio: Float = 1
    private var viewportSize = SIMD2<Float>(1, 1)
    let input = InputState()

    /// Slots for uniforms: one per drawable per frame in flight, so a frame never overwrites one the
    /// GPU is still reading.
    private static let maxDrawables = 128
    private static let uniformStride = (MemoryLayout<Uniforms>.stride + 255) & ~255

    init?(engine: FrameRenderer) {
        self.engine = engine
        let device = engine.device

        let loaded = SampleLevel.load()
        level = loaded.level
        levelPath = loaded.source

        // Spawn where the level says, looking where it says.
        let spawn = level.markers(ofKind: "spawn").first
        var camera = Camera(position: (spawn?.position ?? SIMD3(0, 0, 12)) + SIMD3(0, 1.7, 0))
        camera.yaw = spawn?.yaw ?? 0
        self.camera = camera
        self.previousCamera = camera

        let vertexDescriptor = SampleGame.vertexDescriptor()

        do {
            let library = try ShaderLibrary.make(device: device, bundle: .module, sourceNamed: "SampleShaders")
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "sampleVertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "sampleFragment"

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = "SamplePipeline"
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.vertexDescriptor = vertexDescriptor
            descriptor.colorAttachments[0].pixelFormat = FrameRenderer.colorPixelFormat
                pipeline = try compiler.makeRenderPipelineState(descriptor: descriptor, compilerTaskOptions: nil)
        } catch {
            print("WindageSample: pipeline failed — \(error)")
            return nil
        }

        guard let depthState = engine.makeDepthStencilState() else {
            print("WindageSample: depth state failed")
            return nil
        }
        self.depthState = depthState

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 2
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else {
            print("WindageSample: argument table failed")
            return nil
        }
        argumentTable = table

        guard let buffer = device.makeBuffer(
            length: SampleGame.uniformStride * SampleGame.maxDrawables * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: uniform buffer failed")
            return nil
        }
        uniformBuffer = buffer

        hud = HUDRenderer(device: device)

        // **Everything the GPU reads has to be in the residency set.** A buffer or texture that is
        // not is read as whatever memory happens to be there — which is not a black screen, it is
        // garbage that looks like a shader bug.
        engine.residencySet.addAllocations([uniformBuffer])
        if let hud { engine.residencySet.addAllocations(hud.allocations) }

        // Meshes, then the level resolved against them.
        for name in Set(level.placements.map(\.mesh)) {
            if let mesh = try? MeshLoader.load(named: name, device: device,
                                               vertexDescriptor: vertexDescriptor,
                                               semantics: SampleGame.semantics,
                                               bundle: .module).first {
                meshes[name] = mesh
                engine.residencySet.addAllocations(mesh.mesh.vertexBuffers.map(\.buffer))
                engine.residencySet.addAllocations(mesh.mesh.submeshes.map(\.indexBuffer.buffer))
            } else {
                print("WindageSample: no mesh named \(name)")
            }
        }
        engine.commitResidency()

        // The sample's ground is a plane at zero, so the anchor resolver has a trivial job — but it
        // is still the engine's resolver, because the *meaning* of an anchor is not this game's to
        // reinvent.
        let ground = Level.Ground(heightAt: { _, _ in 0 })
        for placement in level.placements {
            guard let mesh = meshes[placement.mesh] else { continue }
            let position = level.worldPosition(of: placement, on: ground)
            let c = cos(placement.yaw), s = sin(placement.yaw), k = placement.scale
            let transform = matrix_float4x4(columns: (SIMD4(c * k, 0, -s * k, 0),
                                                      SIMD4(0, k, 0, 0),
                                                      SIMD4(s * k, 0, c * k, 0),
                                                      SIMD4(position, 1)))
            drawables.append((mesh, transform, SampleGame.albedo(for: placement)))
        }
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")
    }

    /// Colour by tag, so the level's own labels are visibly doing something.
    private static func albedo(for placement: Level.Placement) -> SIMD3<Float> {
        if placement.tags.contains("ground") { return SIMD3(0.32, 0.34, 0.30) }
        if placement.tags.contains("landmark") { return SIMD3(0.75, 0.45, 0.20) }
        return SIMD3(0.55, 0.57, 0.60)
    }

    private var sunDirection: SIMD3<Float> {
        let pitch = radians_from_degrees(Float(level.settings["sunPitch"] ?? 45))
        let yaw = radians_from_degrees(Float(level.settings["sunYaw"] ?? 135))
        return simd_normalize(SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)))
    }

    // MARK: - GameLoop

    /// **Mouse look is consumed once per frame, not once per step.** A mouse delta is a
    /// displacement that already happened; applying it in a frame that ran three simulation steps
    /// would turn three times as far. The engine's `InputState` says so and the sample obeys it —
    /// this is the sort of thing a consumer gets wrong when the engine only documents it in one
    /// game's source.
    func beginFrame() {
        input.pollFrame()
        camera.look(mouseDelta: input.consumePendingLook())
    }

    func step(deltaTime: Float) {
        previousCamera = camera
        camera.turn(rate: input.lookRate, deltaTime: deltaTime)
        camera.advance(input.movement, deltaTime: deltaTime)
        // Stay on the ground. The sample has no terrain and no gravity — that is a game's job, and
        // pretending otherwise here would put a physics engine in a walkthrough.
        camera.position.y = 1.7
    }

    func viewportChanged(width: Int, height: Int) {
        aspectRatio = Float(width) / Float(max(height, 1))
        viewportSize = SIMD2(Float(width), Float(height))
    }

    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
        let view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
        let projection = matrix_perspective_right_hand_reverse_z(
            fovyRadians: radians_from_degrees(70), aspectRatio: aspectRatio, nearZ: 0.1)
        let viewProjection = simd_mul(projection, view.viewMatrix)

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])

        let base = frameSlot * SampleGame.uniformStride * SampleGame.maxDrawables
        for (index, drawable) in drawables.prefix(SampleGame.maxDrawables).enumerated() {
            let offset = base + index * SampleGame.uniformStride
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: drawable.transform,
                                    normalMatrix: normalMatrix(from: drawable.transform),
                                    albedo: drawable.albedo,
                                    sunDirection: sunDirection)
            uniformBuffer.contents().advanced(by: offset)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
            argumentTable.setAddress(uniformBuffer.gpuAddress + UInt64(offset), index: 1)

            let mesh = drawable.mesh.mesh
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

    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
        guard let hud else { return }
        hud.begin(viewportSize: viewportSize)
        let white = UIColor(srgb: SIMD4(1, 1, 1, 0.9))
        _ = hud.text(level.name, x: 16, y: 20, pointSize: 20, color: white)
        _ = hud.text(String(format: "x %.1f   z %.1f   %d drawables",
                            camera.position.x, camera.position.z, drawables.count),
                     x: 16, y: 46, pointSize: 14, color: white)
        _ = hud.text("WASD move · mouse look · click to capture · esc release", x: 16,
                     y: viewportSize.y - 30, pointSize: 13, color: white)
        _ = hud.text("editing \(levelPath)", x: 16, y: viewportSize.y - 52, pointSize: 11, color: white)
        // A centre dot, so turning has something to turn about.
        hud.rect(x: viewportSize.x / 2 - 2, y: viewportSize.y / 2 - 2, width: 4, height: 4, color: white)
        hud.draw(into: encoder, frameSlot: frameSlot)
    }
}
