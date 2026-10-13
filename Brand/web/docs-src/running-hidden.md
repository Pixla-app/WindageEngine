---
title: Running hidden
description: Keep the simulation running while the window is hidden, draw frames into a texture with no window, and run a game as a headless check.
---
By default a hidden game is frozen: macOS stops delivering display-link frames to a window nobody can see, and the simulation steps only when a frame arrives. This page covers the switch that keeps time without frames, and the call that draws a frame with no drawable at all.

## Hidden is frozen, by default

When the window is hidden, minimized, covered or on another Space, its display link does not call at all. When the window returns, the first frame reports the whole absence and `FixedTimestep.maxFrameTime` throws away all but a quarter of a second of it. Measured: hidden for 10.2 s, one frame back reporting 10.23 s, 30 steps run for it.

That is a fair pause for a single-player game. It is wrong for anything that has to keep time: a match with other players, a timed run, a scripted check that has to finish.

## `runsWhileHidden` {#runs-while-hidden}

```swift
engine.runsWhileHidden = true
```

`FrameRenderer.runsWhileHidden` is off by default. When on, a timer steps the simulation whenever the display link has been quiet for more than 0.1 s (three frames at its slowest rate):

- The same fixed steps at the same rate, through `step(deltaTime:)`.
- **No frame drawn, and `beginFrame()` not called**, because no frame begins. Anything a game polls in `beginFrame` (the controller, for instance) is not polled while hidden. If a hidden game needs it, poll in `step` too, as the sample does when it runs as a check.
- **One clock, credited once.** A display-link frame is stamped with when it will be *shown*, some 50 ms ahead of the host clock, which is all a timer knows. The timer moves the frames' clock on by exactly what it credits, so no time is counted twice when the window comes back.
- **Time starts at the first tick when no frame ever comes.** A window opened hidden, and perhaps never shown, still keeps time.

The arithmetic is an internal type, `FrameClock`, tested apart from the timer and the display link.

The sample turns it on only for a scripted walk, leaving ordinary play paused when hidden:

```swift
engine.runsWhileHidden = ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_WALK"] != nil
```

### App Nap {#app-nap}

macOS coalesces timers in an app it thinks is idle, and a hidden game with no sound playing looks idle. So while `runsWhileHidden` is on, the renderer holds a process activity with `.userInitiatedAllowingIdleSystemSleep` and `.latencyCritical`. Both are needed. Measured on a silent bundled app, hidden two minutes:

| Activity | Longest wait between steps |
| --- | --- |
| none | 120 / 78 ms, ragged after a minute |
| user-initiated only | 165 / 54 ms |
| user-initiated + latency-critical | 33 / 32 ms |

The last row is as steady as an app playing sound. Idle sleep is still allowed, and the timer precision's power is paid only while a game asks for it.

> Steps per second cannot show App Nap. The hidden clock credits whatever time went by, so a timer slowed to once a second still runs 120 steps, in one burst. What shows it is the longest wall-clock wait between steps, which the sample prints with `WINDAGE_SAMPLE_FPS=1`.

## Drawing into a texture {#render-into}

```swift
public func render(into texture: MTLTexture, interpolation: Float = 0)
```

`FrameRenderer.render(into:)` draws one frame into a texture of your own instead of a window's drawable, with the same passes in the same order: pre-passes, the scene into its HDR target, the tone map and the interface. What comes out is what a player would have seen. It **waits for the GPU**, so the texture can be read the moment it returns. Use it for a frame compared against a recorded one, a thumbnail, or a saved photograph.

The texture needs `FrameRenderer.colorPixelFormat`, `.renderTarget` usage and, to read it back, shared or managed storage. Like everything else the GPU touches, it goes in the residency set. From the sample's `writeFrame(to:)`:

```swift
let width = 640, height = 400
let descriptor = MTLTextureDescriptor.texture2DDescriptor(
    pixelFormat: FrameRenderer.colorPixelFormat, width: width, height: height, mipmapped: false)
descriptor.usage = [.renderTarget, .shaderRead]
descriptor.storageMode = .shared
guard let texture = engine.device.makeTexture(descriptor: descriptor) else { return false }
engine.residencySet.addAllocation(texture)
engine.commitResidency()
viewportSizeChanged(width: width, height: height)
engine.render(into: texture)

var bgra = [UInt8](repeating: 0, count: width * height * 4)
bgra.withUnsafeMutableBytes {
    texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                     from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
}
```

The bytes are BGRA. Swap red and blue to write an RGBA image. `render(into:)` does nothing if `engine.game` is not set. It informs the game of a new size through `viewportSizeChanged` the same way a displayed frame does; the sample also calls it directly so the aspect ratio is right before anything else.

The sample draws its frame **before any step**, so the picture is identical on every run. Pass `interpolation` if you want a moment between steps.

## Headless {#headless}

`FrameRenderer(device:)` needs a Metal 4 device, not a window. Two patterns from the sample cover most headless needs.

**A frame and quit.** `WINDAGE_SAMPLE_FRAME=<path>` sets everything up, draws one frame with `render(into:)` before the window is ever shown, writes a PNG and exits. `Tools/frames.py` does this for each recorded viewpoint and compares pixel by pixel. See [frames](frames.html).

**A check that runs while someone works.** `WINDAGE_SAMPLE_CHECK=1` plays a scripted walk with the window never shown:

```swift
application.setActivationPolicy(SampleGame.isCheck ? .accessory : .regular)
// ...
if SampleGame.isCheck {
    // Not shown.
} else {
    window.makeKeyAndOrderFront(nil)
    application.activate(ignoringOtherApps: true)
}
```

- **Accessory, not regular.** A regular app is made frontmost when it finishes launching whether or not it asks, and would take the next keystroke from whoever is typing.
- **`runsWhileHidden` on**, so the walk keeps time with no frames from its first tick.
- **No sound, and saves of its own**, cleared at launch, so a check never writes a player's best times or reads their rebinding.

A walk's result depends on its step count, not the wall clock, so checks can run side by side. See [walks](walks.html).
