//
//  FrameRenderer.swift
//  WindageEngine
//

import Metal
import MetalKit
import QuartzCore
import simd

/// What a game supplies to the engine's frame loop.
///
/// The engine owns *when* things happen — pacing, frames in flight, the render pass. The game owns
/// *what* happens: its pipelines, its uniforms, its draws. The split is deliberately at that line
/// because everything above it was identical in every renderer this was extracted from, and
/// everything below it was not.
public protocol GameLoop: AnyObject {

    /// Once per displayed frame, before any simulation steps. Poll input here.
    func beginFrame()

    /// One fixed simulation step. Never called with a variable delta — see ``FixedTimestep``.
    func step(deltaTime: Float)

    /// The drawable changed size. Rebuild anything that depends on aspect ratio.
    func viewportChanged(width: Int, height: Int)

    /// Encode any passes that must run *before* the main one — shadow maps, depth prepasses,
    /// offscreen effects.
    ///
    /// Deliberately general rather than a `encodeShadowPass` hook. The engine has no opinion about
    /// what a game renders into its own targets, and naming this after the first feature that
    /// needed it would bake one title's structure into every other title's engine.
    ///
    /// Default implementation does nothing.
    func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float)

    /// Encode this frame's draws.
    ///
    /// - Parameters:
    ///   - frameSlot: which of the frames-in-flight slots this frame owns. Index per-frame resources
    ///     with it; the engine guarantees the GPU has finished with that slot.
    ///   - interpolation: how far between the last two simulation steps to draw, in `0..<1`.
    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float)

    /// Encode the interface, **after** the scene.
    ///
    /// Separate from ``encode(into:frameSlot:interpolation:)`` so the ordering is structural rather
    /// than a convention each title has to remember. Scene colour is radiance and gets tone mapped;
    /// interface colour is a specification and must not be. Draw HUD inside the scene's shading and
    /// a brand colour arrives on screen desaturated, with nothing to say why.
    ///
    /// Default implementation does nothing.
    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int)
}

public extension GameLoop {
    func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float) {}
    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {}
}

/// Drives frames, owns the Metal 4 objects every renderer needs, and enforces the engine's
/// reversed-Z depth convention.
///
/// **Why the depth convention lives here rather than in each game.** Reversed-Z needs the
/// projection, the compare function and the clear value to agree, and a mismatch renders *nothing at
/// all* rather than rendering badly. Three constants that must match, spread across three files, in
/// every title, is a trap that will be sprung. Here, a game that uses `FrameRenderer` and
/// ``matrix_perspective_right_hand_reverse_z`` gets a consistent set by construction, and
/// ``makeDepthStencilState()`` hands back the matching depth state.
public final class FrameRenderer: NSObject, CAMetalDisplayLinkDelegate {

    /// Frames the CPU may run ahead of the GPU.
    public static let maxFramesInFlight = 3

    /// What the **drawable** is: what a view's layer must be set to, and what an interface pipeline
    /// draws into. `_srgb`, so the GPU encodes linear values for the display on write.
    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// What the **scene** is drawn into, and therefore what a game's scene pipelines must declare.
    ///
    /// **Sixteen-bit float, because shading does not stop at 1.** A surface lit by the sun with a
    /// specular highlight on it is genuinely brighter than white paper; written straight to an 8-bit target
    /// every value above 1 clips to the same white, and the brightest part of the image becomes the
    /// part carrying no information. The scene is drawn here and ``ToneMapping`` fits it into what a
    /// display can show.
    ///
    /// Half float rather than full: it holds far more range than a frame needs and costs half the
    /// bandwidth of `rgba32Float`, which on a full-screen target is the whole cost of this pass.
    public static let sceneColorPixelFormat: MTLPixelFormat = .rgba16Float

    public static let depthPixelFormat: MTLPixelFormat = .depth32Float_stencil8

    /// Reversed-Z: 0 is infinitely far, so that is what an untouched pixel starts at.
    public static let reversedZClearDepth: Double = 0.0

    public let device: MTLDevice
    public let commandQueue: MTL4CommandQueue
    public let commandBuffer: MTL4CommandBuffer

    /// Everything the GPU touches must be in here. Add allocations as they are created, then
    /// ``commitResidency()``.
    public let residencySet: MTLResidencySet

