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

    /// The level, and the editing on top of it. **The engine owns what an edit *means*** — see
    /// `LevelEditor`; this file only turns clicks and keys into those operations and draws the result.
    private var editor: LevelEditor
    private(set) var isEditing = false
    var isEditingLevel: Bool { isEditing }
    private var level: Level { editor.level }
    private let levelURL: URL
    private let levelPath: String
    private var meshes: [String: LoadedMesh] = [:]
    /// Resolved from the level — anchors against this game's ground, which is simply y = 0.
    /// **Rebuilt whenever the level changes**, because in edit mode it changes constantly.
    private var drawables: [(mesh: LoadedMesh, transform: matrix_float4x4, albedo: SIMD3<Float>)] = []

    /// What the player cannot walk through, and what a click can pick.
    ///
    /// **Both from the same list, on purpose.** Two descriptions of "what is there" drift, and the
    /// day they do you are pointing at something you cannot touch.
    private var volumes: [Volume] = []
    private var solidVolumes: [Volume] = []

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
        editor = LevelEditor(level: loaded.level)
        levelURL = SampleLevel.writableURL
        levelPath = loaded.source

        // Spawn where the level says, looking where it says.
        let spawn = loaded.level.markers(ofKind: "spawn").first
        var camera = Camera(position: (spawn?.position ?? SIMD3(0, 0, 12)) + SIMD3(0, 1.7, 0))
        camera.yaw = spawn?.yaw ?? 0
        camera.pitch = radians_from_degrees(Float(spawn?.values["pitch"] ?? 0))
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

        rebuild()
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")
    }

    /// Turn the level into things to draw, walk into and click on.
    ///
    /// The sample's ground is a plane at zero, so the anchor resolver has a trivial job — but it is
    /// still the *engine's* resolver, because what an anchor means is not this game's to reinvent.
    private func rebuild() {
        drawables.removeAll(keepingCapacity: true)
        volumes.removeAll(keepingCapacity: true)
        solidVolumes.removeAll(keepingCapacity: true)
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
            let volume = Volume(local: mesh.bounds, transform: transform)
            volumes.append(volume)
            // **The level's own tag decides.** The engine has no idea what "solid" means; this game
            // does. Shipping the tag and then ignoring it — which this sample did on its first
            // run — is worse than not having it, because the file says something untrue.
            if placement.tags.contains("solid") { solidVolumes.append(volume) }
        }
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

    // MARK: - Editing

    /// Keys the editor takes, by macOS key code. Returns whether it consumed the event.
    ///
    /// **Consumed keys never reach `InputState`**, so `D` nudges rather than strafing. Routing every
    /// key to both and hoping they do not collide is how an editor ends up walking the camera into a
    /// wall while you are trying to move a crate.
    func handleKey(_ code: UInt16, command: Bool) -> Bool {
        if code == 48 {                                     // tab — in and out of edit mode
            isEditing.toggle()
            input.setMouseCaptured(!isEditing)
            return true
        }
        guard isEditing else { return false }

        if command {
            switch code {
            case 1:                                          // cmd-S — save
                do {
                    try editor.save(to: levelURL)
                    print("WindageSample: saved \(levelURL.path)")
                } catch { print("WindageSample: save failed — \(error)") }
            case 6: editor.undo(); rebuild()                 // cmd-Z
            case 15: editor.redo(); rebuild()                // cmd-R
            default: return false
            }
            return true
        }

        // Nudges are along the world axes rather than the camera's, so a number typed into the file
        // afterwards means the same thing as a key pressed here.
        let d = LevelEditor.nudge
        switch code {
        case 123: editor.move(by: SIMD3(-d, 0, 0))           // ←
        case 124: editor.move(by: SIMD3(d, 0, 0))            // →
        case 126: editor.move(by: SIMD3(0, 0, -d))           // ↑ — away, down the -z the camera faces
        case 125: editor.move(by: SIMD3(0, 0, d))            // ↓
        case 12: editor.move(by: SIMD3(0, d, 0))             // q — up
        case 14: editor.move(by: SIMD3(0, -d, 0))            // e — down
        case 0: editor.rotate(by: -LevelEditor.turn)         // a
        case 2: editor.rotate(by: LevelEditor.turn)          // d
        case 27: editor.scale(by: 1 / 1.25)                  // -
        case 24: editor.scale(by: 1.25)                      // =
        case 51, 117: editor.delete()                        // delete / fn-delete
        case 11: editor.duplicate()                          // b — duplicate
        case 49: pickUnderCrosshair(); return true           // space — pick, for hands already on
                                                             // the keys and for automated checks
        default: return false
        }
        rebuild()
        return true
    }

    /// Pick whatever is under the middle of the screen.
    ///
    /// Down the crosshair rather than from the mouse position: the sample captures the pointer for
    /// look, so there *is* no mouse position while playing, and a picker that needed one would only
    /// work in a mode the sample does not have.
    func pickUnderCrosshair() {
        let origin = camera.position
        let hit = Volume.firstHit(origin: origin, direction: camera.forward, against: volumes,
                                  maxDistance: 200)
        editor.select(hit?.index)
        rebuild()
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
        // In edit mode the movement keys are the editor's, so the camera holds still.
        if !isEditing {
            let before = camera.position
            camera.advance(input.movement, deltaTime: deltaTime)
            // Stay on the ground. The sample has no terrain and no gravity — that is a game's job,
            // and pretending otherwise here would put a physics engine in a walkthrough.
            camera.position.y = 1.7
            camera.position = resolved(from: before, to: camera.position)
        }
    }

    /// Where a step actually ends, given that solid things are solid.
    ///
    /// **Each axis retried on its own**, so walking into a wall at an angle slides along it rather
    /// than sticking. Refusing the whole move is what makes a wall feel like glue, and is also the
    /// only way out of a corner.
    private func resolved(from start: SIMD3<Float>, to end: SIMD3<Float>) -> SIMD3<Float> {
        guard blocked(end) else { return end }
        let alongX = SIMD3(end.x, end.y, start.z)
        if !blocked(alongX) { return alongX }
        let alongZ = SIMD3(start.x, end.y, end.z)
        if !blocked(alongZ) { return alongZ }
        return start
    }

    /// The player is a cylinder, approximated by testing a short segment through where they stand.
    private static let playerRadius: Float = 0.4

    private func blocked(_ position: SIMD3<Float>) -> Bool {
        let r = SampleGame.playerRadius
        // Four probes around the player's waist. A single point walks through a wall corner-first.
        for offset in [SIMD3<Float>(r, 0, 0), SIMD3(-r, 0, 0), SIMD3(0, 0, r), SIMD3(0, 0, -r)] {
            let point = position + offset - SIMD3(0, 0.9, 0)
            if solidVolumes.contains(where: { $0.worldBounds.contains(point) }) { return true }
        }
        return false
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
            // The selection glows, because an editor where you cannot tell what is selected is a
            // way to move the wrong thing.
            let albedo = (isEditing && index == editor.selection)
                ? SIMD3<Float>(1.0, 0.85, 0.25) : drawable.albedo
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: drawable.transform,
                                    normalMatrix: normalMatrix(from: drawable.transform),
                                    albedo: albedo,
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
        if isEditing {
            let gold = UIColor(srgb: SIMD4(1.0, 0.85, 0.25, 1))
            let what = editor.selected.map { "\($0.mesh)  yaw \(Int($0.yaw * 180 / .pi))°  scale \(String(format: "%.2f", $0.scale))" }
            _ = hud.text("EDIT\(editor.isDirty ? " •" : "")   \(what ?? "nothing selected — click the crosshair at something")",
                         x: 16, y: 72, pointSize: 15, color: gold)
            _ = hud.text("click pick · ←→↑↓ move · q/e up-down · a/d turn · -/= scale · b copy · ⌫ delete",
                         x: 16, y: viewportSize.y - 52, pointSize: 13, color: white)
            _ = hud.text("⌘S save · ⌘Z undo · ⌘R redo · tab back to walking", x: 16,
                         y: viewportSize.y - 30, pointSize: 13, color: white)
        } else {
            _ = hud.text("WASD move · mouse look · click to capture · esc release · TAB to edit", x: 16,
                         y: viewportSize.y - 30, pointSize: 13, color: white)
            _ = hud.text("editing \(levelPath)", x: 16, y: viewportSize.y - 52, pointSize: 11, color: white)
        }
        // A centre dot, so turning has something to turn about.
        hud.rect(x: viewportSize.x / 2 - 2, y: viewportSize.y / 2 - 2, width: 4, height: 4, color: white)
        hud.draw(into: encoder, frameSlot: frameSlot)
    }
}
