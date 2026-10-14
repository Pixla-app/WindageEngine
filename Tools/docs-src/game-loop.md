---
title: GameLoop
description: The protocol a game implements — its six requirements, what the engine owns and what the game owns, frame slots, and the order of a frame.
---
`GameLoop` is what a game supplies to the engine's frame loop, and `FrameRenderer` is what calls it. The engine owns *when* things happen: pacing, frames in flight, the render passes. The game owns *what* happens: its pipelines, its uniforms, its draws.

## The protocol

```swift
public protocol GameLoop: AnyObject {
    func beginFrame()
    func step(deltaTime: Float)
    func viewportSizeChanged(width: Int, height: Int)
    func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float)
    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float)
    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float)
}
```

`encodePrePasses` and `encodeHUD` have default implementations that do nothing. The other four are yours. Set the game with `engine.game = game`; the property is weak, so keep your own strong reference.

| Requirement | Called | Do here |
| --- | --- | --- |
| `beginFrame()` | once per displayed frame, before any steps | poll input |
| `step(deltaTime:)` | once per fixed simulation step, zero or more times a frame | move everything |
| `viewportSizeChanged(width:height:)` | when the drawable's size, in pixels, changes, before that frame is encoded | rebuild anything that depends on aspect ratio |
| `encodePrePasses(into:frameSlot:interpolation:)` | before the main pass | shadow maps, depth prepasses, offscreen targets |
| `encode(into:frameSlot:interpolation:)` | in the scene pass | the scene's draws |
| `encodeHUD(into:frameSlot:interpolation:)` | after tone mapping, in the same pass, with the same `interpolation` | the interface |

## What the engine owns

`FrameRenderer` holds the Metal 4 objects every renderer needs: the `device` and a `residencySet`, and its own command queue and buffer, which it hands to your hooks rather than exposing. Everything the GPU touches must be in that set; add allocations as you create them, then call `commitResidency()`. `init(device:simulationStepsPerSecond:)` throws a `FrameRendererError` when the GPU is not Metal 4 or will not make what a frame needs.

It also owns the targets. The scene is drawn into an HDR texture of `FrameRenderer.sceneColorPixelFormat` (`.rgba16Float`) with a depth attachment of `FrameRenderer.depthPixelFormat`, cleared to `reversedZClearDepth` (0, infinitely far). The engine then tone maps that into the drawable, of `FrameRenderer.colorPixelFormat` (`.bgra8Unorm_srgb`), and calls `encodeHUD` in that same pass. So:

- **Scene pipelines** declare `sceneColorPixelFormat` and `depthPixelFormat`.
- **Interface pipelines** declare `colorPixelFormat` and no depth.
- **Depth state** comes from `makeDepthStencilState()`, which compares with `.greater` to match the engine's reversed-Z projection, `simd_float4x4(perspectiveFovY:aspectRatio:nearZ:depthRange:)`. A mismatch draws nothing at all rather than drawing badly, which is why the engine hands you the matching set.

What untouched pixels show is `clearColor`, in radiance, and the exposure and curve between scene and screen are `toneMapping`. Both can change at any time. See [tone mapping](tone-mapping.html).

## The order of a frame

For each frame the display link delivers:

1. The frame's time is credited to the clock.
2. `beginFrame()`.
3. `step(deltaTime:)` as many times as whole steps are due, each with the same delta.
4. The renderer waits until the GPU has finished with the oldest frame slot, then resets that slot's allocator.
5. `encodePrePasses(into:frameSlot:interpolation:)`, given the command buffer itself.
6. The scene pass: a barrier so it waits for what the pre-passes wrote, then `encode(into:frameSlot:interpolation:)`.
7. The tone map pass, then `encodeHUD(into:frameSlot:interpolation:)`.
8. Commit and present.

`viewportSizeChanged` is called just before step 4 on any frame whose drawable is a new size, including the first. A pause is the game's to implement and costs the loop nothing: keep stepping, just don't advance. The frame loop keeps running, the scene still draws and the window still resizes.

## Frame slots {#frame-slots}

The CPU may run up to `FrameRenderer.maxFramesInFlight` frames (3) ahead of the GPU. `frameSlot` says which of those slots this frame owns, and the engine guarantees the GPU has finished with it. Anything the CPU writes per frame (uniforms, joint palettes, instance data) needs one copy per slot, indexed by `frameSlot`, or the CPU will overwrite numbers the GPU is still reading.

The sample sizes its buffers that way:

```swift
private static let uniformStride = (MemoryLayout<Uniforms>.stride + 255) & ~255

guard let buffer = device.makeBuffer(
    length: SampleGame.uniformStride * SampleGame.uniformSlots * FrameRenderer.maxFramesInFlight,
    options: .storageModeShared) else { return nil }
uniformBuffer = buffer

private func uniformOffset(frameSlot: Int, drawable index: Int) -> Int {
    frameSlot * SampleGame.uniformStride * SampleGame.uniformSlots + index * SampleGame.uniformStride
}
```

`HUDRenderer.draw(into:frameSlot:)` and the engine's other per-frame types take the slot for the same reason.

## Pre-passes {#pre-passes}

`encodePrePasses` gets the command buffer rather than an encoder because the engine has no opinion about what a game renders into its own targets. It is where shadow maps go, and it is also the right place to **write this frame's uniforms**. The sample does that first:

```swift
func encodePrePasses(into commandBuffer: MTL4CommandBuffer, frameSlot: Int, interpolation: Float) {
    writeUniforms(frameSlot: frameSlot, interpolation: interpolation)
    // ... then the shadow pass, reading the same model matrices
}
```

Written in `encode` instead, the shadow pass would record last frame's positions and shadows would lag behind their casters. See [shadows](shadows.html).

## The interface after the scene {#hud}

`encodeHUD` is separate so that the order is structural. Scene color is radiance and is tone mapped; interface color is a specification and must not be. A brand color drawn inside the scene's shading arrives desaturated with nothing to say why. Draw interface in `encodeHUD` and it lands exactly. See [HUD](hud.html).

## Interpolation {#interpolation}

`interpolation` is how far the display sits between the last two simulation steps, in `0..<1`. Draw positions blended by it and motion is smooth at any refresh rate. The sample keeps the camera from before the latest step and blends:

```swift
func step(deltaTime: Float) {
    previousCamera = camera
    // ... move camera
}

private func displayCamera(_ interpolation: Float) -> Camera {
    Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
}
```

`encodeHUD` gets no interpolation; text and counters read the latest step. More in [Fixed timestep](fixed-timestep.html).

## Threading

`GameLoop` and `FrameRenderer` are main-actor types; every call arrives on the main thread. Types that must be free of that, such as `FixedTimestep`, are marked `nonisolated`.