    public private(set) var timestep: FixedTimestep

    /// What an untouched pixel is, **in radiance** — the scene target is HDR, so this is a linear
    /// value that will be tone mapped like everything else rather than a colour that reaches the
    /// screen unchanged.
    public var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

    /// The exposure and curve applied between the scene and the display. Change it whenever.
    public var toneMapping = ToneMapping.default

    public weak var game: GameLoop?

    private let commandAllocators: [MTL4CommandAllocator]
    private let endFrameEvent: MTLSharedEvent
    private var frameIndex: Int
    private var depthTexture: MTLTexture?
    private var sceneTexture: MTLTexture?
    private var toneMapPipeline: MTLRenderPipelineState?
    private let toneMapArgumentTable: MTL4ArgumentTable
    private let toneMapUniformBuffer: MTLBuffer
    /// Per frame in flight, because the GPU may still be reading last frame's exposure.
    private static let toneMapStride = (MemoryLayout<ToneMapping.Packed>.stride + 255) & ~255

    /// Whether the simulation keeps running while nothing is being drawn — the window hidden,
    /// minimised, covered or on another Space. **Off by default: hidden is frozen.**
    ///
    /// **The display link is the clock, and a hidden window has none.** macOS stops delivering its
    /// frames, so the simulation stops with them; when the window returns, the first frame reports the
    /// whole absence and ``FixedTimestep/maxFrameTime`` throws all but a quarter of a second of it
    /// away. Measured: hidden for 10.2 s, one frame back of 10.23 s, 30 steps run for it. That is a fair
    /// pause for a single-player game, and wrong for anything that has to keep time — a match with
    /// other players in it, a timed run, a check scripted to finish.
    ///
    /// On, the simulation is stepped from a timer while the display link is quiet: the same fixed
    /// steps, the same clock — credited once, whichever of the two credits it — with no frame drawn
    /// and ``GameLoop/beginFrame()`` not called, because no frame begins.
    public var runsWhileHidden = false {
        didSet {
            guard runsWhileHidden != oldValue else { return }
            hiddenTimer?.invalidate()
            hiddenTimer = nil
            guard runsWhileHidden else { return }
            // Weakly: a timer keeps its target alive, and a renderer is not kept alive by a switch.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepWhileHidden() }
            }
            RunLoop.main.add(timer, forMode: .common)
            hiddenTimer = timer
        }
    }

    private var hiddenTimer: Timer?
    private var clock = FrameClock()

    isolated deinit { hiddenTimer?.invalidate() }

    private func stepWhileHidden() {
        guard let elapsed = clock.tick(now: CACurrentMediaTime()) else { return }
        let steps = timestep.advance(by: elapsed)
        for _ in 0..<steps {
            game?.step(deltaTime: Float(timestep.step))
        }
    }

    public init?(device: MTLDevice, simulationStepsPerSecond: Double = 120) {
        guard device.supportsFamily(.metal4) else { return nil }
        guard let queue = device.makeMTL4CommandQueue(),
              let buffer = device.makeCommandBuffer(),
              let event = device.makeSharedEvent() else { return nil }

        self.device = device
        self.commandQueue = queue
        self.commandBuffer = buffer
        self.endFrameEvent = event
        self.timestep = FixedTimestep(stepsPerSecond: simulationStepsPerSecond)
        self.commandAllocators = (0..<FrameRenderer.maxFramesInFlight).map { _ in device.makeCommandAllocator()! }

        let descriptor = MTLResidencySetDescriptor()
        descriptor.initialCapacity = 64
        guard let set = try? device.makeResidencySet(descriptor: descriptor) else { return nil }
        self.residencySet = set

        let tableDescriptor = MTL4ArgumentTableDescriptor()
        tableDescriptor.maxBufferBindCount = 1      // 0: the exposure and curve
        tableDescriptor.maxTextureBindCount = 1     // 0: the scene, in radiance
        guard let table = try? device.makeArgumentTable(descriptor: tableDescriptor),
              let uniforms = device.makeBuffer(
                length: FrameRenderer.toneMapStride * FrameRenderer.maxFramesInFlight,
                options: .storageModeShared) else { return nil }
        uniforms.label = "Tone Mapping"
        self.toneMapArgumentTable = table
        self.toneMapUniformBuffer = uniforms

        self.frameIndex = FrameRenderer.maxFramesInFlight
        event.signaledValue = UInt64(FrameRenderer.maxFramesInFlight - 1)

        super.init()
        queue.addResidencySet(set)
        residencySet.addAllocations([uniforms])
        residencySet.commit()

        // **Built here rather than lazily, so a failure is reported once at start-up** instead of
        // per frame from inside the render loop.
        do {
            let library = try ShaderLibrary.make(device: device, bundle: .module,
                                                 sourceNamed: "ToneMapShaders")
            let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

            let vertexFunction = MTL4LibraryFunctionDescriptor()
            vertexFunction.library = library
            vertexFunction.name = "toneMapVertex"
            let fragmentFunction = MTL4LibraryFunctionDescriptor()
            fragmentFunction.library = library
            fragmentFunction.name = "toneMapFragment"

            let descriptor = MTL4RenderPipelineDescriptor()
            descriptor.label = "Tone Map"
            descriptor.vertexFunctionDescriptor = vertexFunction
            descriptor.fragmentFunctionDescriptor = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = FrameRenderer.colorPixelFormat
            toneMapPipeline = try compiler.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            // **Not fatal, and the fallback is a black screen rather than a crash.** A machine that
            // cannot build this pipeline is one where nothing else will work either, and saying so
            // is more use than a trap.
            NSLog("\(Engine.name): tone mapping unavailable — \(error)")
        }
    }

    /// Publishes residency changes to the GPU. Call after adding allocations.
    public func commitResidency() {
        residencySet.commit()
    }

    /// The depth-stencil state matching the engine's reversed-Z convention: nearer is *greater*.
    public func makeDepthStencilState() -> MTLDepthStencilState? {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .greater
        descriptor.isDepthWriteEnabled = true
        return device.makeDepthStencilState(descriptor: descriptor)
    }

    /// Builds a display link that drives this renderer. The caller owns it and must invalidate it.
    public func makeDisplayLink(for layer: CAMetalLayer) -> CAMetalDisplayLink {
        let link = CAMetalDisplayLink(metalLayer: layer)
        link.delegate = self
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        return link
    }

    // MARK: - Frame

    public func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let drawable = update.drawable
        let presentationTime = update.targetPresentationTimestamp

        // The display link reports when the frame will be *shown*, which is the clock animation and
        // ballistics belong on. The first frame has no predecessor and contributes no time.
        let frameTime = clock.frame(presented: presentationTime, now: CACurrentMediaTime())

        game?.beginFrame()

        let steps = timestep.advance(by: frameTime)
        for _ in 0..<steps {
            game?.step(deltaTime: Float(timestep.step))
        }

        render(to: drawable, interpolation: timestep.interpolationAlpha)
    }

    private func updateRenderTargets(width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        if let depthTexture, depthTexture.width == width, depthTexture.height == height { return }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FrameRenderer.depthPixelFormat, width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        // Nothing reads depth after the pass ends, so it never needs to exist in main memory. On
        // Apple silicon a memoryless attachment lives only in tile memory: no allocation, no
        // write-out, and nothing for the residency set to track.
        descriptor.storageMode = .memoryless
        depthTexture = device.makeTexture(descriptor: descriptor)
        depthTexture?.label = "Depth"

        // **The scene target cannot be memoryless**, unlike depth: the tone map pass reads it after
        // the scene pass has ended, so it has to survive into main memory.
        let sceneDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: FrameRenderer.sceneColorPixelFormat, width: width, height: height,
            mipmapped: false)
        sceneDescriptor.usage = [.renderTarget, .shaderRead]
        sceneDescriptor.storageMode = .private
        let previous = sceneTexture
        sceneTexture = device.makeTexture(descriptor: sceneDescriptor)
        sceneTexture?.label = "Scene Colour (HDR)"

        // **Removed as well as added.** A window dragged between displays resizes repeatedly, and a
        // residency set that only ever grows holds every intermediate size resident for the life of
        // the process.
        if let previous { residencySet.removeAllocations([previous]) }
        if let sceneTexture { residencySet.addAllocations([sceneTexture]) }
        residencySet.commit()

        game?.viewportChanged(width: width, height: height)
    }

    /// Pass two: the scene fitted to the display, then the interface on top of it.
    ///
    /// **The interface is drawn here, after the curve, and that is the whole reason the two are one
    /// pass.** Scene colour is radiance and gets tone mapped; interface colour is a *specification* —
    /// a brand red is that red, not "that red as it would look lit by this sun". Tone map the HUD as
    /// well and every interface colour arrives desaturated with nothing to say why.
    private func encodeToneMapAndInterface(to drawable: CAMetalDrawable,
                                           scene: MTLTexture,
                                           frameSlot: Int,
                                           game: GameLoop) {
        let descriptor = MTL4RenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        // Every pixel is written by the full-screen triangle, so there is nothing worth loading.
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        // **No depth attachment.** Nothing here is occluded by anything, and a depth buffer would
        // only be a state for the tone map and the HUD to disagree about.

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Tone Map and Interface"

        if let toneMapPipeline {
            encoder.setRenderPipelineState(toneMapPipeline)
            encoder.setArgumentTable(toneMapArgumentTable, stages: [.vertex, .fragment])
            var uniforms = toneMapping.packed
            let offset = frameSlot * FrameRenderer.toneMapStride
            toneMapUniformBuffer.contents().advanced(by: offset)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<ToneMapping.Packed>.size)
            toneMapArgumentTable.setAddress(toneMapUniformBuffer.gpuAddress + UInt64(offset), index: 0)
            toneMapArgumentTable.setTexture(scene.gpuResourceID, index: 0)
            encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
        }

        game.encodeHUD(into: encoder, frameSlot: frameSlot)
        encoder.endEncoding()
    }

    private func render(to drawable: CAMetalDrawable, interpolation alpha: Float) {
        updateRenderTargets(width: drawable.texture.width, height: drawable.texture.height)
        guard let depthTexture, let sceneTexture, let game else { return }

        // Block until the frame that last used this slot has actually finished on the GPU. Apple's
        // template waits once with a 10 ms timeout and ignores the result, so on expiry it falls
        // through and resets an allocator whose commands may still be executing — undefined
        // behaviour rather than a dropped frame.
        let previousValueToWaitFor = frameIndex - FrameRenderer.maxFramesInFlight
        while !endFrameEvent.wait(untilSignaledValue: UInt64(previousValueToWaitFor), timeoutMS: 1000) {
            NSLog("WindageEngine: GPU has not completed frame \(previousValueToWaitFor) after 1 s; still waiting.")
        }

        let frameSlot = frameIndex % FrameRenderer.maxFramesInFlight
        let allocator = commandAllocators[frameSlot]
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)

        game.encodePrePasses(into: commandBuffer, frameSlot: frameSlot, interpolation: alpha)

        // **Pass one: the scene, into an HDR target.** Not into the drawable — see
        // `sceneColorPixelFormat`.
        let passDescriptor = MTL4RenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = sceneTexture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = clearColor
        passDescriptor.colorAttachments[0].storeAction = .store

        // Built fresh rather than mutated in place: `depthAttachment` is a `copy` property, so
        // whether edits to the returned object stick is not something to rely on.
        let depthAttachment = MTLRenderPassDepthAttachmentDescriptor()
        depthAttachment.texture = depthTexture
        depthAttachment.loadAction = .clear
        depthAttachment.clearDepth = FrameRenderer.reversedZClearDepth
        depthAttachment.storeAction = .dontCare
        passDescriptor.depthAttachment = depthAttachment

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else {
            fatalError("Failed to create render command encoder")
        }
        encoder.label = "Scene"
        game.encode(into: encoder, frameSlot: frameSlot, interpolation: alpha)
        encoder.endEncoding()

        encodeToneMapAndInterface(to: drawable, scene: sceneTexture, frameSlot: frameSlot, game: game)

        if let layerResidencySet = (drawable.layer as CAMetalLayer?)?.residencySet {
            commandBuffer.useResidencySet(layerResidencySet)
        }
        commandBuffer.endCommandBuffer()

        commandQueue.waitForDrawable(drawable)
        commandQueue.commit([commandBuffer])
        commandQueue.signalDrawable(drawable)
        commandQueue.signalEvent(endFrameEvent, value: UInt64(frameIndex))
        frameIndex += 1
        drawable.present()
    }
}
