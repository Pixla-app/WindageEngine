---
title: The mark
description: EngineMark is the engine's mark as geometry — drawn in your HUD at any size, and written to the SVG files in Brand/ by a test.
---
`EngineMark` is the engine's mark, the Drift W, as geometry. Draw it into your [HUD](hud.html) at any size to credit the engine in a corner, a credits screen or an about box; the [splash](splash.html) uses it the same way. The SVG files in `Brand/` are written from the same geometry, so there is one drawing of the mark, not several that drift apart.

## What it is a picture of {#drawing}

*Windage* is the sideways carry of a shot, and the correction dialed against it. The mark is a W drawn as one continuous stroke whose **right half is carried up by 16% of its own height**. The middle apex sits well below both shoulders, which is what makes it read as a W rather than two Vs; the lift is the windage.

The mark is square: `EngineMark.width(forHeight:)` returns the height.

## Drawing it {#draw}

```swift
// Your game, inside encodeHUD, between hud.begin(viewportSize:) and hud.draw(into:frameSlot:).
let height: Float = 48
EngineMark.draw(into: hud, origin: viewportSize - height - 24, height: height, color: EngineMark.display)
```

`draw(into:origin:height:color:)` fills the mark with its top-left corner at `origin` in the HUD's coordinates. It needs no texture, no resource and no pipeline of its own: it is a call to `HUDRenderer.fillPolygon(_:color:feather:)`, with the HUD's default one-unit feather so its diagonals are not stair-stepped. A height of 0, or a color with zero alpha, draws nothing.

### The outline

`EngineMark.outline` is the shape itself: thirteen points in a unit square, **origin at the top left, y downward**, the same as `HUDRenderer`, in order around the letter starting at the left shoulder. Scale and offset it yourself if you want the mark in something other than the HUD:

```swift
let points = EngineMark.outline.map { SIMD2(x, y) + $0 * height }
```

It is constructed, not traced: five points on the stroke's center line (left shoulder, left valley, middle apex, right valley, right shoulder) and a stroke width measured across, as type is. Each arm's edges are its center line moved half the width either way, every corner is where two of those edges meet, and every end is cut flat. The tests check that it stays inside its square, never crosses itself, has its apex cut flat and well below the shoulders, and that only its right half is lifted.

## Two tones, no hue {#tones}

| Tone | Value | For |
| --- | --- | --- |
| `EngineMark.display` | `#F2F4F7` | dark grounds: a game, a splash, a store capsule |
| `EngineMark.deep` | `#1B2027` | light grounds: a page, print, anything that must meet a contrast ratio |

Both are `InterfaceColor`s, drawn exactly as authored because the HUD draws after tone mapping.

**The mark has no hue on purpose.** It appears inside somebody else's game, where the game's own colors should lead. A hue of its own would be a second brand competing with the one the player came for. You may pass any `InterfaceColor` to `draw`, but the two tones are the mark as intended.

## The files in Brand/ {#files}

`EngineMarkTests` writes every SVG of the mark from `EngineMark.outline`, and fails if a file on disk and the outline disagree:

| File | What it is |
| --- | --- |
| `windage-engine.svg` | the mark in `deep`, for light grounds |
| `windage-engine-display.svg` | the mark in `display`, for dark grounds |
| `windage-engine-icon.svg` | an app icon on a 1024 canvas: an 824 tile inset 100, the mark at 56% |
| `favicon.svg` | a full-bleed tile with the mark at 76%, for a browser tab |

Each file carries the engine's name as its title. `Brand/exports/` holds PNGs of all four at the sizes a site, a store page and a Dock need, rasterized from the SVGs by `Tools/make_brand_exports.sh` (which needs `rsvg-convert`; it is a brand tool, not part of the build).

**Changing the mark** means changing the construction in `EngineMark.swift`, never a file:

```sh
WINDAGE_RECORD_MARK=1 swift test --filter EngineMarkTests
Tools/make_brand_exports.sh
python3 Tools/frames.py --record splash
```

The last line re-records the splash's frame, which keeps a picture of the mark on screen with a tolerance of its own, because a lit scene's tolerance could not see a mark move. See [frames](frames.html).

## Crediting the engine {#credit}

**Required: a credits line.** A game that ships the engine names it in its credits or legal screen — for example *"Uses Windage Engine © 2026 Pixla LLC"* — with where the license can be read (PolyForm Small Business 1.0.0, whose `Required Notice:` line this is). That is the whole requirement, as it is for Unreal and Godot. **A splash is not required.** Showing the engine's name or mark more visibly is your choice; ways to do it, from most to least visible:

1. **The splash.** `SplashScreen(lead: "MADE WITH")` at launch: the mark and the name, two and a half seconds, skippable. See [the splash](splash.html).
2. **The mark in your interface.** `EngineMark.draw` on a title screen, a credits roll or an about box, with `Engine.name` set beside it through `HUDRenderer.text`.
3. **The files.** `windage-engine.svg` or `windage-engine-display.svg` on a store page, a website or printed material, or the PNGs from `Brand/exports/`.

Write the name as **Windage Engine**, in title case, in running text, menus and window titles. The capitals `WINDAGE ENGINE` are the splash's lockup setting, not a second spelling. There is no drawn wordmark yet: where the name sits beside the mark, it is set in a font.

Don't recolor the mark with a hue, add an accent to its lifted half, or redraw it from a picture. The outline is the mark.
