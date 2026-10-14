---
title: The splash
description: SplashScreen shows the engine's mark and name over your game for a couple of seconds, fading in and out, skippable without eating the key that skipped it.
---
`SplashScreen` is the engine saying its own name: the engine's mark and "Windage Engine" over a dark ground, fading up, holding and fading away. A game that wants to credit the engine at launch has nothing to build: no art, no texture and no pipeline, because it is drawn with the [HUD](hud.html). Nothing runs unless your game runs it.

## What it shows {#lockup}

One line across: an optional **lead**, the mark, and the name, with "WINDAGE" large over "ENGINE" small and tracked out. With `lead: "MADE WITH"`, as the sample uses, the lead sits in small capitals to the left of the mark, one word per line.

The name is set in the HUD's font rather than drawn: the engine has a drawn [mark](mark.html) but not yet a drawn wordmark. There is **no version** on it by default. `showsVersion` exists for development builds and is off, because no shipped game shows its engine's version.

## Using it {#use}

It is an overlay and a clock, not a mode. **Advance it from your simulation step, draw it from your HUD**, and drop it when it is done. From the sample:

```swift
private var splash: SplashScreen? = SplashScreen(lead: "MADE WITH")

func step(deltaTime: Float) {
    if splash != nil {
        splash?.advance(by: deltaTime)
        if splash?.isFinished == true { splash = nil }
    }
    // … the rest of the step runs as usual
}

func keyPressed(_ code: UInt16, command: Bool) {
    splash?.skip()
    // … and the key goes on to do what it was pressed for
}

func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
    guard let hud else { return }
    hud.begin(viewportSize: viewportSize)
    // … the game's own interface
    splash?.draw(into: hud, viewportSize: viewportSize)   // last, over everything
    hud.draw(into: encoder, frameSlot: frameSlot)
}
```

Three rules come with it:

- **Keep stepping behind it.** The game is usually loading during a splash. A game that suspends its step while the splash is up makes its first second unrepeatable.
- **`skip()` is a side effect of a press, never a consumer of one.** A splash that eats the first keystroke eats the first keystroke of whatever the player was already doing. The sample checks this with a scripted walk run under the splash, which must end exactly where the same walk ends without it. See [walks](walks.html).
- **Drop it when `isFinished` is true.** An overlay at zero opacity still costs its vertices.

Draw it last in `encodeHUD`, so it covers the game's own interface.

## Timing {#timing}

| Property | Default | Meaning |
| --- | --- | --- |
| `fadeIn` | 0.4 s | fading up from nothing |
| `hold` | 1.6 s | at full strength |
| `fadeOut` | 0.5 s | fading away |
| `skipDelay` | 0.25 s | presses ignored after it appears |

`duration` is the three together. `elapsed`, `opacity` (0 to 1), `isSkipped` and `isFinished` report where it is.

**A skip runs it to the start of its fade, not to its end.** A splash that vanishes on the frame a key goes down looks like a dropped frame; one that fades out looks intended. A skip is ignored for the first `skipDelay` seconds, because the key or click that launched the game is often still down when the first frame appears, and ignored again once it is fading, so holding a key does not cut the fade short twice.

**The fades are linear ramps** in `elapsed`, which is a sum of step lengths, so the picture at a given moment is the same at 30 steps a second and at 240. The tests check exactly that.

## Appearance {#appearance}

| Property | Default |
| --- | --- |
| `background` | `InterfaceColor(hex: 0x0B0D10)`, near-black so it reads as a surface |
| `foreground` | `EngineMark.display`, the light tone for dark grounds |
| `lead` | `nil`, no lead; the mark and name center on their own |
| `markScale` | `0.12` of the viewport's width; everything else is sized from the mark |
| `showsVersion` | `false` |

All are `var`s, set after `SplashScreen(lead:)`. If you set `showsVersion`, the text drawn is `Engine.version`.

## Your game's name {#your-name}

The splash says the engine's name, not yours. It reads `Engine.name`, which is `"Windage Engine"`, and there is no setting to put anything else in it. It is the engine's credit; the only words you choose are the `lead`.

Your game's own title card, logo or studio card is yours to draw, with the same tools. The [HUD](hud.html) draws text, rectangles and polygons in exact colors, so a title screen needs nothing from the engine beyond that. Show it before or after the engine's splash as you like; `SplashScreen` does not install itself in the frame loop or take control of what comes next.

Where the engine's name appears without a splash — a credits screen, an about box, a corner — draw the mark with `EngineMark.draw(into:origin:height:color:)` and set `Engine.name` beside it. The sample also puts the engine's name and version in its window title:

```swift
window.title = "\(Engine.name) \(Engine.version) — sample"
```

**The splash is optional.** What a game must show is a credits line — "Uses Windage Engine © 2026 Pixla LLC" in its credits or legal screen; the splash is a more visible credit on top of that, and nothing shows one unless your game does. See [the mark](mark.html#credit).

## In the sample

The sample opens with the splash in ordinary play. `WINDAGE_SAMPLE_SPLASH=1` or `0` forces it on or off; unset, it is off in a scripted check and in a recorded frame, because those are pictures of the scene. The splash has a recorded frame of its own. See [the sample](sample.html) and [frames](frames.html).
