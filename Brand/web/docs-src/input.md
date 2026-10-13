---
title: Input and settings
description: Read keyboard, mouse and controller through InputState, let players rebind keys and pad buttons, and keep sensitivity, invert, dead zones and head bob in PlayerSettings.
---
`InputState` turns keyboard, mouse and controller into **axes and intents** — `movement`, `consumePendingLook()`, `lookRate`, `isJumpHeld` — so nothing downstream reads key codes. `InputBindings` and `PadBindings` say which key and button does what; `PlayerSettings` holds those and everything else a player sets once.

## Feeding it events

Forward the window's events to it. Your game gets first refusal on each key:

```swift
func keyPressed(_ code: UInt16, command: Bool) {
    if code == KeyCode.escape.rawValue {
        if !handleKey(code, command: false) { input.setMouseCaptured(false) }
        return
    }
    if handleKey(code, command: command) { return }
    input.keyDown(code)
}

func keyReleased(_ code: UInt16) { input.keyUp(code) }

func modifiersChanged(_ code: UInt16, flags: UInt) {
    input.flagsChanged(keyCode: code, modifierFlags: flags)
}
```

> **Forward `flagsChanged`.** macOS sends Shift, Control, Option and Command only as modifier flags, so a window forwarding `keyDown` and `keyUp` alone has no Shift at all. Through `flagsChanged(keyCode:modifierFlags:)` a modifier is a key like any other, and can be bound.

The mouse goes in with `addMouseDelta(x:y:)` (counted only while `setMouseCaptured(true)`), `setLeftMouse(_:)` and `setRightMouse(_:)`; scroll with `addScroll(_:)`, out as whole notches from `consumeScroll()`. Call `releaseAll()` when the window loses focus, or a held key stays held forever.

## Reading it

Once a frame, call `pollFrame()` — it finds controller presses — and take the mouse once, since it is a displacement that already happened:

```swift
input.pollFrame()
let look = input.consumePendingLook()
camera.look(mouseDelta: look * settings.mouseLookScale)
```

The stick is a rate, so it goes in every step:

```swift
camera.turn(rate: input.lookRate * settings.stickLookScale, deltaTime: deltaTime)
```

The body reads the rest — see [CharacterController](character-controller.html):

| Read | What it is |
| --- | --- |
| `movement` | a `MovementInput`: `forward` and `strafe` from keys and the left stick, clamped to −1…1, and `sprint` |
| `isJumpHeld` | Space, or the bottom face button — held state; the controller finds the press |
| `isCrouching` | a latch: press to crouch, press to stand |
| `isBraced` | a latched posture; what it means is your game's. `releaseBrace()` ends it |
| `isAiming`, `isFiring`, `isSteadying` | right and left mouse, or the triggers past halfway; Shift or L3 while aiming |
| `consumeSteps()`, `consumeNext()` | the arrows and d-pad as discrete steps, and Tab as a generic "next" |

A sprint press while crouched stands the player up. On a pad, the stick click **latches** sprint — that thumb is steering — and lets go when the player stops pushing forward; Shift stays held.

## Rebinding keys

`InputBindings` maps eight `Action`s — `forward`, `back`, `left`, `right`, `jump`, `crouch`, `sprint`, `brace` — to one `KeyCode` each. A `KeyCode` is a key position, not a letter, so movement stays under the left hand on any layout; its `name` is the US legend.

```swift
let outcome = settings.bindings.bind(action, to: key, reserving: SampleGame.reservedKeys)
switch outcome {
case .bound:              menu?.message = "\(action.title) is \(key.name)"
case .swapped(let other): menu?.message = "\(action.title) is \(key.name) — \(other.title) moved to "
                              + settings.bindings[other].name
case .refused:            menu?.message = "\(key.name) cannot be bound"
}
```

The rules:

- **A key in use is swapped, not stolen**, so every action still has one.
- **Escape, Tab and the arrows are refused** (`InputBindings.fixed`). Escape is the way out.
- **Pass your game's own keys in `reserving:`** — the sample reserves P, R, N, M and O, so jump on P cannot pause the game.

## Rebinding controller buttons

`PadBindings` does the same for jump, crouch, sprint and brace. A `PadButton` is a position — `south`, `east`, `west`, `north`, the shoulders, the stick clicks — and `name(on:)` asks the connected pad what it prints there.

By default south jumps, east crouches, the left stick click sprints and the left shoulder braces. The right stick click is refused: it is the scroll notch. West, north and the right shoulder are free by default; a game with a reload reserves one.

While a menu has the pad, set `acceptsPadActions = false` and read raw `padButtonsPressed`, or leaving the menu also crouches the player. `useGamepad(_:)` reads a pad pressed from code instead, for tests.

## PlayerSettings

Every value clamps itself to its range.

| Field | Default | Range |
| --- | --- | --- |
| `bindings`, `padBindings` | `.standard` | |
| `mouseSensitivity`, `stickSensitivity` | 1 | 0.1…5 |
| `invertMouse`, `invertStick` | false | |
| `moveDeadzone`, `lookDeadzone` | 0.16, 0.10 | 0…0.5 |
| `headBob` | 1 | 0…1, 0 is off |
| `volume`, `ambienceVolume` | 0.8, 1 | 0…1 |
| `brightness` | 0 | −2…2 stops |

**Sensitivity and invert are per device** — use `mouseLookScale` and `stickLookScale`, as above. Apply and save on every change; the sample has no apply button:

```swift
input.bindings = settings.bindings
input.padBindings = settings.padBindings
input.moveDeadzone = settings.moveDeadzone
input.lookDeadzone = settings.lookDeadzone
try SampleGame.settingsStore.save(settings)
```

The store is a `SaveStore<PlayerSettings>` ([saving](saving.html)). Decoding is **tolerant, field by field**, so an older file loads with everything it said intact. Keys are stored by name: `"forward" : "W"`.

## Dead zones and the stick curve

`InputState` shapes each stick with `StickResponse.shaped(_:deadzone:exponent:)`. The dead zone is **radial** — a per-axis one feels dead on the diagonals — and the response runs from zero at its edge to full at full deflection, so a bigger dead zone never costs top speed. `moveExponent` is 1.3; `lookExponent` 2.0 gives fine aim near the center.

## What it does not do

One key per action, no secondary slot. The sticks, triggers, d-pad and menu button cannot be rebound.
