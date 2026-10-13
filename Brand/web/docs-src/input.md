---
title: Input and settings
description: Read keyboard, mouse and controller through InputState, add your game's own actions, let players rebind keys and pad buttons, and keep sensitivity, invert, dead zones and head bob in PlayerSettings.
---
`InputState` turns keyboard, mouse and controller into **axes, actions and intents** — `movement`, `consumeLook()`, `lookRate`, `isHeld(_:)` — so nothing downstream reads key codes. `InputBindings` and `PadBindings` say which key and button does what, for the engine's actions and your game's own; `PlayerSettings` holds those and everything else a player sets once.

## Feeding it events

Call `start()` once, when your window opens — it listens for controllers connecting. Then forward the window's events. Your game gets first refusal on each key:

```swift
func keyPressed(_ key: KeyCode, command: Bool) {
    if key == .escape {
        if !handleKey(key, command: false) { input.setMouseCaptured(false) }
        return
    }
    if handleKey(key, command: command) { return }
    input.keyDown(key)
}

func keyReleased(_ key: KeyCode) { input.keyUp(key) }

func modifiersChanged(_ key: KeyCode, flags: NSEvent.ModifierFlags) {
    input.flagsChanged(key: key, modifierFlags: flags)
}
```

The view makes the `KeyCode` from the event: `KeyCode(rawValue: event.keyCode)`. In your own code, name keys by their statics — `.w`, `.space`, `.leftShift`, `.digit1` — or by `KeyCode(named:)` for a name read from a file.

> **Forward `flagsChanged`.** macOS sends Shift, Control, Option and Command only as modifier flags, so a window forwarding `keyDown` and `keyUp` alone has no Shift at all. Through `flagsChanged(key:modifierFlags:)` a modifier is a key like any other, and can be bound.

The mouse goes in with `addMouseDelta(x:y:)` (counted only while `setMouseCaptured(true)`), `setLeftMouse(_:)` and `setRightMouse(_:)`; scroll with `addScroll(_:)`, out as whole notches from `consumeScroll()`. Call `releaseAll()` when the window loses focus, or a held key stays held forever, and `stop()` when it closes.

## Reading it

Once a frame, call `pollFrame()` — it finds controller presses — and take the mouse once, since it is a displacement that already happened. It comes out already through the player's sensitivity and invert:

```swift
input.pollFrame()
camera.look(mouseDelta: input.consumeLook())
```

The stick is a rate, so it goes in every step:

```swift
camera.turn(rate: input.lookRate, deltaTime: deltaTime)
```

The body reads the engine's actions — see [CharacterController](character-controller.html):

| Read | What it is |
| --- | --- |
| `movement` | a `MovementInput`: `forward` and `strafe` from keys and the left stick, clamped to −1…1, and `isSprinting` |
| `isJumpHeld` | Space, or the bottom face button — held state; the controller finds the press |
| `isCrouching` | a latch: press to crouch, press to stand. `standUp()` ends it |
| `consumeSteps()`, `consumeNext()` | the arrows and d-pad as discrete steps, and Tab as a generic "next" |

A sprint press while crouched stands the player up. On a pad, the stick click **latches** sprint — that thumb is steering — and lets go when the player stops pushing forward; Shift stays held. A game that gives the stick click a second job sets `padSprintLatches = false` while it applies.

## Your game's own actions

The engine acts on walking, jumping, crouching and sprinting, and nothing else. **Fire, aim, reload, use — every verb your game has — is an `InputAction` you name**, bound and read like the engine's:

```swift
extension InputAction {
    nonisolated static let reload = InputAction("reload")
}

input.bindings = InputBindings.standard.adding(.reload, defaultKey: .r)
input.padBindings = PadBindings.standard.adding(.reload, defaultButton: .west)

if input.consumePresses(of: .reload) > 0 { weapon.reload() }
```

