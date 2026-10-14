---
title: Tone mapping
description: The HDR scene target, ToneMapping's exposure in stops and its three curves, and why the interface is drawn after the tone map.
---
Shading doesn't stop at 1. Windage Engine draws the scene into a half-float HDR target, then a second pass applies an exposure and a curve to fit it onto the display. Your HUD is drawn in that second pass, after the curve, so its colors reach the screen exactly as specified.

## Why a curve is not optional {#why}

A sunlit surface with a specular highlight is genuinely brighter than white paper. Once ambient, direct and specular light are added together, values routinely go past 1.0. The sample's lit faces reach about 1.13 before anything shiny is involved. Written straight to an 8-bit display buffer, all of those values clip to the same white. The brightest part of the image ends up carrying no detail, and it reads as bad art rather than a missing step.

## The two passes {#passes}

`FrameRenderer` runs the frame as two passes:

1. **The scene** draws into `FrameRenderer.sceneColorPixelFormat`, which is `rgba16Float`. Half float holds far more range than a frame needs, at half the bandwidth of full float. It can't be memoryless, because the second pass reads it after the scene pass ends.
2. **The tone map** draws one full-screen triangle, generated from `vertex_id` with no vertex buffer. It reads the scene, applies exposure and the curve, and writes the drawable in `FrameRenderer.colorPixelFormat` (`bgra8Unorm_srgb`). `GameLoop.encodeHUD(into:frameSlot:interpolation:)` runs in this same pass.

`FrameRenderer.clearColor` is in radiance, because it is cleared into the HDR target and tone-mapped along with everything else.

> **A pipeline with the wrong pixel format draws static, not an error.** Metal 4 builds pipelines separately from passes. A scene pipeline that still declares `colorPixelFormat` is accepted, and it writes 8-bit pixels into the 16-bit float target: magenta and blue noise, with nothing logged. Pipelines drawn in `encode` use `sceneColorPixelFormat`, pipelines drawn in `encodeHUD` use `colorPixelFormat`, and anything drawn into your own target uses that target's format.

## ToneMapping {#tone-mapping}

```swift
public init(curve: Curve = .aces, exposureStops: Float = 0, whitePoint: Float = 4)
```

Set it on the renderer and change it whenever you like:

```swift
engine.toneMapping = ToneMapping(curve: .aces, exposureStops: SampleGame.baseExposure)
```

**Exposure is in stops**: +1 doubles the light, and −1 halves it. Stops match how people think about brightness, and the useful range is small and symmetric, roughly −4 to +4. As a plain multiplier, that same range runs from 0.06 to 16. `exposure` gives you the linear multiplier when you need it.

`ToneMapping` is `Codable`, as `{"curve": "aces", "exposureStops": 0, "whitePoint": 4}` with every key optional, so a game can keep its look in a file. The curve is written by name.

### Curves {#curves}

| `ToneMapping.Curve` | |
| --- | --- |
| `clamp` | Not really a curve. It's what a renderer does with no tone mapping, kept so you can see the difference. |
| `reinhard` | Extended Reinhard with a `whitePoint`. The gentlest curve and the most washed out. It scales all three channels by the same factor, so hue is exactly preserved. |
| `aces` | **The default.** Narkowicz's fit of the ACES filmic curve. It rolls highlights off gradually and lets very bright colors desaturate toward white, which reads as bright rather than clipped. |

`ToneMapping.default` is ACES at 0 stops. `ToneMapping.off` is `clamp` at 0 stops. If your game tone-maps in its own shader, set `toneMapping = .off` so the picture doesn't get a second curve.

The sample cycles through all three curves on a key, using `ToneMapping.Curve.allCases`. It also adds the player's brightness setting to its own exposure:

```swift
engine.toneMapping.exposureStops = SampleGame.baseExposure + settings.brightness
```

### Two things worth knowing {#gotchas}

- **ACES lifts the midtones.** Middle gray 0.18 maps to 0.267. A scene whose values were picked before there was a curve comes out *brighter* once ACES is on. The sample sits at −0.5 stops for this reason. A game authored against the curve from the start would sit at zero.
- **The ACES fit isn't asymptotic.** It passes 1 at an input of about 6.6, so the clamp afterward is doing real work.

### The curve in Swift {#apply}

`apply(_:)` is the definitive version of the curve; the shader transcribes it, and tests pin input–output pairs so the two can't drift silently. Your game can call it to pick an interface color that matches the tone-mapped scene.

## The interface is drawn after tone mapping {#hud}

This ordering is built into the engine, not left as a convention. Scene color is *radiance*: unbounded, linear and tone-mapped. Interface color is a *specification*: it must land on screen as exactly the value it was authored as. A HUD drawn inside the scene goes through exposure and a filmic curve like everything else, and a brand color comes out desaturated and shifted with nothing to explain why.

So `GameLoop` has a separate hook. `encode(into:frameSlot:interpolation:)` draws the scene, and `encodeHUD(into:frameSlot:interpolation:)` draws the interface after the curve. `InterfaceColor` is the interface's color type. It takes an sRGB value, such as `InterfaceColor(hex: 0x00C2FF)` or `InterfaceColor(srgb:)`, and converts it once to linear. The `_srgb` drawable encodes it back on write, so the round trip is exact: `#00C2FF` authored is `#00C2FF` on screen, verified by reading pixels back. See [HUD](hud.html).

Particles are the reverse case. A spark belongs to the scene, so it goes through the curve like the lamp it came from. See [particles](particles.html).

## What is deliberately not here {#not-here}

**No auto-exposure.** Metering a frame, deciding what "correctly exposed" means and smoothing adaptation over time all depend on the game. **No bloom, color grading or vignette.** Those are a look. Tone mapping is the part without which there is no picture.
