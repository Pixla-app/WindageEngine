---
title: Saving
description: SaveStore keeps any Codable value between runs, atomically, in a place that works sandboxed or not; PlayerSettings is the settings every first-person game needs.
---
`SaveStore` keeps what your game remembers between runs. It stores any `Codable` value as a JSON file, atomically, in the one place a Mac app can always write, sandboxed or not. `PlayerSettings` is the engine's share of a settings screen, ready to save with it.

## SaveStore {#savestore}

```swift
let store = SaveStore<SampleRun.Progress>(container: "WindageSample", name: "progress")

let progress = store.load() ?? SampleRun.Progress()   // nil when there is nothing, or it cannot be read
try store.save(progress)
store.clear()                                         // "reset progress"
```

`SaveStore<Value: Codable & Sendable>` is a small value type:

| Member | What it does |
| --- | --- |
| `init(container:name:)` | `container` is the folder for your game; `name` is the file, without extension |
| `url` | where the file lives; creates the folder if needed, writes nothing else |
| `load() -> Value?` | the saved value, or `nil` |
| `save(_:) throws` | writes the value, replacing what was there |
| `clear()` | removes the file |

**Name the container after your game**, so two games on one machine do not collide and a person can find your files. Use one store per kind of thing: the sample keeps settings and progress apart, so resetting progress does not reset a player's keys.

```swift
private static let settingsStore = SaveStore<PlayerSettings>(container: container, name: "settings")
```

### Where files go {#where}

The file is `<container>/<name>.json` in the user's **Application Support** folder:

- Unsandboxed, that is `~/Library/Application Support/<container>/`.
- Sandboxed, macOS gives the app its own Application Support inside its container, and the same code resolves to it.

This is why `SaveStore` is in the engine at all. **The engine never assumes a writable location outside the app's container**, because your game, not the engine, is what gets distributed, and it may be sandboxed. A path beside the executable works right up until the app is sandboxed, so there is one place that knows where a game may write. Resources you ship are read from bundles. The save itself is pretty-printed JSON with sorted keys.

### Atomic writes {#atomic}

`save` writes to a temporary file and renames it over the old one, and a rename is atomic. If the game crashes mid-write, the save is either the old one or the new one, never half of either.

### A bad file reads as nothing {#bad-file}

`load()` returns `nil` rather than throwing when the file is missing, truncated, or written by a build that cannot be decoded. A save that will not load must not stop the game starting: losing a high score is a disappointment; refusing to launch is a bug report.

That is the right failure for progress and a bad one for settings, where `nil` means every setting reset. The fix is in the type you save, not in `SaveStore`; see versioning below.

**In tests**, use a container of your own and clear what you write: tests sharing the real file clobber a player's save, and parallel tests clobber each other.

## PlayerSettings {#settings}

`PlayerSettings` is what a player sets once and expects to find set again. It is `Codable`, so it saves through a `SaveStore` as it is:

```swift
private var settings = SampleGame.settingsStore.load() ?? PlayerSettings()

// Written the moment anything changes: no "apply" button to forget.
try SampleGame.settingsStore.save(settings)
```

| Property | Default | Range |
| --- | --- | --- |
| `bindings` | `InputBindings.standard` | which key does what |
| `padBindings` | `PadBindings.standard` | which controller button does what |
| `mouseSensitivity`, `stickSensitivity` | `1` | `PlayerSettings.sensitivityRange`, 0.1…5 |
| `invertMouse`, `invertStick` | `false` | |
| `moveDeadzone`, `lookDeadzone` | `StickResponse.moveDeadzone`, `.lookDeadzone` | `PlayerSettings.deadzoneRange`, 0…0.5 |
| `headBob` | `1` | 0…1; 0 is off |
| `volume` | `0.8` | 0…1 |
| `ambienceVolume` | `1` | 0…1, under `volume` |
| `brightness` | `0` | `PlayerSettings.brightnessRange`, −2…2 stops |

Every numeric setting is clamped to its range when set, and a value that is not finite falls back to its default. `mouseLookScale` and `stickLookScale` give the multipliers to apply before `Camera.look(mouseDelta:)` and `Camera.turn(rate:deltaTime:)`. See [input](input.html) for bindings and the rules for rebinding.

A game with more settings, such as a field of view, a difficulty or subtitles, keeps them **beside** `PlayerSettings` rather than inside it.

## Versioning saved data {#versioning}

`SaveStore` does not version what it stores; the type you save does. Two patterns, both in the engine and its sample:

**Decode field by field.** `PlayerSettings` decodes every field as optional: a missing field takes its default, an unknown one is ignored, and a key name this build does not recognize costs only that one binding. A settings file from an older build loads into a newer one with everything it did say intact. A file from before 0.8.0 has one sensitivity and one invert, and both devices inherit them.

**Carry a version from the first save.** The sample's `SampleRun.Progress` has a `version` field and `currentVersion = 2`. Version 1 held a single best time; version 2 keeps one per level. A version 1 save migrates when it loads instead of being discarded, and the encoder never writes the old field, so migration is one way.

> The first save format that needs changing is always one that did not have a version. Add the field before you need it.

`Engine.version` is the engine's version, not your save's: a save's format changes when your data does.

## What it does not do

- **No cloud sync or save slots.** One value per file; several slots are several stores with different names.
- **No encryption.** The file is plain JSON a player can edit.
- **No background writes.** `save` writes when called.

The sample's level editor saves edited levels to the same folder; see [levels](levels.html).
