---
title: Levels and the editor
description: Level, the engine's versioned JSON level format, and LevelEditor, an editor a game embeds to change its own levels while it runs.
---
A level is a file, not code: things placed in space, points that mean something to the game, the sky, and the lamps. `Level` reads and writes it as JSON, and `LevelEditor` is the selection, operations, undo and save that let a game edit its own levels in place, without a window of its own.

## What a level holds {#format}

`Level` is a `Codable` value type with a format version, a name, and these fields:

| Field | What it is |
| --- | --- |
| `placements` | `[Level.Placement]`: a mesh name, a `position`, a `yaw` in radians, a `scale`, an `anchor`, `tags`, and optionally a `light`, a `surface` and a `sound` |
| `markers` | `[Level.Marker]`: a `kind`, an optional `name`, a position, an anchor, a yaw and `values` |
| `lights` | `[PunctualLight]`: free-standing lamps |
| `sky` | an optional `ProceduralSky`; `resolvedSky` gives a plausible one when the file has none |
| `settings` | `[String: Double]`: numbers your game interprets |
| `groundSurface` | what the ground is made of, for footsteps |

**The engine does not interpret any of the words.** A marker's `kind`, a placement's `tags` and its `surface` are your game's vocabulary. The sample reads `"spawn"` and `"objective"` markers and a `"solid"` tag; another game reads its own. The engine never adds a `.spawn` case, so the format has no opinion about genre.

Every field except `formatVersion` may be left out, so a file written before a field existed still loads. Placements leave out `yaw`, `scale`, `anchor` and `tags` when they hold their default values, which keeps a large level small.

## A real level {#excerpt}

This is trimmed from the sample's `Sources/WindageSampleCore/Resources/ruins.json`: one spawn marker and one brazier that carries its own lamp and crackle.

```json
{
  "formatVersion" : 1,
  "groundSurface" : "dirt",
  "markers" : [
    {
      "anchor" : "absolute",
      "kind" : "spawn",
      "name" : "start",
      "position" : [ 0, 0, 6 ],
      "values" : { "pitch" : -6 }
    }
  ],
  "name" : "RUINS",
  "placements" : [
    {
      "anchor" : "absolute",
      "light" : {
        "color" : [ 1.0, 0.6, 0.3 ],
        "intensity" : 60,
        "position" : [ 0, 1.8, 0 ],
        "range" : 14
      },
      "mesh" : "brazier",
      "position" : [ -4.0, 0, -10 ],
      "sound" : { "name" : "crackle", "offset" : [ 0, 1.0, 0 ], "volume" : 0.8 },
      "surface" : "metal",
      "tags" : [ "solid" ]
    }
  ]
}
```

In the file a lamp's `color` and `intensity` are separate, because a person thinks about them separately. In code they are one value, `PunctualLight.color`, which is the color multiplied by its brightness. A cone is added by giving a `direction`. `innerAngle` and `outerAngle` are in degrees.

## Things that travel with a placement {#carried}

A lamp or a sound on a placement is **in the placement's own space**, so moving, turning, copying or deleting the brazier takes its light and its crackle with it. The lamp's offset scales with the placement. Its range and brightness don't. Before this existed, a brazier and its flame were two entries in one file, and moving the brazier in the editor left its light on the floor.

Turn a level into world positions against your game's ground:

```swift
// your game: the ground is the plane y = 0
let ground = Level.Ground(height: { _, _ in 0 })   // ground.height(atX:z:) asks it

let lights = level.resolvedLights(on: ground)     // free-standing first, then carried
let sounds = level.carriedSounds(on: ground)      // each a CarriedSoundInWorld: placement, name, position, volume
let matrix = level.transform(of: level.placements[0], on: ground)
```

`Level.Anchor` says how `y` is read. With `.absolute` it is a world height. With `.ground` it is an offset from the ground under the origin. With `.beddedFootprint` it is an offset from the lowest ground under the mesh's footprint, which needs `footprintCorners` on the `Ground`. Storing an offset instead of a height means a level stays on the ground when the terrain changes.

## Loading and saving {#load}

```swift
let level = try Level.load(named: "ruins", bundle: .module)
```

`Level.load(named:withExtension:bundle:)` reads **from a bundle, never from an arbitrary path**, so the engine runs the same way sandboxed or not. `Level.decode(from:)` reads data you already have. Every failure is a `LevelError` — `.notFound`, `.unreadable`, `.malformed`, or `.unsupportedVersion` for a file written by a newer format, so a newer file can't load with pieces silently missing. `encoded()` writes sorted, pretty-printed JSON, so a save that changes nothing produces no diff.

A bundle is read-only, so the sample saves edits to its own folder in Application Support. From then on, that copy **shadows** the shipped file. The sample prints which file it loaded, and **⌘⌫** throws the copy away. Do the same in your game, or someone will edit the shipped file and see nothing change.

## LevelEditor {#editor}

`LevelEditor` wraps a `Level` and owns everything an edit means. Your game only turns keys and clicks into its calls and draws the result:

```swift
var editor = LevelEditor(level: level)                 // or level:configuration: for your own steps

editor.select(index)                                   // from your own picking
editor.move(by: SIMD3(editor.configuration.nudge, 0, 0))   // 0.5 m
editor.rotate(by: editor.configuration.turn)           // 15°
editor.scale(by: 1.25)                                 // clamped to 0.05…100
editor.duplicate()
editor.delete()
editor.undo()
try editor.save(to: url)                               // clears isDirty
```

- **Lamps:** `setLight(_:)` gives the selected placement a lamp, replaces it, or removes it with `nil`. `raiseLight(by:)` moves it in meters of the world, whatever the placement's scale. `brightenLight(by:)` works in ratios, and the default `configuration.lampBrighten` is a third of a stop.
- **Adding:** `add(_:at:yaw:)` drops another of one of `editor.kinds()` at a ground point, bringing its height, scale, tags, surface and lamp. `add(mesh:at:tags:light:)` knows only the mesh.
- **Undo** is 64 steps deep by default (`configuration.undoDepth`). An edit that changes nothing records nothing.
- **`isDirty` means different from what was saved**: undoing back to the saved level is clean again, and redoing away from it is not.
- **Saving is atomic**, like `SaveStore`: a crash mid-save leaves the old file.

`LevelEditor.Configuration` holds the steps a key makes — `nudge`, `turn`, `lampRaise`, `lampBrighten` — with the lamp's brightness range and the undo depth, and every default is the value above.

In the sample, **Tab** opens the editor. Click (or space) picks what is under the crosshair, the arrow keys and **q**/**e** move it, **a**/**d** turn it, **-**/**=** scale it, **b** copies it, **l** and **[ ] , .** handle the lamp, **t** and **i** add things, **⌘S** saves and **⌘Z** undoes. See [the sample](sample.html).

> **Deliberately absent:** gizmos, snapping to other geometry, multi-select, prefabs and a scene graph. `LevelEditor` needs no window, so all of it runs in `swift test`.

Lamps are covered in [lights](lights.html), and carried sounds and surfaces in [audio](audio.html).
