---
title: Camera
description: The first-person Camera type, its view matrix, and the reversed-Z projection with an infinite far plane that every Windage Engine frame is drawn through.
---
`Camera` is an eye in the world: a position in meters, a yaw and a pitch, and the view matrix that follows from them. Pair it with `simd_float4x4(perspectiveFovY:aspectRatio:nearZ:depthRange:)` for the projection, and you have everything a frame needs to know about where it is looking from.

## The Camera type

```swift
public nonisolated struct Camera: Sendable, Equatable {
    public var position: SIMD3<Float>   // meters, Y is up
    public var yaw: Float               // radians, 0 looks down -Z, positive turns left
    public var pitch: Float             // radians, positive looks up
    public var tuning: Tuning           // speeds and sensitivities
    public init(position: SIMD3<Float> = .zero, yaw: Float = 0, pitch: Float = 0, tuning: Tuning = Tuning())
}
```

Orientation is yaw and pitch with no roll. Pitch is clamped to `Camera.pitchLimit`, 89 degrees: at exactly 90 the look direction is parallel to world up, the right vector is undefined, and the image snaps. Yaw is kept wrapped to `(-π, π]` by `Float.wrappedAngle(_:)`, because a session spinning steadily for an hour would otherwise reach angles a 32-bit float cannot resolve finely. **Both hold however the angles are set** — `camera.pitch += recoil` is clamped, `camera.yaw += turned` is wrapped.

The basis comes from those two angles:

| Property | What it is |
| --- | --- |
| `forward` | The look direction. |
| `right` | Horizontal only, so strafing never drifts up or down while looking at the sky. |
| `up` | `right × forward`. |
| `viewMatrix` | World space to view space. Right-handed: the camera looks down **-Z**, so anything in front of it has a negative view-space Z. |

## An eye, not a body

`advance(_:deltaTime:)` flies along the look direction, through anything. That is right for an editor, a photo mode, or a game that genuinely flies. A game with feet moves a `CharacterController` instead and puts the camera at its `eye` — see [character-controller](character-controller.html). Walking is along the ground plane, not the look direction, which is why the two are separate types.

`advance` takes a `MovementInput` — axes rather than key names, so a stick or a replay can drive it as easily as a keyboard. Its direction is clamped to length 1, not normalized: two keys at once are not faster than one, and a stick pushed a third of the way goes a third as fast. Speeds are the camera's `tuning.walkSpeed` (6 m/s) and `tuning.sprintSpeed` (18 m/s).

```swift
camera.advance(MovementInput(forward: 1, strafe: 0, vertical: 0, isSprinting: false),
               deltaTime: deltaTime)
```

## Looking: mouse and stick are different quantities

There are two look methods, and mixing them up ruins the feel of one or the other.

- `look(mouseDelta:)` is **not** scaled by time. A mouse delta is a displacement the player already made; scaling it by frame duration would make the same hand movement turn further on a slow frame.
- `turn(rate:deltaTime:)` **is** scaled by time. A stick reports a held position, which is a rate: hold it twice as long and you turn twice as far.

Sensitivities are `tuning.lookSensitivity` (0.0022 radians per unit of mouse movement) and `tuning.stickLookSpeed` (3.2 radians per second at full deflection) — your game's to change, per camera. A player's own sensitivity goes on top, through [input](input.html).

## Reversed-Z, with an infinite far plane {#reversed-z}

```swift
public extension simd_float4x4 {
    init(perspectiveFovY fovY: Float, aspectRatio: Float, nearZ: Float,
         depthRange: ClosedRange<Float> = 0...1)
}
```

`fovY` is the vertical field of view in radians; `Float.radians(fromDegrees:)` converts.

This projection maps the near plane to depth **1** and infinite distance to depth **0** — the opposite of the conventional near-0, far-1. Depth is stored as floating point, and floats hold far more precision near zero, so the conventional mapping spends almost all of it in the first few meters and leaves the far field to z-fight. Reversed, the precision is where the distance is.

The far plane is gone, not merely large: depth approaches 0 asymptotically, so there is no view distance to tune and nothing to clip against at range. One consequence shows up in [culling](culling.html): a Windage Engine frustum has five planes, not six.

### Three things must agree, so the engine owns them

Reversed-Z needs the projection, the depth compare function and the depth clear value to agree, and a mismatch renders **nothing at all** rather than rendering badly. So:

| Piece | Where it comes from |
| --- | --- |
| The projection | `simd_float4x4(perspectiveFovY:aspectRatio:nearZ:depthRange:)` |
| Compare `.greater` (nearer is now larger) | `FrameRenderer.makeDepthStencilState()` |
| Clear to 0 | `FrameRenderer.reversedZClearDepth` |

Use all three and they cannot disagree.

> Reversed-Z means **larger is nearer**. Any depth arithmetic you write yourself — a depth range, a bias, a comparison in a shader — has to read it that way round.

### A slice of the depth buffer

`depthRange` confines the projection to part of the depth buffer, for drawing something held in the player's hands with its own field of view and in front of the world. `0...1`, the default, is the whole buffer; `0.9...1` is the front tenth. Because depth is reversed, `depthRange.upperBound` is the near end.

## How the sample drives it

The sample keeps two cameras — the last simulation step's and this one's — and blends between them for display, so motion stays smooth when the display and the simulation run at different rates (see [fixed-timestep](fixed-timestep.html)). `Camera.interpolated(from:to:alpha:)` takes yaw the short way across the ±π seam, so turning from 179° to -179° is 2° of movement, not 358°.

```swift
// Each simulation step
previousCamera = camera
camera.turn(rate: input.lookRate * settings.stickLookScale, deltaTime: deltaTime)

// Each frame
let view = Camera.interpolated(from: previousCamera, to: camera, alpha: interpolation)
let projection = simd_float4x4(
    perspectiveFovY: Float.radians(fromDegrees: 70), aspectRatio: aspectRatio, nearZ: 0.1)
let viewProjection = simd_mul(projection, view.viewMatrix)
```

Mouse look goes through `camera.look(mouseDelta:)` as events arrive. The sample's view also adds a head bob and a slide's dip to the *displayed* camera only, never to `camera` itself — the view moves, the aim does not.

## Gotchas

- `MovementInput` has an explicit public initializer, so you can construct one from outside the module.
- `Float.shortestAngle(from:to:)` is the signed shortest turn between two yaws — what `Camera.interpolated(from:to:alpha:)` blends by, so a frame across the ±π seam does not spin the long way round.
- The camera knows nothing about collision. Put it at a body's eye if it should not walk through walls.
