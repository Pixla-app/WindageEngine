---
title: Your first game
description: A new Swift package that depends on Windage Engine, a minimal GameLoop, and the window and FrameRenderer set-up that puts it on screen.
---
A game is a Swift package that depends on the engine and supplies one object conforming to `GameLoop`. This page builds the smallest one that opens a window and draws something, using the same set-up the sample game uses.

## The package

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyGame",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://…/WindageEngine.git", .upToNextMinor(from: "{{version}}"))
    ],
    targets: [
        .executableTarget(
            name: "MyGame",
            dependencies: [.product(name: "WindageEngine", package: "WindageEngine")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        )
    ]
)
```

Three things in it are deliberate:

- **macOS 26 and tools 6.2**, which the engine requires. `FrameRenderer` also needs a GPU that supports Metal 4; its initializer returns `nil` otherwise.
- **`.upToNextMinor`**. Before 1.0 a minor bump may break a build and a patch never does, so this gets fixes without surprises.
- **`.defaultIsolation(MainActor.self)`**, matching the engine. `GameLoop` and `FrameRenderer` are main-actor types, and with the same default your game's code means the same thing on both sides.

A relative-path dependency works too, for an engine checkout beside the game, but then the game no longer builds from its own checkout alone.

## A minimal GameLoop

This game counts simulated seconds and draws the number with the engine's `HUDRenderer`. It draws no scene, so the frame shows `clearColor`.

```swift
import Metal
import WindageEngine

final class Game: GameLoop {
    private let hud: HUDRenderer
    private var viewportSize = SIMD2<Float>(1, 1)
    private var seconds: Double = 0

    init(engine: FrameRenderer) throws {
        hud = try HUDRenderer(device: engine.device)
        engine.residencySet.addAllocations(hud.allocations)
        engine.commitResidency()
    }

    func beginFrame() {}

    func step(deltaTime: Float) {
        seconds += Double(deltaTime)
    }

    func viewportSizeChanged(width: Int, height: Int) {
        viewportSize = SIMD2(Float(width), Float(height))
    }

    func encode(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {}

    func encodeHUD(into encoder: MTL4RenderCommandEncoder, frameSlot: Int, interpolation: Float) {
        hud.begin(viewportSize: viewportSize)
        hud.text(String(format: "%.1f s", seconds), atBaseline: SIMD2(40, 80), pointSize: 48, color: .white)
        hud.draw(into: encoder, frameSlot: frameSlot)
    }
}
```

`encodePrePasses` is left out because it has a default that does nothing; `encodeHUD` has one too. Everything the GPU touches has to be in the renderer's `residencySet`, which is why the HUD's allocations are added and committed. The viewport is in pixels, and since that is what the HUD is begun with, HUD coordinates are pixels from the top left too — the text's position is its baseline.

## Getting it on screen

The engine owns no window. A window, a view and a responder chain are your app's decisions, so `main.swift` makes them, exactly as the sample's does:

```swift
import AppKit
import MetalKit
import WindageEngine

let application = NSApplication.shared
application.setActivationPolicy(.regular)

guard let device = MTLCreateSystemDefaultDevice() else { exit(1) }

let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
                      styleMask: [.titled, .closable, .resizable, .miniaturizable],
                      backing: .buffered, defer: false)
window.title = "My Game"
window.center()

let engine: FrameRenderer
do {
    engine = try FrameRenderer(device: device)
} catch {
    print(error)   // FrameRendererError: no Metal 4, or something a frame needs
    exit(1)
}

let view = MTKView(frame: window.contentLayoutRect, device: device)
view.colorPixelFormat = FrameRenderer.colorPixelFormat
view.depthStencilPixelFormat = FrameRenderer.depthPixelFormat
view.isPaused = true
view.enableSetNeedsDisplay = false
window.contentView = view

guard let game = try? Game(engine: engine) else { exit(1) }
engine.game = game
engine.clearColor = MTLClearColor(red: 0.42, green: 0.55, blue: 0.70, alpha: 1)

guard let metalLayer = view.layer as? CAMetalLayer else { exit(1) }
let displayLink = engine.makeDisplayLink(for: metalLayer)
displayLink.add(to: .main, forMode: .common)

window.makeKeyAndOrderFront(nil)
application.activate(ignoringOtherApps: true)
application.run()
```

Then:

```sh
swift run MyGame
```

### What to watch for

- **The view hosts the layer; it does not drive frames.** `CAMetalDisplayLink` does. Leaving MetalKit's own timer running as well (`isPaused = false`) would ask for two frames of work per frame.
- **`engine.game` is weak.** Something else has to keep the game alive. In `main.swift` the top-level `let game` does; in an app delegate, store it.
- **You own the display link** and must invalidate it when you are done with it.
- **`clearColor` is radiance**, tone mapped like the rest of the scene, so it will not arrive on screen as exactly those numbers. Interface colors drawn in `encodeHUD` do.
- **Shaders under `swift run`.** SwiftPM's command line compiles no Metal. Ship your `.metal` source as a `.copy` resource and load it through `ShaderLibrary.make(device:bundle:sourceNamed:)`, which compiles the source at runtime when no compiled library exists.
- **Print unbuffered.** `print` is fully buffered when stdout is not a terminal; the sample calls `setbuf(stdout, nil)` so a piped run shows anything at all.

## Input

Keys reach the game through the view. The sample subclasses `MTKView`, overrides `keyDown`, `keyUp`, `flagsChanged` (Shift, Control, Option and Command arrive only there) and the mouse events, and hands them to an `InputState`, started once with `start()`. Poll it in `beginFrame`. See [input](input.html).

## Where to go next

- [GameLoop](game-loop.html) — each requirement, frame slots and the order of a frame.
- [Fixed timestep](fixed-timestep.html) — why `step` always gets the same delta, and how to draw between steps.
- [Camera](camera.html) and [meshes](meshes.html) — a scene to draw in `encode`.
- [The sample game](sample.html) — split into a window-free core and an app, which is the shape to copy as the game grows.
