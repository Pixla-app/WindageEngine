---
title: Fixed timestep
description: FixedTimestep runs the simulation in identical steps however frames arrive, and interpolation keeps the drawing smooth between them.
---
The engine never hands `step(deltaTime:)` a variable delta. Wall-clock time accumulates in a `FixedTimestep` and is spent in identical steps, so a game behaves the same on a 60 Hz display, a 120 Hz one and a frame that stuttered. Drawing still happens as often as the display allows, between steps.

## Why

A thrown object or a falling player is integrated step by step, and each step's result feeds the next. Integrate with each frame's own delta and the same throw lands somewhere different at 60 Hz than at 120 Hz, and somewhere different again on a frame that happened to stall. A miss caused by the machine being busy is not a game. With a fixed step, the simulation is a function of the inputs and the step count, and nothing else.

## The type

```swift
public nonisolated struct FixedTimestep: Sendable {
    public let stepDuration: Double
    public let maxFrameTime: Double
    public private(set) var simulatedTime: Double
    public private(set) var totalSteps: Int
    public init(stepsPerSecond: Double, maxFrameTime: Double = 0.25)
    public mutating func advance(by frameTime: Double) -> Int
    public var interpolation: Float { get }
}
```

Seconds are `Double` here because this is a clock that adds frame times up for as long as the game runs; what a step hands the simulation, `step(deltaTime:)`, is one short span and is `Float`, like the rest of the engine's per-step arithmetic.

- `advance(by:)` adds one frame's elapsed time and returns how many whole steps are now due. Unspent time carries over to the next frame. A negative delta counts as zero; the clock never runs backwards.
- `maxFrameTime` caps what one frame may add. Without it, a long stall (a breakpoint, a window drag) becomes a burst of steps that takes longer than a frame, which makes the next delta larger still. Time is deliberately lost instead: the game runs slow for an instant rather than spiraling.
- `interpolation` is how far the display sits between the last completed step and the next, in `0..<1`. It is the value every `encode` hook is handed.
- `simulatedTime` and `totalSteps` count whole steps since the clock started, so they are exactly reproducible.

It is `nonisolated` pure arithmetic, so you can use it on its own and test with it:

```swift
var clock = FixedTimestep(stepsPerSecond: 120)
let steps = clock.advance(by: 1.0 / 60.0)   // 2
```

## In FrameRenderer

You rarely touch it directly. `FrameRenderer` owns one, and you choose its rate when you create the renderer:

```swift
public init(device: MTLDevice, simulationStepsPerSecond: Double = 120) throws
```

It throws a `FrameRendererError` when the GPU is not Metal 4 or will not make what a frame needs.

Each frame it credits the time since the previous frame's presentation, calls `beginFrame()`, calls `step(deltaTime:)` once per due step with `Float(timestep.stepDuration)`, then renders with `timestep.interpolation`. The display link asks for 30 to 120 frames a second, preferring 120, unless you pass `makeDisplayLink(for:frameRateRange:)` another range. `engine.timestep` is readable if you want the step length or the simulated time.

The sample picks its rate from the environment, which is how it shows the choice does not change the game:

```swift
static let stepsPerSecond = ProcessInfo.processInfo.environment["WINDAGE_SAMPLE_RATE"]
    .flatMap(Double.init) ?? 120

let engine = try FrameRenderer(device: device, simulationStepsPerSecond: SampleGame.stepsPerSecond)
```

## Drawing between steps {#interpolation}

Without interpolation, a 120 Hz display showing a 60 Hz simulation shows every position twice, which reads as judder. So keep the state from before the latest step, and draw a blend:

```swift
func step(deltaTime: Float) {
    previousCamera = camera
    // ... advance camera by exactly deltaTime
}

func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
    let view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
    // ... draw from view
}
```

`Camera.interpolated(from:to:alpha:)` blends position and pitch, and takes the shortest way round for yaw. The sample blends its head bob the same way. Interpolate what is drawn, never what is simulated: the camera's aim stays the stepped value.

## Input belongs to frames, not steps

A frame may run zero, one or several steps. Mouse movement is a displacement that already happened, so `InputState.consumePendingLook()` is read **once per frame**, in `beginFrame`. Applied in every step of a frame that ran three, it would turn three times as far. Held keys and stick rates, by contrast, are read per step and scaled by `deltaTime`. See [input](input.html).

## Behaving the same at any step rate

A fixed step makes a game independent of the frame rate. The step rate itself is still a game's choice, and the engine goes further so that choice does not change behavior either. Its character controller integrates flight with the exact answer for constant gravity, `y + v·dt − ½g·dt²`, rather than a step at a time. Before that change, a jump's height depended on the rate:

| Steps a second | 30 | 60 | 120 | 240 |
| --- | --- | --- | --- | --- |
| apex before | 0.890 m | 0.940 m | 0.966 m | 0.979 m |
| apex now | 0.992 m | 0.992 m | 0.992 m | 0.992 m |

A game at 60 used to jump 2.6 cm lower than one at 120 and miss a ledge the other cleared. Landing speed, slide distance and the eye's settling were fixed the same way: a landing from 1 m hits at 6.3246 m/s at every rate.

The proof is one course: walk, jump, three steps climbed, sprint, slide, off a ledge, land. The sample walks it in the ruins at 30, 60, 120 and 240 steps a second, and `Tools/walks.py` requires the same report at all four, to the centimeter. See [walks](walks.html).

> The remaining floor is `Float` precision, not physics: an eight-second straight walk ends 0.1 mm from 48 m at 30 steps a second and 0.6 mm at 240.

## Choosing a rate

120 is the default and what the sample uses. A lower rate costs less CPU; a higher one samples fast events more finely. Pick once and keep it. If your own simulation code integrates anything nonlinear, test it at more than one rate, as the engine does, because a fixed step only removes the frame rate from the result, not the step size.

When the window is hidden there are no frames, and so no steps unless you ask for them. See [Running hidden](running-hidden.html).
