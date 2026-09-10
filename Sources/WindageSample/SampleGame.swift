//
//  SampleGame.swift
//  WindageSample
//

import AppKit
import Metal
import MetalKit
import simd
import WindageEngine
import WindageSampleCore

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

    /// The same, plus the two attributes that make a mesh skinnable.
    ///
    /// **A separate layout and therefore a separate pipeline.** Putting joints and weights on every
    /// vertex in the level would double the size of a courtyard's geometry to say "no joint" 40,000
    /// times.
    static let skinnedSemantics: [Int: String] = [
        0: MDLVertexAttributePosition,
        1: MDLVertexAttributeNormal,
        2: MDLVertexAttributeJointIndices,
        3: MDLVertexAttributeJointWeights,
    ]

    /// **Four influences per vertex, whatever the file holds.** The sample's figure is authored with
    /// two; Model I/O pads the rest with a joint index of 0 and a weight of 0, which contributes
    /// nothing — measured, not assumed. Four is what a bought character will bring.
    static func skinnedVertexDescriptor() -> MTLVertexDescriptor {
        let descriptor = vertexDescriptor()
        descriptor.attributes[2].format = .ushort4
        descriptor.attributes[2].offset = 24
        descriptor.attributes[2].bufferIndex = 0
        descriptor.attributes[3].format = .float4
        descriptor.attributes[3].offset = 32
        descriptor.attributes[3].bufferIndex = 0
        descriptor.layouts[0].stride = 48
        return descriptor
    }

    /// One animated character: the rig, where it stands, and where it is in its two clips.
    ///
    /// **The pose is kept between frames rather than rebuilt**, because it owns its arrays — posing
    /// a character allocates nothing, and that only holds if the character keeps its pose.
    private struct Figure {
        var pose: SkeletonPose
        var idle: AnimationPlayhead
        var wave: AnimationPlayhead
        /// How much of the wave is showing, 0…1. Eased toward a target so a player walking past
        /// does not switch a character between clips in one frame.
        var waveWeight: Float = 0
        let transform: matrix_float4x4
        let position: SIMD3<Float>
    }

    private struct Uniforms {
        var viewProjection: matrix_float4x4
        var model: matrix_float4x4
        var normalMatrix: matrix_float3x3
        var albedo: SIMD3<Float>
        var sunDirection: SIMD3<Float>
    }

    /// Mirrors `ShadowFrame` in `SampleShaders.metal`. **Frame-wide, so it is written once** — four
    /// matrices copied into every drawable's uniforms would multiply them by the object count for
    /// nothing.
    private struct ShadowFrame {
        var cascadeViewProjection: (matrix_float4x4, matrix_float4x4, matrix_float4x4, matrix_float4x4)
        var cascadeSplits: SIMD4<Float>
        var cascadeBlendStart: SIMD4<Float>
        var cascadeDepthBias: SIMD4<Float>
        var cameraPosition: SIMD3<Float>
        var texelSize: Float
    }
    private static let shadowFrameStride = (MemoryLayout<ShadowFrame>.stride + 255) & ~255

    private let engine: FrameRenderer
    private let pipeline: MTLRenderPipelineState
    /// **Optional: no skinned pipeline means no characters, not no sample.**
    private let skinnedPipeline: MTLRenderPipelineState?
    private let depthState: MTLDepthStencilState
    private let hud: HUDRenderer?

    /// **Optional, and the game runs without it.** A machine with no output device, or an audio
    /// engine that will not start, must not stop somebody seeing the sample — sound is the first
    /// thing to go wrong on someone else's hardware and the last thing that should be fatal.
    private let audio: AudioEngine?
    private let argumentTable: MTL4ArgumentTable
    private let uniformBuffer: MTLBuffer

    /// **Optional like the audio.** A machine that cannot build the shadow pipeline should still
    /// show the sample, unlit rather than not at all.
    private let shadowMap: SampleShadowMap?
    /// Frame-wide shadow data — written once a frame, not once per object.
    private let shadowFrameBuffer: MTLBuffer

    /// The level, and the editing on top of it. **The engine owns what an edit *means*** — see
    /// `LevelEditor`; this file only turns clicks and keys into those operations and draws the result.
    private var editor: LevelEditor
    private(set) var isEditing = false
    var isEditingLevel: Bool { isEditing }
    private var level: Level { editor.level }
    /// Which level is loaded. **`var`, and that is the whole point of this pass** — everything about
    /// this game assumed one level, loaded once, because there had only ever been one.
    private var levelIndex = 0
    private var levelURL: URL { SampleLevel.writableURL(levelIndex) }
    private var levelPath: String
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
    /// Which drawables are objectives, so a collected one can go dark without searching the level.
    private var objectiveDrawables: [Int] = []

    /// The character mesh and the rig it wears — loaded once, shared by every figure in the level.
    ///
    /// **A `Skeleton` is structure, not pose**, so one of these serves any number of characters; what
    /// is per-character is the ``SkeletonPose`` inside each ``Figure``.
    private var figureMesh: LoadedMesh?
    private var figureRig: Rig?
    private var figures: [Figure] = []

    private var run: SampleRun
    /// Seconds left on the pause between winning and the next level, or nil.
    private var advanceAfterWinning: Double?
    private var camera: Camera
    private var previousCamera: Camera
    private var aspectRatio: Float = 1
    private var viewportSize = SIMD2<Float>(1, 1)
    let input = InputState()

    /// Slots for uniforms: one per drawable per frame in flight, so a frame never overwrites one the
    /// GPU is still reading.
    /// Uniform slots per frame, and therefore the hard ceiling on things drawn.
    ///
    /// **Being over it silently drops the tail of the scene** — the same fault that once made
    /// a viewmodel disappear from the player's hands and read as a rendering bug. `rebuild()`
    /// says so out loud rather than leaving it to be discovered.
    private static let maxDrawables = 128
    private static let uniformStride = (MemoryLayout<Uniforms>.stride + 255) & ~255

    /// Figures take uniform slots after the level's drawables, in the same buffer.
    private static let maxFigures = 8
    private static let uniformSlots = maxDrawables + maxFigures

    /// **A ceiling, not the rig's joint count.** The buffer is allocated before any rig is loaded,
    /// so it has to be sized for a plausible character rather than for the one that turns up. A
    /// hundred joints is a humanoid with fingers.
    private static let maxJoints = 128
    private static let jointPaletteStride =
        (MemoryLayout<matrix_float4x4>.stride * maxJoints + 255) & ~255
    private let jointBuffer: MTLBuffer

    init?(engine: FrameRenderer) {
        self.engine = engine
        let device = engine.device

        let loaded = SampleLevel.load(0)
        editor = LevelEditor(level: loaded.level)
        levelPath = loaded.report

        run = SampleRun(objectives: loaded.level.markers(ofKind: "objective").map(\.position),
                        levelName: loaded.level.name)

        // Spawn where the level says, looking where it says.
        let spawn = loaded.level.markers(ofKind: "spawn").first
        var camera = Camera(position: (spawn?.position ?? SIMD3(0, 0, 12)) + SIMD3(0, 1.7, 0))
        camera.yaw = spawn?.yaw ?? 0
        camera.pitch = radians_from_degrees(Float(spawn?.values["pitch"] ?? 0))
        self.camera = camera
        self.previousCamera = camera

        let vertexDescriptor = SampleGame.vertexDescriptor()

        let shaderLibrary: MTLLibrary
        do {
            shaderLibrary = try ShaderLibrary.make(device: device, bundle: .module, sourceNamed: "SampleShaders")
        } catch {
            print("WindageSample: shader library failed — \(error)")
            return nil
        }

        do {
            let library = shaderLibrary
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

            // The skinned pipeline differs only in its vertex function and its layout — same
            // fragment shader, so a character is lit and shadowed by exactly the code the rest of
            // the scene is. Two fragment shaders that are meant to match is how a character ends up
            // subtly the wrong brightness.
            let skinnedVertex = MTL4LibraryFunctionDescriptor()
            skinnedVertex.library = library
            skinnedVertex.name = "sampleSkinnedVertex"
            descriptor.label = "SampleSkinnedPipeline"
            descriptor.vertexFunctionDescriptor = skinnedVertex
            descriptor.vertexDescriptor = SampleGame.skinnedVertexDescriptor()
            skinnedPipeline = try compiler.makeRenderPipelineState(descriptor: descriptor,
                                                                   compilerTaskOptions: nil)
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
        // 0: vertex buffer · 1: per-object uniforms · 2: the frame's shadow data · 3: joints.
        tableDescriptor.maxBufferBindCount = 4
        tableDescriptor.maxTextureBindCount = 1
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor) else {
            print("WindageSample: argument table failed")
            return nil
        }
        argumentTable = table

        guard let buffer = device.makeBuffer(
            length: SampleGame.uniformStride * SampleGame.uniformSlots * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: uniform buffer failed")
            return nil
        }
        uniformBuffer = buffer

        // One palette per figure per frame in flight — **per frame in flight**, because the GPU is
        // still reading the previous frame's pose while this one is written. Sharing one palette
        // across frames is the animation version of tearing.
        guard let joints = device.makeBuffer(
            length: SampleGame.jointPaletteStride * SampleGame.maxFigures * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: joint palette buffer failed")
            return nil
        }
        joints.label = "Joint Palettes"
        jointBuffer = joints

        guard let shadowFrames = device.makeBuffer(
            length: SampleGame.shadowFrameStride * FrameRenderer.maxFramesInFlight,
            options: .storageModeShared) else {
            print("WindageSample: shadow frame buffer failed")
            return nil
        }
        shadowFrameBuffer = shadowFrames

        shadowMap = SampleShadowMap(device: device, library: shaderLibrary,
                                    vertexDescriptor: vertexDescriptor,
                                    skinnedVertexDescriptor: SampleGame.skinnedVertexDescriptor())
        if shadowMap == nil { print("WindageSample: no shadows — the scene will be flat-lit") }

        // **The hint lines use keyboard symbols, so the atlas has to carry them.** It is ASCII by
        // default, and a character it does not carry draws nothing at all — which is how these
        // hints spent several sessions reading "S save  Z undo" with the ⌘ silently missing.
        hud = HUDRenderer(device: device, additionalCharacters: ["⌘", "⌫", "·", "°", "•"])

        audio = AudioEngine()
        if let audio {
            // **From this module's bundle, not `.main`.** `AudioEngine.load` defaults to `.main`,
            // which for a SwiftPM executable is the executable itself and holds no resources — the
            // sounds live in the target's own bundle.
            for sound in ["pickup", "win", "lose"] where !audio.load(sound, bundle: .module) {
                print("WindageSample: no sound named \(sound)")
            }
        } else {
            print("WindageSample: no audio — the game runs, it is just quiet")
        }

        // **Everything the GPU reads has to be in the residency set.** A buffer or texture that is
        // not is read as whatever memory happens to be there — which is not a black screen, it is
        // garbage that looks like a shader bug.
        engine.residencySet.addAllocations([uniformBuffer, shadowFrameBuffer, jointBuffer])
        if let shadowMap { engine.residencySet.addAllocations(shadowMap.allocations) }
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
        loadFigureAsset()
        engine.commitResidency()

        rebuild()
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")
    }

    /// Loads the rigged figure: one mesh, one skeleton, two clips, all from one USD file.
    ///
    /// **Everything about the rig comes out of the file** — the joint hierarchy, the bind pose and
    /// both clips. Nothing about this figure is written into this game, which is the check that
    /// matters: a loader that only works on a rig the programmer already knows is not a loader.
    private func loadFigureAsset() {
        guard skinnedPipeline != nil else { return }
        do {
            figureRig = try RigLoader.load(named: "figure", withExtension: "usda", bundle: .module)
        } catch {
            print("WindageSample: no figure rig — \(error)")
            return
        }
        guard let mesh = try? MeshLoader.load(named: "figure", withExtension: "usda",
                                              device: engine.device,
                                              vertexDescriptor: SampleGame.skinnedVertexDescriptor(),
                                              semantics: SampleGame.skinnedSemantics,
                                              bundle: .module).first else {
            print("WindageSample: no figure mesh")
            figureRig = nil
            return
        }
        figureMesh = mesh
        engine.residencySet.addAllocations(mesh.mesh.vertexBuffers.map(\.buffer))
        engine.residencySet.addAllocations(mesh.mesh.submeshes.map(\.indexBuffer.buffer))

        if let rig = figureRig {
            print("WindageSample: figure rig — \(rig.skeleton.jointCount) joints, clips: "
                  + rig.clips.map(\.name).joined(separator: ", "))
            if rig.skeleton.jointCount > SampleGame.maxJoints {
                print("WindageSample: WARNING the rig has more joints than the palette holds")
                figureRig = nil
            }
        }
    }

    /// Places a figure wherever the level puts a `figure` marker.
    ///
    /// **From the level file, like everything else in the scene.** A character hard-coded into the
    /// game would not prove the level format can carry one, and moving it would mean a rebuild.
    private func rebuildFigures() {
        figures.removeAll(keepingCapacity: true)
        guard let rig = figureRig, let idleClip = rig.clip(named: "Idle"),
              let waveClip = rig.clip(named: "Wave") else { return }

        for marker in level.markers(ofKind: "figure").prefix(SampleGame.maxFigures) {
            let yaw = marker.yaw
            let c = cos(yaw), s = sin(yaw)
            let transform = matrix_float4x4(columns: (SIMD4(c, 0, -s, 0),
                                                      SIMD4(0, 1, 0, 0),
                                                      SIMD4(s, 0, c, 0),
                                                      SIMD4(marker.position, 1)))
            var figure = Figure(pose: SkeletonPose(skeleton: rig.skeleton),
                                idle: AnimationPlayhead(clip: idleClip, skeleton: rig.skeleton),
                                wave: AnimationPlayhead(clip: waveClip, skeleton: rig.skeleton),
                                transform: transform,
                                position: marker.position)
            // **Started at different points in the clip.** A row of characters moving in lockstep
            // reads as one object drawn several times, which is exactly what it is.
            figure.idle.advance(by: Float(figures.count) * 0.9)
            figures.append(figure)
        }
    }

    /// Turn the level into things to draw, walk into and click on.
    ///
    /// The sample's ground is a plane at zero, so the anchor resolver has a trivial job — but it is
    /// still the *engine's* resolver, because what an anchor means is not this game's to reinvent.
    private func rebuild() {
        drawables.removeAll(keepingCapacity: true)
        volumes.removeAll(keepingCapacity: true)
        solidVolumes.removeAll(keepingCapacity: true)
        objectiveDrawables.removeAll(keepingCapacity: true)
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
            if placement.tags.contains("objective") { objectiveDrawables.append(drawables.count - 1) }
            let volume = Volume(local: mesh.bounds, transform: transform)
            volumes.append(volume)
            // **The level's own tag decides.** The engine has no idea what "solid" means; this game
            // does. Shipping the tag and then ignoring it — which this sample did on its first
            // run — is worse than not having it, because the file says something untrue.
            if placement.tags.contains("solid") { solidVolumes.append(volume) }
        }
        rebuildFigures()
        if drawables.count > SampleGame.maxDrawables {
            print("WindageSample: WARNING \(drawables.count) drawables against a cap of "
                  + "\(SampleGame.maxDrawables) — the rest of the level will not be drawn")
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

    // MARK: - Levels

    /// Load a different level **while the game is running**.
    ///
    /// **Three things here were assumptions, not code, until there was a second level.** Meshes were
    /// loaded once in `init` from the first level's list, so a level using anything new drew nothing.
    /// The camera was placed in `init`, so a new spawn was ignored. And the run was sized once, so a
    /// level with a different number of objectives could not be finished. None of them would have
    /// been found by a second *copy* of the first level — only by one that differs.
    func load(level index: Int) {
        levelIndex = (index + SampleLevel.names.count) % SampleLevel.names.count
        let loaded = SampleLevel.load(levelIndex)
        editor = LevelEditor(level: loaded.level)
        levelPath = loaded.report

        loadMissingMeshes()
        rebuild()

        // Spawn where *this* level says, not where the last one did.
        let spawn = level.markers(ofKind: "spawn").first
        camera.position = (spawn?.position ?? SIMD3(0, 0, 12)) + SIMD3(0, 1.7, 0)
        camera.yaw = spawn?.yaw ?? 0
        camera.pitch = radians_from_degrees(Float(spawn?.values["pitch"] ?? 0))
        previousCamera = camera

        // A fresh run, sized from this level's objectives — and keeping the progress, which is the
        // player's rather than the level's.
        run = SampleRun(objectives: level.markers(ofKind: "objective").map(\.position),
                        levelName: level.name)
        print("WindageSample: '\(level.name)' — \(drawables.count) drawables from \(levelPath)")
    }

    /// Loads any mesh this level needs that is not already in memory.
    ///
    /// **Additive rather than a reload.** Levels share most of their meshes, and throwing the lot away
    /// on every switch would stall for no reason — but a mesh has to be in the residency set before
    /// the GPU can reach it, so a newly loaded one joins it and the set is committed again.
    private func loadMissingMeshes() {
        var added: [any MTLAllocation] = []
        for name in Set(level.placements.map(\.mesh)) where meshes[name] == nil {
            guard let mesh = try? MeshLoader.load(named: name, device: engine.device,
                                                  vertexDescriptor: SampleGame.vertexDescriptor(),
                                                  semantics: SampleGame.semantics,
                                                  bundle: .module).first else {
                print("WindageSample: no mesh named \(name)")
                continue
            }
            meshes[name] = mesh
            added += mesh.mesh.vertexBuffers.map(\.buffer)
            added += mesh.mesh.submeshes.map(\.indexBuffer.buffer)
        }
        if !added.isEmpty {
            engine.residencySet.addAllocations(added)
            engine.commitResidency()
        }
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
        // These work whether or not the editor is open, because a paused game you cannot unpause
        // is a hang with a label on it.
        switch code {
        case 35: run.togglePause(); return true              // p
        case 15: if !command { run.restart(); return true }  // r — but ⌘R is redo
        case 45: load(level: levelIndex + 1); return true    // n — next level
        default: break
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
            case 51:                                         // cmd-⌫ — throw the edited copy away
                // **The way back to the level this repository ships.** Once the editor has saved,
                // that copy shadows the shipped file for ever, so editing `courtyard.json` in the
                // source tree appears to do nothing. Without this the only cure is knowing where
                // Application Support is.
                if SampleLevel.discardEdits(levelIndex) {
                    print("WindageSample: discarded the edited copy")
                } else {
                    print("WindageSample: there was no edited copy to discard")
                }
                load(level: levelIndex)
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
        // **A pause is "do not advance", not "stop the loop".** The frame loop keeps running, the
        // scene still draws and the window still resizes — which is why pausing is a game's decision
        // and not something the engine has to provide.
        if !isEditing {
            let events = run.step(deltaTime: Double(deltaTime), playerAt: camera.position)
            if !events.isEmpty { rebuild() }          // a collected crate changes colour
            for crate in events.collected {
                // **At the crate, not at the player.** The whole reason the engine spatialises is
                // that a sound should come from where the thing is; playing it flat would make the
                // positional path untested by the one consumer meant to exercise it.
                audio?.play("pickup", at: crate + SIMD3(0, 1, 0))
            }
            if events.won {
                audio?.play("win")
                // **Winning moves you on.** A game that ends and sits there is a game that stopped;
                // this is the smallest progression there is, and it is what makes a second level
                // part of the loop rather than a thing you have to ask for.
                advanceAfterWinning = 2.5
            }
            if events.lost { audio?.play("lose") }
        }

        if var wait = advanceAfterWinning {
            wait -= Double(deltaTime)
            if wait <= 0 {
                advanceAfterWinning = nil
                load(level: levelIndex + 1)
            } else {
                advanceAfterWinning = wait
            }
        }

        animateFigures(deltaTime: deltaTime)

        // Where the ears are. Once per step is more often than needed — once per frame would do —
        // but it costs two vector writes and cannot go stale.
        audio?.updateListener(position: camera.position, forward: camera.forward, up: SIMD3(0, 1, 0))

        // In edit mode the movement keys are the editor's, so the camera holds still. So is a
        // finished run: walking around after the clock stops reads as the game not having noticed.
        if !isEditing && !run.isOver && run.mode != .paused {
            let before = camera.position
            camera.advance(input.movement, deltaTime: deltaTime)
            // Stay on the ground. The sample has no terrain and no gravity — that is a game's job,
            // and pretending otherwise here would put a physics engine in a walkthrough.
            camera.position.y = 1.7
            camera.position = resolved(from: before, to: camera.position)
        }
    }

    /// How far away a figure notices the player. Chosen so a figure is waving by the time you are
    /// close enough to read the blend rather than after you have walked past it.
    private static let noticeDistance: Float = 7

    /// Advances every figure's clips and blends between them.
    ///
    /// **This is the whole animation update, and it is nine lines.** Everything expensive —
    /// sampling, the parent chain, the cross-fade — is `SkeletonPose.set(to:blendedWith:weight:)`,
    /// and the game's part is deciding *what* to play. That split is the point: a game that had to
    /// walk a joint hierarchy to make a character wave would have an engine that had not finished
    /// the job.
    ///
    /// **Runs while editing and while paused.** A frozen character in a paused game looks broken in
    /// a way a frozen crate does not.
    private func animateFigures(deltaTime: Float) {
        for index in figures.indices {
            figures[index].idle.advance(by: deltaTime)
            figures[index].wave.advance(by: deltaTime)

            let distance = simd_distance(figures[index].position, camera.position)
            let target: Float = distance < SampleGame.noticeDistance ? 1 : 0
            // Eased rather than switched. A cross-fade is the only reason the pose keeps rotation as
            // a quaternion, and snapping between clips would waste it — a quarter of a second is
            // about where a hand-over stops reading as a glitch.
            let rate = min(deltaTime / 0.25, 1)
            figures[index].waveWeight += (target - figures[index].waveWeight) * rate

            figures[index].pose.set(to: figures[index].idle,
                                    blendedWith: figures[index].wave,
                                    weight: figures[index].waveWeight)
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

    private func uniformOffset(frameSlot: Int, drawable index: Int) -> Int {
        frameSlot * SampleGame.uniformStride * SampleGame.uniformSlots + index * SampleGame.uniformStride
    }

    /// Figures take the slots after the level's drawables in the same buffer.
    private func uniformOffset(frameSlot: Int, figure index: Int) -> Int {
        uniformOffset(frameSlot: frameSlot, drawable: SampleGame.maxDrawables + index)
    }

    private func jointOffset(frameSlot: Int, figure index: Int) -> Int {
        (frameSlot * SampleGame.maxFigures + index) * SampleGame.jointPaletteStride
    }

    private var visibleFigureCount: Int { min(figures.count, SampleGame.maxFigures) }

    private var visibleDrawableCount: Int { min(drawables.count, SampleGame.maxDrawables) }

    /// **Written before the shadow pass, not during the main one.** The shadow pass reads the same
    /// `model` matrix the main pass will; writing them in `encode` would record shadows from last
    /// frame's positions, which reads as shadows lagging behind their casters.
    private func writeUniforms(frameSlot: Int, interpolation: Float) {
        let view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
        let projection = matrix_perspective_right_hand_reverse_z(
            fovyRadians: radians_from_degrees(70), aspectRatio: aspectRatio, nearZ: 0.1)
        let viewProjection = simd_mul(projection, view.viewMatrix)

        for (index, drawable) in drawables.prefix(SampleGame.maxDrawables).enumerated() {
            // The selection glows, because an editor where you cannot tell what is selected is a
            // way to move the wrong thing.
            var albedo = drawable.albedo
            // An objective still to reach is bright; one already touched goes dull, so progress is
            // visible in the world and not only in the corner of the screen.
            if let slot = objectiveDrawables.firstIndex(of: index) {
                albedo = run.collected.indices.contains(slot) && run.collected[slot]
                    ? SIMD3(0.30, 0.34, 0.30) : SIMD3(0.30, 0.80, 0.45)
            }
            if isEditing && index == editor.selection { albedo = SIMD3(1.0, 0.85, 0.25) }
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: drawable.transform,
                                    normalMatrix: normalMatrix(from: drawable.transform),
                                    albedo: albedo,
                                    sunDirection: sunDirection)
            uniformBuffer.contents().advanced(by: uniformOffset(frameSlot: frameSlot, drawable: index))
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)
        }

        for (index, figure) in figures.prefix(SampleGame.maxFigures).enumerated() {
            var uniforms = Uniforms(viewProjection: viewProjection,
                                    model: figure.transform,
                                    normalMatrix: normalMatrix(from: figure.transform),
                                    // Warm, so a figure reads as a person rather than as another
                                    // crate the level forgot to tag.
                                    albedo: SIMD3(0.78, 0.62, 0.44),
                                    sunDirection: sunDirection)
            uniformBuffer.contents().advanced(by: uniformOffset(frameSlot: frameSlot, figure: index))
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.size)

            // The palette straight out of the pose — no conversion, because `skinningMatrices` is
            // already exactly what the vertex shader indexes.
            figure.pose.skinningMatrices.withUnsafeBytes { source in
                jointBuffer.contents().advanced(by: jointOffset(frameSlot: frameSlot, figure: index))
                    .copyMemory(from: source.baseAddress!, byteCount: source.count)
            }
        }
    }

    /// The shadow pass, before anything is drawn to the screen.
    func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float) {
        writeUniforms(frameSlot: frameSlot, interpolation: interpolation)
        guard let shadowMap else { return }

        let view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
        let matrices = shadowMap.updateMatrices(frameSlot: frameSlot, camera: view,
                                                sunDirection: sunDirection)

        let cascades = SampleShadowMap.cascades
        var frame = ShadowFrame(
            cascadeViewProjection: (matrices[0], matrices[1], matrices[2], matrices[3]),
            cascadeSplits: cascades.splitVector,
            cascadeBlendStart: cascades.blendStartVector,
            cascadeDepthBias: cascades.depthBiasVector,
            cameraPosition: view.position,
            texelSize: 1 / Float(cascades.resolution))
        shadowFrameBuffer.contents().advanced(by: frameSlot * SampleGame.shadowFrameStride)
            .copyMemory(from: &frame, byteCount: MemoryLayout<ShadowFrame>.size)

        var batches = [SampleShadowMap.Batch(
            pipeline: shadowMap.staticPipeline,
            count: visibleDrawableCount,
            mesh: { self.drawables[$0].mesh.mesh },
            uniformAddress: { self.uniformBuffer.gpuAddress
                + UInt64(self.uniformOffset(frameSlot: frameSlot, drawable: $0)) },
            jointPaletteAddress: nil)]

        if let skinned = shadowMap.skinnedPipeline, let mesh = figureMesh, visibleFigureCount > 0 {
            batches.append(SampleShadowMap.Batch(
                pipeline: skinned,
                count: visibleFigureCount,
                mesh: { _ in mesh.mesh },
                uniformAddress: { self.uniformBuffer.gpuAddress
                    + UInt64(self.uniformOffset(frameSlot: frameSlot, figure: $0)) },
                jointPaletteAddress: { self.jointBuffer.gpuAddress
                    + UInt64(self.jointOffset(frameSlot: frameSlot, figure: $0)) }))
        }

        shadowMap.encode(into: commandBuffer, frameSlot: frameSlot, batches: batches)
    }

    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setArgumentTable(argumentTable, stages: [.vertex, .fragment])

        argumentTable.setAddress(
            shadowFrameBuffer.gpuAddress + UInt64(frameSlot * SampleGame.shadowFrameStride), index: 2)
        if let shadowMap { argumentTable.setTexture(shadowMap.texture.gpuResourceID, index: 0) }

        for (index, drawable) in drawables.prefix(SampleGame.maxDrawables).enumerated() {
            argumentTable.setAddress(
                uniformBuffer.gpuAddress + UInt64(uniformOffset(frameSlot: frameSlot, drawable: index)),
                index: 1)

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

        encodeFigures(into: encoder, frameSlot: frameSlot)
    }

    /// The characters, in one pipeline change rather than one per object.
    ///
    /// **Same fragment shader, same shadow map, same uniforms** — a skinned mesh differs from the
    /// rest of the scene in exactly two things: where its vertices are and what moved them there.
    private func encodeFigures(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
        guard let skinnedPipeline, let mesh = figureMesh?.mesh, visibleFigureCount > 0 else { return }
        encoder.setRenderPipelineState(skinnedPipeline)

        for index in 0..<visibleFigureCount {
            argumentTable.setAddress(
                uniformBuffer.gpuAddress + UInt64(uniformOffset(frameSlot: frameSlot, figure: index)),
                index: 1)
            argumentTable.setAddress(
                jointBuffer.gpuAddress + UInt64(jointOffset(frameSlot: frameSlot, figure: index)),
                index: 3)

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

        // **Sized against the drawable, not in raw pixels.** The viewport is in *pixels*, and on a
        // Retina display that is twice the points — so text asked for at "20" rendered at ten points
        // and was reported as unreadable. Scaling against a 1080-pixel reference is
        // resolution-independent rather than tuned to one machine.
        let scale = max(viewportSize.y / 1080, 0.75)
        let title = 30 * scale, body = 21 * scale, hint = 17 * scale
        let margin = 22 * scale
        let white = UIColor(srgb: SIMD4(1, 1, 1, 0.95))
        let gold = UIColor(srgb: SIMD4(1.0, 0.85, 0.25, 1))
        let green = UIColor(srgb: SIMD4(0.45, 0.95, 0.6, 1))
        let red = UIColor(srgb: SIMD4(1.0, 0.45, 0.4, 1))

        // **`y` is a baseline and glyphs draw upward from it**, so the first line starts a full
        // line-height down or its ascenders run off the top edge — which is what "COURTYARD touches
        // the top" was.
        var y = margin + title
        _ = hud.text("\(level.name)   \(levelIndex + 1)/\(SampleLevel.names.count)",
                     x: margin, y: y, pointSize: title, color: white)
        y += title * 1.5

        let clock = String(format: "%02d:%02d", Int(run.remaining) / 60, Int(run.remaining) % 60)
        _ = hud.text("CRATES \(run.found)/\(run.objectives.count)     \(clock)",
                     x: margin, y: y,
                     pointSize: body, color: run.remaining < 15 ? red : white)
        y += body * 1.4

        if let best = run.best {
            _ = hud.text(String(format: "best %.1fs   ·   %d of %d runs won",
                                best, run.progress.wins, run.progress.runs),
                         x: margin, y: y, pointSize: hint, color: white)
        } else {
            _ = hud.text("no run finished yet", x: margin, y: y, pointSize: hint, color: white)
        }
        y += hint * 1.6

        switch run.mode {
        case .paused:
            _ = hud.text("PAUSED — p to resume", x: margin, y: y, pointSize: body, color: gold)
        case .won(let seconds):
            _ = hud.text(String(format: "ALL FOUND in %.1fs — r to run again", seconds),
                         x: margin, y: y, pointSize: body, color: green)
        case .lost:
            _ = hud.text("OUT OF TIME — r to run again", x: margin, y: y, pointSize: body, color: red)
        case .playing:
            break
        }

        if isEditing {
            let what = editor.selected.map {
                "\($0.mesh)  yaw \(Int($0.yaw * 180 / .pi))°  scale \(String(format: "%.2f", $0.scale))"
            }
            _ = hud.text("EDIT\(editor.isDirty ? " •" : "")   \(what ?? "aim and click to pick")",
                         x: margin, y: y + body * 1.4, pointSize: body, color: gold)
            _ = hud.text("click pick · arrows move · q/e up · a/d turn · -/= scale · b copy · ⌫ delete",
                         x: margin, y: viewportSize.y - margin - hint * 1.4, pointSize: hint, color: white)
            _ = hud.text("⌘S save · ⌘Z undo · ⌘R redo · ⌘⌫ revert to shipped · tab back to walking",
                         x: margin, y: viewportSize.y - margin, pointSize: hint, color: white)
        } else {
            // **The hints follow whichever device is actually plugged in.** Telling somebody holding
            // a controller to press WASD is a small lie the game is in a position to avoid, and the
            // engine already reports which it has.
            let moving = input.isGamepadConnected
                ? "left stick move · right stick look"
                : "WASD move · mouse look · click to capture · esc release"
            _ = hud.text(moving, x: margin, y: viewportSize.y - margin - hint * 1.4,
                         pointSize: hint, color: white)
            _ = hud.text("p pause · r restart · n next level · tab to edit the level",
                         x: margin, y: viewportSize.y - margin, pointSize: hint, color: white)
        }

        // A centre dot, so turning has something to turn about.
        let dot = 3 * scale
        hud.rect(x: viewportSize.x / 2 - dot, y: viewportSize.y / 2 - dot,
                 width: dot * 2, height: dot * 2, color: white)
        hud.draw(into: encoder, frameSlot: frameSlot)
    }
}