| Read | What it is |
| --- | --- |
| `isHeld(_:)` | the action's key or pad button is down; `isKeyHeld(_:)` and `isPadHeld(_:)` for one device |
| `consumePresses(of:)` | presses since you last asked — once a step; a toggle flips on an odd count |
| `isLeftMouseHeld`, `isRightMouseHeld` | the mouse buttons, as the window reported them |
| `leftTrigger`, `rightTrigger` | how far each trigger is pulled, 0…1 — how far is far enough is yours |

The action's name is what a settings file stores, so keep it stable; what a settings screen calls it is your game's to say.

## Rebinding keys

`InputBindings` maps each action to one `KeyCode`. A `KeyCode` is a key position, not a letter, so movement stays under the left hand on any layout; its `name` is the US legend. `standard` binds the engine's seven actions; `actions` lists every one, in the order a settings screen shows them.

```swift
let outcome = settings.bindings.bind(action, to: key, reserving: SampleGame.reservedKeys)
switch outcome {
case .bound:              menu?.message = "\(title(of: action)) is \(key.name)"
case .swapped(let other): menu?.message = "\(title(of: action)) is \(key.name) — \(title(of: other)) moved to "
                              + (settings.bindings[other]?.name ?? "")
case .refused:            menu?.message = "\(key.name) cannot be bound"
}
```

The rules:

- **A key in use is swapped, not stolen**, so every action still has one.
- **Escape, Tab and the arrows are refused** (`InputBindings.fixed`). Escape is the way out.
- **Pass your game's own keys in `reserving:`** — the sample reserves P, R, N, M and O, so jump on P cannot pause the game.

## Rebinding controller buttons

`PadBindings` does the same for the actions that are buttons — the engine's jump, crouch and sprint, and any your game adds. A `PadButton` is a position — `south`, `east`, `west`, `north`, the shoulders, the stick clicks — and `name(on:)` asks the connected pad what it prints there.

By default south jumps, east crouches and the left stick click sprints. **The engine keeps no button for itself**: west, north and the shoulders are the convention's reload, weapon swap, equipment and grenade, and a game that has them reserves them in `reserving:`.

While a menu has the pad, set `acceptsPadActions = false` and read raw `padButtonsPressed` and `wasPadMenuPressed`, or leaving the menu also crouches the player. `useGamepad(_:)` reads a pad pressed from code instead, for tests.

## PlayerSettings

Every value clamps itself to its range.

| Field | Default | Range |
| --- | --- | --- |
| `bindings`, `padBindings` | `.standard`, or what you pass to `init(bindings:padBindings:)` | |
| `mouseSensitivity`, `stickSensitivity` | 1 | 0.1…5 |
| `invertMouse`, `invertStick` | false | |
| `moveDeadzone`, `lookDeadzone` | 0.16, 0.10 | 0…0.5 |
| `headBobAmount` | 1 | 0…1, 0 is off |
| `volume`, `ambienceVolume` | 0.8, 1 | 0…1 |
| `brightness` | 0 | −2…2 stops |

**Hand them to input in one call**, and save on every change; the sample has no apply button:

```swift
input.apply(settings)
try SampleGame.settingsStore.save(settings)
```

`apply(_:)` sets both bindings, the dead zones, and each device's sensitivity and invert. Volume, brightness and head bob are not input's, and stay with your game.

The store is a `SaveStore<PlayerSettings>` ([saving](saving.html)). Decoding is **tolerant, field by field**, so an older file loads with everything it said intact. Keys are stored by name: `"forward" : "W"`. **Add your game's actions after loading** — `settings.bindings = settings.bindings.adding(.reload, defaultKey: .r)` — and the key the player chose for each is found in the file.

## Dead zones and the stick curve

`InputState` shapes each stick with `StickResponse.shaped(_:deadzone:exponent:)`. The dead zone is **radial** — a per-axis one feels dead on the diagonals — and the response runs from zero at its edge to full at full deflection, so a bigger dead zone never costs top speed. `moveExponent` is 1.3; `lookExponent` 2.0 gives fine aim near the center — both are properties on `InputState`, for a game with its own feel.

## What it does not do

One key per action, no secondary slot. The sticks, triggers, d-pad and menu button cannot be rebound.
