---
title: Audio
description: AudioEngine plays positional one-shots and looping sounds tied to a place, and the character controller and level supply what a footstep needs to sound right.
---
`AudioEngine` plays sounds at positions in the world: one-shots for things that happen, and loops for things that keep making noise, like a brazier. Footsteps and landings come from the [character controller](character-controller.html), which reports what the body did, and from the [level](levels.html), which says what each surface is made of.

## What it does and does not do {#scope}

Every sound is spatialized: you give the listener each frame and a world position for each sound. The engine plays one-shots and loops tied to a place. It has **no music, no buses and no mixing groups**. Those come when a game needs them.

Sixteen one-shots can overlap (`AudioEngine.voiceCount`). Beyond that the oldest voice is reused, because the newest sound is the one that just happened.

## Setting it up {#setup}

```swift
// your game: nil when there is no output device, and the game runs quiet
if let audio = AudioEngine() {
    for sound in ["pickup", "crackle", "step_stone_0", "land_stone"] where !audio.load(sound, bundle: .module) {
        print("no sound named \(sound)")
    }
}
```

`load(_:withExtension:bundle:)` decodes a sound and keeps it in memory, with `wav` as the default extension. **`bundle` has no default on purpose.** In an app bundle the sounds are in `.main`, while in a SwiftPM executable `.main` holds nothing and the sounds are in `.module`. `load(_:samples:sampleRate:)` loads mono samples your game generates.

Move the listener once a frame:

```swift
audio?.updateListener(position: camera.position, forward: camera.forward, up: SIMD3(0, 1, 0))
```

## One-shots {#one-shots}

```swift
// your game
audio.play("pickup", at: cratePosition, volume: 0.8)
audio.play("impact", at: target, delay: distance / 343)   // sound takes time to travel
audio.play("win")                                         // not positioned
```

`play(_:at:volume:delay:)` plays a sound at a world position. `delay` is in seconds. At about 343 m/s, an impact 800 m away is heard nearly two and a half seconds after it happens. `play(_:volume:)` plays without a position, for sounds that happen *to* the player.

## Loops that belong to a place {#loops}

```swift
if let loop = audio.startLoop("crackle", at: position, volume: 0.8) {
    audio.moveLoop(loop, to: newPosition)
    audio.stopLoop(loop)
}
```

`startLoop(_:at:volume:)` returns an `AudioEngine.Loop` handle, and `stopAllLoops()` and `loopCount` cover the rest. Each loop starts at a different point in its sound, so two braziers playing the same crackle don't sound like one crackle in two places.

**Loops get their own spatializer with a different falloff.** One-shots are tuned for a sound heard across a range: full volume out to 8 m, then 90% of the inverse law. Through that curve, a brazier sounds as loud at 8 m as it does up close, and two of them fill a level with fire. Loops use the physical inverse law from `AudioEngine.loopReferenceDistance` (2 m) and measured 1 : 0.250 : 0.100 at 2, 8 and 20 m.

A placement can carry a sound in its own space, like its lamp. `Level.carriedSounds(on:)` gives each one's world position, so a brazier moved in the editor takes its crackle with it. When your level changes, **reconcile the loops instead of restarting them**. The sample matches loops by name and position first, and only then by placement index, because copying a placement renumbers every placement after it.

## Footsteps and landings {#footsteps}

The engine doesn't play footsteps itself. It gives your game the two facts it needs:

- **What the body did.** `CharacterController.events` lists this step's `.stride(foot:speed:)`, `.landed(impactSpeed:)` and `.jumped`, in order. The list is cleared at the start of every step, so read it after `step`.
- **What is underfoot.** `CharacterController.groundSolid` says which solid the feet are on. `Level.surface(standingOn:)` turns the matching placement into its `surface`, or the level's `groundSurface` for `nil`.

Here is the sample's version, trimmed (`variant` picks one of three recordings). Footsteps are not positioned, because they happen to the player:

```swift
var surface = level.surface(standingOn: placement) ?? "stone"
for event in body.events {
    switch event {
    case .stride(_, let speed):
        let crouched = body.tuning.walkSpeed * body.tuning.crouchedSpeedFraction
        let t = simd_clamp((speed - crouched) / (body.tuning.sprintSpeed - crouched), 0, 1)
        audio?.play("step_\(surface)_\(variant)", volume: 0.3 + 0.7 * t)
    case .landed(let impact):
        audio?.play("land_\(surface)", volume: simd_clamp(impact / 9, 0.35, 1))
    case .jumped:
        audio?.play("step_\(surface)_0", volume: 0.4)
    }
}
```

A few details are worth knowing:

- **Strides are counted from the distance the feet actually covered**, not the distance asked for. A player pushing into a wall doesn't march on the spot.
- **Strides are longer than a person's because the speeds are faster.** `walkStride`, `sprintStride` and `crouchStride` (2.6, 5 and 1.6 m) give about 2.3, 3.6 and 1.7 steps a second. The first footstep comes partway into a stride (`firstStepPhase`), so a walk doesn't start silent.
- **Each stair tread gets a footstep.** A step up or down counts as a foot landing, whatever the stride says. A step down a stair is not a `.landed`, and a slide makes no footsteps.
- **`surface(standingOn:)` returns `nil` for a placement that names no surface.** It doesn't fall back to the ground's, so the gap can be noticed. The sample logs it once and plays stone.

## Volume {#volume}

`masterVolume` scales everything. `ambienceVolume` scales only the loops, so a player who finds a fire too loud doesn't lose their own footsteps turning it down. `PlayerSettings.ambienceVolume` is the matching player setting. Measured: half ambience lowers a loop by 6.02 dB and a one-shot by 0.0.

## Measuring without listening {#offline}

`AudioEngine(offlineSampleRate:)` makes an engine with no device, and `renderOffline(seconds:)` returns the mix as one array per channel. The falloff numbers on this page were measured that way. `WINDAGE_SAMPLE_MEASURE_AUDIO=1 swift run WindageSample` measures the sample's own crackle at several distances.

> **Before adding an AVFoundation callback:** a closure written inside the engine's methods inherits main-actor isolation, and AVFoundation calls it on a realtime audio thread, which crashes. Mark it `@Sendable` and give it its own thread-safe storage.
