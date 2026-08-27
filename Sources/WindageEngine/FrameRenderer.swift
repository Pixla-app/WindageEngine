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

    public static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
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
    public var clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

    public weak var game: GameLoop?

    private let commandAllocators: [MTL4CommandAllocator]
    private let endFrameEvent: MTLSharedEvent
    private var frameIndex: Int
    private var depthTexture: MTLTexture?
    private var lastPresentationTime: CFTimeInterval?

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

        self.frameIndex = FrameRenderer.maxFramesInFlight
        event.signaledValue = UInt64(FrameRenderer.maxFramesInFlight - 1)

        super.init()
        queue.addResidencySet(set)
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
        let frameTime = lastPresentationTime.map { presentationTime - $0 } ?? 0
        lastPresentationTime = presentationTime

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

        game?.viewportChanged(width: width, height: height)
    }

    private func render(to drawable: CAMetalDrawable, interpolation alpha: Float) {
        updateRenderTargets(width: drawable.texture.width, height: drawable.texture.height)
        guard let depthTexture, let game else { return }

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

        let passDescriptor = MTL4RenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
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
        encoder.label = "Primary Render Encoder"
        game.encode(into: encoder, frameSlot: frameSlot, interpolation: alpha)

        // The interface goes last, in the same pass, on top of a scene that has already been tone
        // mapped. See `GameLoop.encodeHUD`.
        game.encodeHUD(into: encoder, frameSlot: frameSlot)

        encoder.endEncoding()

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
