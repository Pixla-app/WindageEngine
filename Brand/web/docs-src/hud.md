---
title: The HUD
description: HUDRenderer draws text, rectangles, lines, rings and polygons in screen space, after tone mapping, so interface colors land exactly as authored.
---
`HUDRenderer` draws your game's interface: text, filled and outlined rectangles, lines, rings and polygons, in screen space, after the scene has been tone mapped. Use it for a reticle, a timer, a bar, a panel, a settings screen or a credit. It is one pipeline and one draw call for the whole interface.

## Why it draws after tone mapping {#order}

Scene colors are radiance: they pass through an exposure and a filmic curve on the way to the screen, by design. An interface color is a specification, and a brand color must land on screen as exactly that color. So `FrameRenderer` calls your `GameLoop`'s `encodeHUD(into:frameSlot:)` **after** the scene and its tone map, and the HUD's pipeline applies no curve. The ordering is structural, not something each game has to remember.

`encodeHUD` has a default implementation that does nothing; implement it to draw an interface. See [tone mapping](tone-mapping.html) for what happens to the scene before it.

## Making one {#init}

```swift
hud = HUDRenderer(device: device, additionalCharacters: ["⌘", "⌫", "·", "°", "•", "—"])
if let hud { engine.residencySet.addAllocations(hud.allocations) }
```

The initializer is `init?(device:font:additionalCharacters:)` and returns nil if the font atlas or pipeline cannot be built. Its `allocations` (the vertex buffer and the glyph texture) must be in the residency set, like everything else the GPU reads.

## A frame {#frame}

From the sample's `encodeHUD`, trimmed:

```swift
func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int) {
    guard let hud else { return }
    hud.begin(viewportSize: viewportSize)

    let scale = max(viewportSize.y / 1080, 0.75)
    let title = 30 * scale, margin = 22 * scale
    let white = UIColor(srgb: SIMD4(1, 1, 1, 0.95))

    var y = margin + title
    _ = hud.text("\(level.name)   \(levelIndex + 1)/\(SampleLevel.names.count)",
                 x: margin, y: y, pointSize: title, color: white)

    let dot = 3 * scale
    hud.rect(x: viewportSize.x / 2 - dot, y: viewportSize.y / 2 - dot,
             width: dot * 2, height: dot * 2, color: white)
    hud.draw(into: encoder, frameSlot: frameSlot)
}
```

`begin(viewportSize:)` clears last frame's shapes and sets the coordinate space. Coordinates are **points with the origin at the top left**, in whatever units you pass as the viewport. The sample passes the drawable's size in pixels and scales against a 1080-pixel reference, so text is the same share of the screen on any display. Raw pixel sizes on a Retina display come out at half the size you meant.

`draw(into:frameSlot:)` uploads and draws everything since `begin`, in the order it was added: later shapes draw over earlier ones.

## What it draws {#shapes}

| Method | Draws |
| --- | --- |
| `rect(x:y:width:height:color:)` | a filled rectangle |
| `stroke(x:y:width:height:thickness:color:)` | an unfilled rectangle, as four edges |
| `line(from:to:thickness:color:)` | a line of a thickness, as a rotated quad |
| `ring(center:innerRadius:outerRadius:segments:color:)` | a filled ring; `segments` defaults to 96 |
| `fill(polygon:color:feather:)` | a filled polygon, concave or convex |
| `text(_:x:y:pointSize:color:)` | a line of text; returns its width |
| `width(of:pointSize:)` | a string's width without drawing it |

A ring with a large outer radius is a circular vignette, which is how a scope's surround is drawn.

### Polygons and feather

`fill(polygon:color:feather:)` takes an outline in order, either way round, and triangulates it by ear clipping, so concave shapes such as a letter fill correctly. The outline must be simple, with no edge crossing another; one that is not is drawn only in part.

The HUD pipeline has no multisampling, so a filled shape with a diagonal edge would be stair-stepped. `feather` (default `1`, in the HUD's own units, so a pixel when the viewport is in pixels) runs a strip around the outline that fades from the color to nothing. Pass `0` for hard edges, for a shape that must tile exactly against its neighbor. The engine's [mark](mark.html) is drawn this way.

## Text {#text}

> **`y` is the baseline, not the top.** Glyphs draw upward from it. Pass a top margin as `y` and the first line's ascenders run off the top of the screen. Put the first line at least one `pointSize` below where text should start.

Baselines make two readouts line up even when one has a descender or a comma. `text` returns the width it drew, which `SplashScreen` uses to set letters one at a time with extra spacing; `width(of:pointSize:)` measures without drawing, for centering or right-aligning.

### FontAtlas

Glyphs come from a `FontAtlas`, rasterized at launch from an installed font: `init?(device:font:additionalCharacters:)`, with the font defaulting to the monospaced system font. It rasterizes at `FontAtlas.rasterHeight` (64) and scales down, so text looks clean at HUD sizes and softens if drawn much larger. It is a bitmap atlas, not signed distance fields.

**ASCII is the default, not a limit.** Anything else, such as `×`, `·` or `⌘`, is passed in `additionalCharacters`. A character the atlas does not carry draws nothing, so the engine says so: `FontAtlas.unavailableCharacters` lists what the font could not supply, and `text` logs each missing character once. The sample's hints once read "S save" with the ⌘ silently gone, which is why.

## UIColor {#color}

`UIColor` is a color authored for the interface: sRGB, the space hex codes live in, converted to linear once using the real sRGB transfer function. The drawable re-encodes on write, so the value round-trips exactly.

```swift
let brand = UIColor(hex: 0x00C2FF)
let panel = UIColor(srgb: SIMD4(0.05, 0.06, 0.08, 0.86))
let faded = brand.withAlpha(0.5)
```

`UIColor.white`, `.black` and `.clear` are provided. Blending is premultiplied, so translucent panels composite cleanly over the scene. A shape with zero alpha is skipped.

## Limits

- **No layout, widgets or event handling.** Positions are yours; a settings screen is text and rectangles your game places, and its keys are your game's.
- **`HUDRenderer.maxVerticesPerFrame` is 8,192** per frame; anything past it is not drawn. Every rectangle and character is six vertices.
- **Text is one line per call.** Wrapping and line spacing are yours.

See [the splash](splash.html) for a full-screen overlay drawn through the HUD.
